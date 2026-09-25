<#
.SYNOPSIS
    Provides separate NetBox Web and NBAPI authentication workflows for S2 Toolbox.
.DESCRIPTION
    Centralizes authentication while keeping the NetBox Web session and XML NBAPI
    session as distinct connection types.

    Web authentication uses POST /j_security_check and returns an
    S2.WebAuthenticationContext containing the authenticated WebRequestSession.

    NBAPI authentication uses the Login and Logout commands exported by
    S2.NBAPI.psm1 and stores the returned session ID on an S2.ApiConnection.

    The module does not log passwords, cookies, CSRF tokens, or NBAPI session IDs.
.NOTES
    FileName   : S2.Authentication.psm1
    Author     : Brian Kendrick
    Application: S2 Toolbox
    Requires   : Windows PowerShell 5.1
    Version    : 2.0.0
.CHANGELOG
    2.0.0
        - Separated Web POST authentication from NBAPI authentication.
        - Replaced legacy S2.Api.psm1 dependencies with S2.NBAPI.psm1 commands.
        - Added explicit dependency validation for each authentication workflow.
        - Preserved Connect-S2ApiSession and Disconnect-S2ApiSession as wrappers.
#>

#requires -Version 5.1
Set-StrictMode -Version Latest

#region Private validation and utility functions

function Assert-S2NBApiDependency {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile

    )

    foreach ($commandName in @('New-S2NBApiCommandXml', 'Invoke-S2NBApiCommand')) {
        if ($null -eq (Get-Command -Name $commandName -ErrorAction SilentlyContinue)) {
            $Message = "Required command '$commandName' was not found. Import S2.NBAPI.psm1 first."
            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name
            throw [System.InvalidOperationException]::new($Message)
        }
    }
}

