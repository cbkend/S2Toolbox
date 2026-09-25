<#
.SYNOPSIS
    Centralized validation services for S2 Toolbox.

.DESCRIPTION
    Provides reusable, side-effect-free validation functions for import data,
    CSV files, file paths, S2 resource identifiers, compatibility rules, and
    documented resource relationships.

.NOTES
    FileName: S2.Validation.psm1
    Author     : Brian Kendrick
    Application: S2 Toolbox
    Requires   : Windows PowerShell 5.1
    Version    : 1.0.0

.CHANGELOG
    1.0.0
        - Initial release.
#>

#requires -Version 5.1
Set-StrictMode -Version Latest

#region helpers
function Assert-S2QueryCollection {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [hashtable]$Query,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    if ($null -eq $Query) {
        return
    }

    foreach ($key in $Query.Keys) {
        $keyText = [string]$key

        if ([string]::IsNullOrWhiteSpace($keyText)) {
            $Message = 'Query parameter names cannot be null, empty, or whitespace.'

            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name

            throw [System.InvalidOperationException]::new($Message)
        }

        $value = $Query[$key]

        if ($null -eq $value) {
            continue
        }

        if (
            $value -is [System.Collections.IDictionary] -or
            (
                $value -is [System.Collections.IEnumerable] -and
                $value -isnot [string]
            )
        ) {
            $Message = (
                "Query parameter '{0}' must contain a scalar value." -f
                $keyText
            )

            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name

            throw [System.InvalidOperationException]::new($Message)
        }
    }

    Write-S2Verbose `
        -Message 'Validated Web API query parameters.' `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
}

function Assert-S2HeaderCollection {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [hashtable]$Headers,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    if ($null -eq $Headers) {
        return
    }

    foreach ($key in $Headers.Keys) {
        $headerName = [string]$key

        if ([string]::IsNullOrWhiteSpace($headerName)) {
            $Message = 'HTTP header names cannot be null, empty, or whitespace.'

            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name

            throw [System.InvalidOperationException]::new($Message)
        }

        # Prevent invalid header-name characters and line injection.
        if ($headerName -notmatch '^[!#$%&''*+\-.^_`|~0-9A-Za-z]+$') {
            $Message = "HTTP header name '$headerName' is not valid."

            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name

            throw [System.InvalidOperationException]::new($Message)
        }

        $value = $Headers[$key]

        if ($null -eq $value) {
            $Message = "HTTP header '$headerName' cannot contain a null value."

            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name

            throw [System.InvalidOperationException]::new($Message)
        }

        $valueText = [string]$value

        if ($valueText -match '[\r\n]') {
            $Message = (
                "HTTP header '{0}' contains an invalid newline character." -f
                $headerName
            )

            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name

            throw [System.InvalidOperationException]::new($Message)
        }
    }

    Write-S2Verbose `
        -Message 'Validated Web API request headers.' `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
}

function Test-S2DuplicateValues {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [object[]]$Data,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Column,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $duplicates = @()

    $groups =
    $Data |
    Group-Object -Property $Column |
    Where-Object {
        -not [string]::IsNullOrWhiteSpace($_.Name) -and
        $_.Count -gt 1
    }

    foreach ($group in $groups) {
        $duplicates += [PSCustomObject]@{
            Column = $Column
            Value  = $group.Name
            Count  = $group.Count
        }
    }

    Write-S2Debug `
        -Message "Checking duplicate values in column '$Column'." `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name

    return $duplicates
}

function Test-S2StringLength {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value,

        [int]$MinimumLength = 0,

        [int]$MaximumLength = 2147483647,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $length = $Value.Length

    Write-S2Verbose `
        -Message (
        "Testing string length :: Length={0} :: Min={1} :: Max={2}" -f
        $length,
        $MinimumLength,
        $MaximumLength
    ) `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name

    return (
        $length -ge $MinimumLength -and
        $length -le $MaximumLength
    )
}

function Test-S2DateFormat {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Value,

        [Parameter(Mandatory)]
        [string]$Format,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $dateValue = [datetime]::MinValue

    $isValid =
    [datetime]::TryParseExact(
        $Value,
        $Format,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$dateValue
    )

    Write-S2Verbose `
        -Message (
        "Testing date format '{0}' against '{1}'." -f
        $Value,
        $Format
    ) `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name

    return $isValid
}

