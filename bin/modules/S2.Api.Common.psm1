<#
.SYNOPSIS
    Provides shared API infrastructure functions for the S2 Toolbox.

.DESCRIPTION
    Centralizes connection management, session handling,
    URI construction,  validation, and utility
    functions used by the S2 API modules.

    This module is consumed by:

        S2.NBAPI.psm1
        S2.RestApi.psm1
        S2.WebApi.psm1

    and future service modules.
.NOTES
    FileName   : S2.Api.Common.psm1
    Author     : Brian Kendrick
    Application: S2 Toolbox
    Requires   : Windows PowerShell 5.1
    Version    : 1.0.0

.CHANGELOG
    1.0.0
        - Refactored from S2.Api.psm1
#>

#requires -Version 5.1
Set-StrictMode -Version Latest

#region Connection Functions

function New-S2ApiConnection {

    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$HostName,

        [ValidateSet('http', 'https')]
        [string]$Protocol = 'https',

        [AllowNull()]
        [AllowEmptyString()]
        [string]$SessionId,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$CsrfToken,

        [AllowNull()]
        [AllowEmptyString()]
        [Microsoft.PowerShell.Commands.WebRequestSession]$WebSession,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $normalizedHost = $HostName.Trim()
    $normalizedHost = $normalizedHost -replace '^https?://', ''
    $normalizedHost = $normalizedHost.TrimEnd('/')

    if ([string]::IsNullOrWhiteSpace($normalizedHost)) {
        $Message = 'HostName cannot be empty.'
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }

    $Message = ("Build S2 API connection for {0}." -f $normalizedHost)
    Write-S2Information `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name

    [pscustomobject]@{
        PSTypeName         = 'S2.ApiConnection'
        HostName           = $normalizedHost
        Protocol           = $Protocol.ToLowerInvariant()
        AuthenticationType = $null
        SessionId          = $SessionId
        CsrfToken          = $CsrfToken
        WebSession         = $WebSession
        BaseUri            = '{0}://{1}' -f ( $Protocol.ToLowerInvariant()), $normalizedHost
    }
}

#endregion Connection Functions

#region Session Functions

function New-S2WebSession {

    [CmdletBinding()]
    [OutputType([Microsoft.PowerShell.Commands.WebRequestSession])]
    param(
        [Parameter(Mandatory)]
        [psobject]$Connection,
        
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    Assert-S2WebConnection -Connection $Connection -LogFile $LogFile

    if ($null -ne $Connection.WebSession -and
        $Connection.WebSession -is
        [Microsoft.PowerShell.Commands.WebRequestSession]) {

        $Message = "Build S2 Web session :: Host=$($Connection.HostName)"
        Write-S2Information `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name

        return $Connection.WebSession
    }
    else {
        $Message = "Build S2 Web session failed.:: Host=$($Connection.HostName)"
        Write-S2Error`
        -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }
    
   
}

#endregion Session Functions

#region Uri Functions

function Join-S2Uri {

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject]$Connection,

        [Parameter(Mandatory)]
        [string]$Path,
        
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $Message = ("Join S2 Uri for {0} with {1}." -f $Connection, $Path )
    Write-S2Verbose `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name

    return '{0}/{1}' -f (
        $Connection.BaseUri.TrimEnd('/')
    ),
    (
        $Path.TrimStart('/')
    )
}

#endregion Uri Functions



#region Utility Functions

function ConvertTo-S2JsonFormBody {

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,

        [int]$Depth = 10,
        
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )
    $Message = ("Convert to Json")
    Write-S2Verbose `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
    $json =
    ConvertTo-Json `
        -InputObject $InputObject `
        -Compress `
        -Depth $Depth

    'json={0}' -f (
        [System.Uri]::EscapeDataString($json)
    )
}

#endregion Utility Functions

#region Public Exports

Export-ModuleMember -Function @(
    'New-S2ApiConnection',
    'New-S2WebSession',
    'Join-S2Uri',
    'ConvertTo-S2JsonFormBody'
)

#endregion Public Exports