function New-S2NBApiLoginParameters {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$UserName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Password,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $document = New-Object System.Xml.XmlDocument
    $parameters = $document.CreateElement('PARAMS')

    $usernameNode = $document.CreateElement('USERNAME')
    $usernameNode.InnerText = $UserName
    [void]$parameters.AppendChild($usernameNode)

    $passwordNode = $document.CreateElement('PASSWORD')
    $passwordNode.InnerText = $Password
    [void]$parameters.AppendChild($passwordNode)

    
    # Create a redacted copy for logging
    $logDocument = New-Object System.Xml.XmlDocument
    $logDocument.LoadXml($parameters.OuterXml)
    $logPasswordNode = $logDocument.SelectSingleNode('/PARAMS/PASSWORD')
    if ($null -ne $logPasswordNode) {
        $logPasswordNode.InnerText = '********'
    }
    $Message = "New-S2NBApiCommandXml for login $($logDocument.OuterXml)"
    Write-S2Debug `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
    return $parameters.OuterXml
}
#endregion Private validation and utility functions

#region NetBox Web POST authentication
function Connect-S2WebSession {
    <#
    .SYNOPSIS
        Authenticates to the NetBox Web application by HTTP POST.
    .DESCRIPTION
        Posts a PSCredential to /j_security_check and returns a distinct Web
        authentication context. Use this workflow for scripts that call NetBox
        Web or internal Web API endpoints.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$HostName,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]$Credential,

        [ValidateSet('http', 'https')]
        [string]$Protocol = 'https',

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    Assert-S2CredentialValue -Credential $Credential -LogFile $LogFile

    $normalizedHost = ConvertTo-S2AuthenticationHostName -HostName $HostName -LogFile $LogFile
    $normalizedProtocol = $Protocol.ToLowerInvariant()
    $baseUri = '{0}://{1}' -f $normalizedProtocol, $normalizedHost
    $loginUri = '{0}/j_security_check' -f $baseUri
    $networkCredential = $Credential.GetNetworkCredential()
    $body = @{
        username = $Credential.UserName
        password = $networkCredential.Password
    }

    try {
        $webSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        $null = Invoke-WebRequest `
            -UseBasicParsing `
            -Uri $loginUri `
            -Method Post `
            -ContentType 'application/x-www-form-urlencoded' `
            -Body $body `
            -WebSession $webSession `
            -ErrorAction Stop

        $cookies = @($webSession.Cookies.GetCookies($baseUri))
        $dotSessionCookie = $cookies |
        Where-Object { $_.Name -eq '.sessionId' } |
        Select-Object -First 1
        $sessionCookie = $cookies |
        Where-Object { $_.Name -in @('sessionId', '.session_id', 'session_id') } |
        Select-Object -First 1

        if ($null -eq $dotSessionCookie -and $null -eq $sessionCookie) {
            $Message = 'Web authentication completed without a recognized session cookie.'
            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name
            throw [System.InvalidOperationException]::new($Message)
        }

        $Message = ("Web authentication succeeded for '{0}' on '{1}'." -f $Credential.UserName, $normalizedHost) 
        Write-S2Information `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name

        return [pscustomobject]@{
            PSTypeName         = 'S2.WebAuthenticationContext'
            AuthenticationType = 'Web'
            HostName           = $normalizedHost
            Protocol           = $normalizedProtocol
            BaseUri            = $baseUri
            UserName           = $Credential.UserName
            WebSession         = $webSession
            SessionId          = if ($dotSessionCookie) { $dotSessionCookie.Value } else { $null }
            SessionKey         = if ($sessionCookie) { $sessionCookie.Value } else { $null }
            CsrfToken          = $null
        }
    }
    catch {
        $Message = ("Web authentication failed for '{0}' on '{1}': {2}" -f $Credential.UserName, $normalizedHost, $_.Exception.Message)
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }
    finally {
        if ($null -ne $networkCredential) {
            $networkCredential.Password = $null
        }
        if ($null -ne $body) {
            $body.password = $null
        }
    }
}

function Get-S2CsrfToken {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject]$Connection,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $assertCommand = Get-Command -Name 'Assert-S2WebConnection' -ErrorAction SilentlyContinue
    if ($null -ne $assertCommand) {
        Assert-S2WebConnection  -Connection $Connection -LogFile $LogFile
    }
    $framesetUri = '{0}/frameset/' -f $Connection.BaseUri

    try {
        $response = Invoke-WebRequest `
            -UseBasicParsing `
            -Uri $framesetUri `
            -Method Get `
            -WebSession $Connection.WebSession `
            -Headers @{
            Referer                     = '{0}/login/' -f $Connection.BaseUri
            'Upgrade-Insecure-Requests' = '1'
        } `
            -ErrorAction Stop

        $content = [string]$response.Content
        $patterns = @(
            '(?i)\bcsrft\s*=\s*["'']?([^"'';\s<]+)',
            '(?i)["'']csrft["'']\s*:\s*["'']([^"'']+)["'']',
            '(?i)name=["'']csrft["'']\s+value=["'']([^"'']+)["'']'
        )

        $token = $null
        foreach ($pattern in $patterns) {
            $match = [regex]::Match($content, $pattern)
            if ($match.Success) {
                $token = $match.Groups[1].Value.Trim()
                break
            }
        }

        if ([string]::IsNullOrWhiteSpace($token)) {
            $Message = 'The frameset response did not contain a recognizable CSRF token.'
            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name
            throw [System.InvalidOperationException]::new($Message) 
        }

        $Connection.CsrfToken = $token
        $Message = ("CSRF token retrieval succeeded for '{0}'." -f $Connection.HostName)
        Write-S2Information `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name

        return $token
    }
    catch {
        $Message = ("CSRF token retrieval failed for '{0}': {1}" -f $Connection.HostName, $_.Exception.Message)
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message) 
    }
}