function Test-S2ImportRecord {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [psobject]$Record,

        [Parameter(Mandatory)]
        [string[]]$RequiredFields,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $errors = @()

    foreach ($field in $RequiredFields) {
        if (
            -not $Record.PSObject.Properties[$field] -or
            [string]::IsNullOrWhiteSpace(
                [string]$Record.$field
            )
        ) {
            $errors +=
            "Required field '$field' is missing or empty."
        }
    }

    Write-S2Debug `
        -Message "Validated import record." `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name

    return [PSCustomObject]@{
        Valid  = ($errors.Count -eq 0)
        Errors = $errors
    }
}
#endregion Helpers

#region Authenication
function Test-S2HostName {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$HostName,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $value = $HostName.Trim()
    $value = $value -replace '^https?://', ''
    $value = $value.TrimEnd('/')

    if ([string]::IsNullOrWhiteSpace($HostName)) {
        return $false
    }

    if ($value -match '[/?#]') {
        return $false
    }

    # Bracketed IPv6, such as [2001:db8::1]
    if ($value.StartsWith('[') -and $value.EndsWith(']')) {
        $value = $value.Substring(1, $value.Length - 2)
    }

    $ipAddress = $null

    if (
        [System.Net.IPAddress]::TryParse(
            $value,
            [ref]$ipAddress
        )
    ) {
        return $true
    }

    # DNS hostname/FQDN validation.
    if ($value.Length -gt 253) {
        return $false
    }

    $labels = $value.Split('.')

    foreach ($label in $labels) {
        if (
            [string]::IsNullOrWhiteSpace($label) -or
            $label.Length -gt 63 -or
            $label -notmatch '^?:[A-Za-z0-9-]{0,61}[A-Za-z0-9]?$'
        ) {
            return $false
        }
    }

    $Message = "Validated S2 host name '$HostName'."

    Write-S2Verbose `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name

    return $true
}

function Assert-S2CredentialValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    if ([string]::IsNullOrWhiteSpace($Credential.UserName)) {
        $Message = 'Credential must contain a username.'
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name

        throw [System.InvalidOperationException]::new($Message)
    }

    if ($Credential.Password.Length -le 0) {
        $Message = 'Credential must contain a password.'
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name

        throw [System.InvalidOperationException]::new($Message)
    }
    $Message = 'Check if User and Password exist.'
    Write-S2Debug `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
}

function ConvertTo-S2AuthenticationHostName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$HostName,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $value = $HostName.Trim() -replace '^https?://', ''
    $value = $value.TrimEnd('/')

    if (-not (Test-S2HostName -HostName $value -LogFile $LogFile)) {
        $Message = "HostName '$HostName' is not a valid hostname or IP address."

        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name

        throw [System.InvalidOperationException]::new($Message)
    }
    
    if ([string]::IsNullOrWhiteSpace($value) -or $value -match '[/?#]') {
        $Message = "HostName '$HostName' is not a valid host name or IP address."
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name

        throw [System.InvalidOperationException]::new($Message)
    }
    $Message = "HostName '$HostName' clean up."
    Write-S2Debug `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
    return $value
}
#endregion Authenication

#region Api.Common
function Assert-S2ApiConnection {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Connection,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    if (
        $Connection.PSTypeNames -notcontains
        'S2.ApiConnection'
    ) {
        $Message = 'Invalid S2 connection object.'
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }

    foreach ($property in @(
            'HostName',
            'Protocol',
            'BaseUri'
        )) {

        if (
            $null -eq $Connection.PSObject.Properties[$property] -or
            [string]::IsNullOrWhiteSpace(
                [string]$Connection.$property
            )
        ) {

            $Message = "Connection is missing required property '$property'."
            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name
            throw [System.InvalidOperationException]::new($Message)
        }
    }

    if ([string]$Connection.Protocol -notin @(
            'http',
            'https'
        )) {

        $Message = "Connection protocol must be 'http' or 'https'."
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }
}

function Assert-S2WebConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject]$Connection,
        
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    if (
        $Connection.PSTypeNames -notcontains
        'S2.WebAuthenticationContext'
    ) {
        $Message = 'Invalid S2 web connection object.'
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }

    if (
        $null -eq $Connection.PSObject.Properties['WebSession'] -or
        $null -eq $Connection.WebSession
    ) {
        $Message = 'Web connection does not contain an authenticated WebSession.'
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
        
    }

    if (
        $Connection.WebSession -isnot
        [Microsoft.PowerShell.Commands.WebRequestSession]
    ) {
        $Message = 'WebSession is not a valid WebRequestSession object.'
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }

    if (
        $null -ne $Connection.PSObject.Properties['AuthenticationType'] -and
        $Connection.AuthenticationType -ne 'Web'
    ) {
        $Message = ( "Connection authentication type is '$($Connection.AuthenticationType)' " + "but a Web connection is required." )
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }
}

function Assert-S2NBApiConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject]$Connection,
        
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    Assert-S2ApiConnection -Connection $Connection -LogFile $LogFile

    if (
        $null -eq $Connection.PSObject.Properties['SessionId'] -or
        [string]::IsNullOrWhiteSpace(
            [string]$Connection.SessionId
        )
    ) {
        $Message = ( 'NBAPI connection does not contain a valid SessionId.')
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }

    if (
        $null -ne $Connection.PSObject.Properties['AuthenticationType'] -and
        $Connection.AuthenticationType -ne 'NBAPI'
    ) {
        $Message = ( "Connection authentication type is '$($Connection.AuthenticationType)' " + "but an NBAPI connection is required." )
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }
}
#endregion Api.Common

#region Security
function Test-S2PathSafety {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $Message = "Test Path '$Path'."
    Write-S2Verbose `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
        return -not [string]::IsNullOrWhiteSpace($fullPath)
    }
    catch {
        return $false
    }
}

function Test-S2CertificateThumbprint {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Thumbprint,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $normalizedThumbprint = $Thumbprint -replace '\s', ''
    $Message = "Testing for Certificate Thumbprint."
    Write-S2Verbose `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name

    return $normalizedThumbprint -match '^[A-Fa-f0-9]{40}$'
}

function Test-S2SecretExposure {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $patterns = @(
        '(?i)\bpassword\s*[=:]',
        '(?i)\bpasswd\s*[=:]',
        '(?i)\bapikey\s*[=:]',
        '(?i)\bapi[_-]?key\s*[=:]',
        '(?i)\btoken\s*[=:]',
        '(?i)\bsessionid\s*[=:]',
        '(?i)\bsecret\s*[=:]',
        '(?i)\bauthorization\s*[=:]'
    )
    $Message = "Testing for exposure of known sensitive data."
    Write-S2Debug `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name

    foreach ($pattern in $patterns) {
        if ($Text -match $pattern) {
            return $true
        }
    }

    return $false
}
#endregion Security 

#region NBAPI
function Assert-S2NBApiDefinition {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $NBApiCommand,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $definition = $NBApiCommand

    foreach ($property in @(
            'Category',
            'Action',
            'Description'
        )) {
        if (
            -not $definition.ContainsKey($property) -or
            [string]::IsNullOrWhiteSpace(
                [string]$definition[$property]
            )
        ) {
            $Message = ( "NBAPI command '{0}' is missing required property '{1}'." -f $NBApiCommand, $property )
            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name
            throw [System.InvalidOperationException]::new($Message)
        }
        else {
            return $true
        }
    }    
}
#endregion NBAPI 