function Disconnect-S2WebSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject]$Connection,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $assertCommand = Get-Command -Name 'Assert-S2WebConnection' -ErrorAction SilentlyContinue
    if ($null -ne $assertCommand) {
        Assert-S2WebConnection  -Connection $Connection -LogFile $LogFile
    }
    $logoutUri = '{0}/login/?src=sessionexpired' -f $Connection.BaseUri

    try {
        $null = Invoke-WebRequest `
            -UseBasicParsing `
            -Uri $logoutUri `
            -Method Get `
            -WebSession $Connection.WebSession `
            -Headers @{ Referer = '{0}/frameset/' -f $Connection.BaseUri } `
            -ErrorAction Stop
        $Message = ("Web logout succeeded for '{0}' on '{1}'." -f $Connection.UserName, $Connection.HostName)
        Write-S2Information `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
    }
    catch {
        $Message = ("Web logout failed for '{0}': {1}" -f $Connection.HostName, $_.Exception.Message)
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message) 
    }
    finally {
        $Connection.SessionId = $null
        $Connection.SessionKey = $null
        $Connection.CsrfToken = $null
        $Connection.WebSession = $null
    }
}
#endregion NetBox Web POST authentication

#region NBAPI authentication
function Connect-S2NBApiSession {
    <#
    .SYNOPSIS
        Authenticates through the XML NBAPI Login command.
    .DESCRIPTION
        Uses New-S2NBApiCommandXml and Invoke-S2NBApiCommand from S2.NBAPI.psm1.
        Use this workflow for scripts that execute NBAPI commands.
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject]$Connection,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    Assert-S2NBApiDependency -LogFile $LogFile
    Assert-S2ApiConnection -Connection $Connection -LogFile $LogFile
    Assert-S2CredentialValue -Credential $Credential -LogFile $LogFile

    $networkCredential = $Credential.GetNetworkCredential()
    $loginParameters = $null

    try {
        $loginParameters = New-S2NBApiLoginParameters `
            -UserName $Credential.UserName `
            -Password $networkCredential.Password `
            -LogFile $LogFile

        [xml]$commandXml = New-S2NBApiCommandXml `
            -Command 'Login' `
            -CommandParameters $loginParameters `
            -LogFile $LogFile 

        $result = Invoke-S2NBApiCommand `
            -Connection $Connection `
            -Name 'Login' `
            -CommandXml $commandXml `
            -LogFile $LogFile 

        $sessionId = [string]$result.NETBOX.sessionid
        if ([string]::IsNullOrWhiteSpace($sessionId)) {
            $Message = 'NBAPI Login succeeded without returning a session ID.'
            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name
            throw [System.InvalidOperationException]::new($Message)
        }

        if ($null -eq $Connection.PSObject.Properties['SessionId']) {
            $Connection | Add-Member -MemberType NoteProperty -Name SessionId -Value $sessionId
        }
        else {
            $Connection.SessionId = $sessionId
        }

        if ($null -eq $Connection.PSObject.Properties['AuthenticationType']) {
            $Connection | Add-Member -MemberType NoteProperty -Name AuthenticationType -Value 'NBAPI'
        }
        else {
            $Connection.AuthenticationType = 'NBAPI'
        }
        $Message = ("NBAPI authentication succeeded for '{0}' on '{1}'." -f $Credential.UserName, $Connection.HostName)
        Write-S2Information `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name

        return $Connection
    }
    catch {
        $Message = ("NBAPI authentication failed for '{0}' on '{1}': {2}" -f $Credential.UserName, $Connection.HostName, $_.Exception.Message)
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }
    finally {
        if ($null -ne $networkCredential) {
            $networkCredential.Password = $null
        }
        $loginParameters = $null
    }
}

function Disconnect-S2NBApiSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject]$Connection,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    Assert-S2NBApiDependency -LogFile $LogFile

    Assert-S2ApiConnection `
        -Connection $Connection `
        -LogFile $LogFile

    if (
        $null -eq $Connection.PSObject.Properties['SessionId'] -or
        [string]::IsNullOrWhiteSpace(
            [string]$Connection.SessionId
        )
    ) {
        $Message = (
            "NBAPI logout skipped for '{0}' because no session ID is present." `
                -f $Connection.HostName
        )

        Write-S2Warning `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name

        return
    }

    Assert-S2NBApiConnection `
        -Connection $Connection `
        -LogFile $LogFile

    try {
        [xml]$commandXml = New-S2NBApiCommandXml `
            -Command 'Logout' `
            -CommandParameters '' `
            -SessionId $Connection.SessionId `
            -LogFile $LogFile 

        $null = Invoke-S2NBApiCommand `
            -Connection $Connection `
            -Name 'Logout' `
            -CommandXml $commandXml `
            -LogFile $LogFile 

        $Message = ("NBAPI logout succeeded for '{0}'." -f $Connection.HostName)
        Write-S2Information `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
    }
    catch {
        $Message = ("NBAPI logout failed for '{0}': {1}" -f $Connection.HostName, $_.Exception.Message)
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message) 
    }
    finally {
        $Connection.SessionId = $null
        $Connection.AuthenticationType = $null
    }
}
#endregion NBAPI authentication

#region Public Exports
Export-ModuleMember -Function @(
    'Connect-S2WebSession',
    'Get-S2CsrfToken',
    'Disconnect-S2WebSession',
    'Connect-S2NBApiSession',
    'Disconnect-S2NBApiSession'
)
#endregion Public Exports