#region RestApi
function Assert-S2RestEndpointValues {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [AllowNull()]
        [hashtable]$Value,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $endpointKey = $script:S2RestEndpoints.Keys |
    Where-Object { $_ -ieq $Name } |
    Select-Object -First 1

    if (-not $endpointKey) {
        $Message = "Unknown S2 REST endpoint '$Name'."
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }

    $definition = $script:S2RestEndpoints[$endpointKey]
    $path = [string]$definition.Path

    if ($null -ne $Value) {
        foreach ($replacementKey in $Value.Keys) {
            $replacementValue = [string]$Value[$replacementKey]

            if ([string]::IsNullOrWhiteSpace($replacementKey)) {
                $Message = ( "Replacement value '{0}' for endpoint '{1}' cannot be empty." -f $replacementKey, $endpointKey )
                Write-S2Error `
                    -Message $Message `
                    -LogFile $LogFile `
                    -FileName $PSCommandPath `
                    -Source $MyInvocation.MyCommand.Name
                throw [System.InvalidOperationException]::new($Message)
            }

            if (
                $replacementKey -ieq 'id' -and
                $replacementValue -notmatch '^[1-9]\d*$'
            ) {
                $Message = ( "Replacement value 'id' for endpoint '{0}' must be a positive integer." -f $endpointKey )
                Write-S2Error `
                    -Message $Message `
                    -LogFile $LogFile `
                    -FileName $PSCommandPath `
                    -Source $MyInvocation.MyCommand.Name
                throw [System.InvalidOperationException]::new($Message)
            }

            $token = '{' + [string]$replacementKey + '}'
            $path = $path.Replace($token, $replacementValue)
        }
    }

    if ($path -match '\{[^}]+\}') {
        $Message = ( "S2 REST endpoint '{0}' requires one or more replacement values." -f $endpointKey )
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }

    return $true
}
#endregion RestApi

#region WebApi
function Assert-S2WebEndpointDefinition {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [AllowNull()]
        [hashtable]$Value,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )
    $endpointKey = $script:S2WebApiEndpoints.Keys |
    Where-Object { $_ -ieq $Name } |
    Select-Object -First 1

    if (-not $endpointKey) {
        $Message = "Unknown S2 Web API endpoint '$Name'."
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }

    $definition = $script:S2WebApiEndpoints[$endpointKey]
    $path = [string]$definition.Path

    if ($null -ne $Value) {
        foreach ($replacementKey in $Value.Keys) {
            $token = '{' + [string]$replacementKey + '}'
            $path = $path.Replace(
                $token,
                [string]$Value[$replacementKey]
            )
        }
    }

    if ($path -match '\{[^}]+\}') {
        $Message = ( "S2 Web API endpoint '{0}' requires one or more replacement values." -f $endpointKey )
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }
    return $true
}

function Assert-S2WebRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Get', 'Post', 'Put', 'Delete')]
        [string]$Method,

        [AllowNull()]
        [object]$Body,

        [Parameter(Mandatory)]
        [ValidateSet('Raw', 'Json', 'JsonForm')]
        [string]$BodyFormat,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    if ($Method -eq 'Get' -and $null -ne $Body) {
        $Message = 'A request body cannot be supplied for a GET Web API request.'

        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name

        throw [System.InvalidOperationException]::new($Message)
    }

    if (
        $null -ne $Body -and
        $BodyFormat -eq 'JsonForm' -and
        $Body -is [string] -and
        [string]::IsNullOrWhiteSpace($Body)
    ) {
        $Message = 'A JsonForm request body cannot be empty or whitespace.'

        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name

        throw [System.InvalidOperationException]::new($Message)
    }

    Write-S2Verbose `
        -Message (
        "Validated Web API request :: Method={0} :: BodyFormat={1}" -f
        $Method,
        $BodyFormat
    ) `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
}

function Assert-S2CsrfRequest {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject]$Connection,

        [switch]$IncludeCsrfToken,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$CsrfHeaderName,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    if (-not $IncludeCsrfToken.IsPresent) {
        return $null
    }

    if (
        $null -eq $Connection.PSObject.Properties['CsrfToken'] -or
        [string]::IsNullOrWhiteSpace([string]$Connection.CsrfToken)
    ) {
        $Message = 'The connection does not contain a CSRF token.'

        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name

        throw [System.InvalidOperationException]::new($Message)
    }

    if ([string]::IsNullOrWhiteSpace($CsrfHeaderName)) {
        $Message = (
            'CsrfHeaderName is required when IncludeCsrfToken is specified.'
        )

        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name

        throw [System.InvalidOperationException]::new($Message)
    }

    if ($CsrfHeaderName -match '[\r\n]') {
        $Message = 'CsrfHeaderName contains an invalid newline character.'

        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name

        throw [System.InvalidOperationException]::new($Message)
    }

    Write-S2Verbose `
        -Message "Validated CSRF request header '$CsrfHeaderName'." `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name

    return [string]$Connection.CsrfToken
}
#endregion WebApi

#region CSV

function Test-S2CsvFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )
    $Message = "Testing CSV file '$Path'. $_"
    Write-S2Information `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
    return (Test-Path -Path $Path)
}

function Test-S2CsvColumns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Data,

        [Parameter(Mandatory)]
        [string[]]$RequiredColumns,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    if (-not $Data -or $Data.Count -eq 0) {
        $Message = "CSV contains no records."
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }

    $columns = $Data[0].PSObject.Properties.Name

    foreach ($column in $RequiredColumns) {
        if ($column -notin $columns) {
            return $false
        }
        $Message = ("'{0}' is in the header of the csv.'." -f $column)
        Write-S2Information `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
    }

    return $true
}

function Test-S2CsvRequiredValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Data,

        [Parameter(Mandatory)]
        [string[]]$RequiredColumns,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $errors = @()

    $rowNumber = 0

    foreach ($row in $Data) {

        $rowNumber++

        foreach ($column in $RequiredColumns) {

            if ([string]::IsNullOrWhiteSpace($row.$column)) {

                $errors += [PSCustomObject]@{
                    Row    = $rowNumber
                    Column = $column
                    Value  = $row.$column
                }
            }
        }
    }
    $Message = "Checking for Errors in Required Values of CSV"
    Write-S2Debug `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
    return $errors
}

function Get-S2CsvSchemaValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Data,

        [Parameter(Mandatory)]
        [string[]]$RequiredColumns,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )
    $Message = "Getting CSV Schema for Validation"
    Write-S2Debug `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
    return [PSCustomObject]@{
        Valid           = (Test-S2CsvColumns -Data $Data -RequiredColumns $RequiredColumns -LogFile $LogFile)
        ExistingColumns = (Get-S2CsvColumns -Data $Data -LogFile $LogFile)
        RequiredColumns = $RequiredColumns
    }
}

#endregion CSV

#region Access Level

function Set-S2AccessLevelVerificationBatchFailure {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object[]]$ActionResult,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object[]]$VerificationPlan,

        [Parameter(Mandatory)]
        [ValidateSet('Add', 'Modify', 'Delete')]
        [string]$Operation,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    foreach ($plan in @($VerificationPlan)) {
        $resultRecord = @($ActionResult) | Where-Object {
            $_.RowNumber -eq $plan.RowNumber
        } | Select-Object -First 1

        if ($null -ne $resultRecord) {
            $resultRecord.Status = 'Failed'
            $resultRecord.Verified = $false
            $resultRecord.Message = $Message
            $resultRecord.VerificationMessage = $Message
        }

        [pscustomobject]@{
            PSTypeName          = 'S2.ResourceVerificationResult'
            Resource            = 'AccessLevel'
            Operation           = $Operation
            RowNumber           = $plan.RowNumber
            Name                = $plan.Name
            ExpectedKey         = [string]$plan.AccessLevelKey
            ActualKey           = ''
            MatchedBy           = ''
            Verified            = $false
            Status              = 'VerificationFailed'
            Message             = $Message
            VerificationMessage = $Message
            Errors              = @($Message)
            Plan                = $plan
            ActualRecord        = $null
        }
    }
}
#endregion Access Level

#region Public Exports
Export-ModuleMember -Function @(
    'Test-S2HostName',
    'Assert-S2QueryCollection',
    'Assert-S2HeaderCollection',
    'Assert-S2CredentialValue',
    'ConvertTo-S2AuthenticationHostName',
    'Assert-S2ApiConnection',
    'Assert-S2WebConnection',
    'Assert-S2NBApiConnection',
    'Test-S2PathSafety',
    'Test-S2CertificateThumbprint',
    'Test-S2SecretExposure',
    'Initialize-S2NBAPICatalog',
    'Assert-S2NBApiDefinition',
    'Initialize-S2RestApiCatalog',
    'Assert-S2RestEndpointValues',
    'Assert-S2WebRequest',
    'Assert-S2CsrfRequest',
    'Test-S2CsvFile',
    'Test-S2CsvColumns',
    'Test-S2CsvRequiredValues',
    'Get-S2CsvSchemaValidation',
    'Test-S2DuplicateValues',
    'Test-S2StringLength',
    'Test-S2DateFormat',
    'Test-S2ImportRecord',
    'Set-S2AccessLevelVerificationBatchFailure'
)
#endregion Public Exports
