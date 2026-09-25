<#
.SYNOPSIS
    Provides centralized security utilities for S2 Toolbox.
.DESCRIPTION
    Provides Windows PowerShell 5.1-compatible helpers for credential storage,
    secure-string protection, path and certificate validation, sensitive-data
    cleanup, secret-exposure detection, and TLS protocol configuration.

    This synchronized version contains the complete public function set from the
    standalone and current-build versions of S2.Security.psm1.
.NOTES
    FileName   : S2.Security.psm1
    Author     : Brian Kendrick
    Application: S2 Toolbox
    Requires   : Windows PowerShell 5.1
    Version    : 1.0.0
    
.CHANGELOG
    1.0.0
        - Synchronized standalone and current-build function sets.
        - Added Test-S2SecretExposure, Test-S2TlsProtocol, and Set-S2TlsProtocol.
        - Added path validation before credential file access.
        - Added literal-path usage and consistent terminating error handling.
        - Preserved existing public function names for compatibility.
#>

#requires -Version 5.1
Set-StrictMode -Version Latest

#region Path validation

function Resolve-S2SecurityPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    if (-not (Test-S2PathSafety -Path $Path -LogFile $LogFile)) {
        $Message = "Path is invalid: $Path"
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }

    $Message = "Get Security Path '$Path'."
    Write-S2Verbose `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
    return [System.IO.Path]::GetFullPath($Path)
}
#endregion Path validation

#region Credential protection
function Protect-S2Credential {
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    if (-not (Test-S2Credential -Credential $Credential -LogFile $LogFile)) {
        $Message = 'Credential must contain a username and password.'
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }

    $resolvedPath = Resolve-S2SecurityPath -Path $Path -LogFile $LogFile
    $parentPath = Split-Path -Path $resolvedPath -Parent

    if ([string]::IsNullOrWhiteSpace($parentPath)) {
        $Message = "Credential path must include a valid parent directory: $Path"
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }

    if (-not (Test-Path -LiteralPath $parentPath -PathType Container)) {
        $null = New-Item `
            -Path $parentPath `
            -ItemType Directory `
            -Force `
            -ErrorAction Stop
    }
    $Message = "Set Protected Credential Data."
    Write-S2Information `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
    try {
        $Credential | Export-Clixml -LiteralPath $resolvedPath -Force -ErrorAction Stop
        return Get-Item -LiteralPath $resolvedPath -ErrorAction Stop
    }
    catch {
        $Message = "Unable to protect credential at '$resolvedPath'. $($_.Exception.Message)"
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }
}

function Unprotect-S2Credential {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCredential])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $resolvedPath = Resolve-S2SecurityPath -Path $Path -LogFile $LogFile
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        $Message = "Protected credential file was not found: $resolvedPath"
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }

    try {
        $credential = Import-Clixml -LiteralPath $resolvedPath -ErrorAction Stop
    }
    catch {
        $Message = "Unable to unprotect credential from '$resolvedPath'. $($_.Exception.Message)"
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }

    if ($credential -isnot [System.Management.Automation.PSCredential]) {
        $Message = "Protected credential file did not contain a PSCredential: $resolvedPath"
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }

    $Message = "Get Protected Credential Data."
    Write-S2Verbose `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
    return $credential
}

function Test-S2Credential {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )
    $Message = "Test for Credential Data."
    Write-S2Verbose `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name

    if ($null -eq $Credential) {
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($Credential.UserName)) {
        return $false
    }

    if ($null -eq $Credential.Password -or $Credential.Password.Length -le 0) {
        return $false
    }

    return $true
}

function New-S2SecureCredential {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCredential])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$UserName,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Security.SecureString]$Password,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    if ($Password.Length -le 0) {
        $Message = 'Password cannot be empty.'
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }
    $Message = "Build Protected Credential."
    Write-S2Information `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name

    return New-Object System.Management.Automation.PSCredential(
        $UserName.Trim(),
        $Password
    )
}
#endregion Credential protection

#region String protection
function Protect-S2String {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )
    $Message = "Set Protected Data."
    Write-S2Debug `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
    $secureString = ConvertTo-SecureString -String $Value -AsPlainText -Force
    try {
        return ConvertFrom-SecureString -SecureString $secureString
    }
    finally {
        $secureString = $null
    }
}

function Unprotect-S2String {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$EncryptedValue,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )
    $Message = "Get Protected Data."
    Write-S2Debug `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
    $secureString = ConvertTo-SecureString -String $EncryptedValue -ErrorAction Stop
    $buffer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)

    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($buffer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($buffer)
        $secureString = $null
    }
}
#endregion String protection

#region TLS configuration
function Get-S2SecurityProtocolValue {
    [CmdletBinding()]
    [OutputType([System.Net.SecurityProtocolType])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [ValidateNotNull()]
        [string]$LogFile
    )

    $protocolNames = [Enum]::GetNames([System.Net.SecurityProtocolType])
    if ($protocolNames -notcontains $Name) {
        $Message = "Security protocol '$Name' is not available in this Windows PowerShell/.NET environment."
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }
    $Message = "Getting Security protocol to '$Name'."
    Write-S2Verbose `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
    return [System.Net.SecurityProtocolType][Enum]::Parse(
        [System.Net.SecurityProtocolType],
        $Name
    )
}

function Test-S2TlsProtocol {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [ValidateSet('Tls12', 'Tls13')]
        [string]$Protocol = 'Tls12',

        [ValidateNotNull()]
        [string]$LogFile
    )

    $availableProtocols = [Enum]::GetNames([System.Net.SecurityProtocolType])
    if ($availableProtocols -notcontains $Protocol) {
        return $false
    }
    $Message = "Setting connection Protocol to '$Protocol'."
    Write-S2Verbose `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
    $protocolValue = Get-S2SecurityProtocolValue -Name $Protocol -LogFile $LogFile
    $configuredProtocols = [System.Net.ServicePointManager]::SecurityProtocol
    return (($configuredProtocols -band $protocolValue) -eq $protocolValue)
}

function Set-S2TlsProtocol {
    [CmdletBinding()]
    [OutputType([System.Net.SecurityProtocolType])]
    param(
        [switch]$EnableTls12,
        [switch]$EnableTls13,

        [ValidateNotNull()]
        [string]$LogFile
    )

    if (-not $EnableTls12.IsPresent -and -not $EnableTls13.IsPresent) {
        $Message = 'Specify EnableTls12, EnableTls13, or both.'
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }

    $protocols = [System.Net.ServicePointManager]::SecurityProtocol

    if ($EnableTls12.IsPresent) {
        $protocols = $protocols -bor (Get-S2SecurityProtocolValue -Name 'Tls12' -LogFile $LogFile)
    }

    if ($EnableTls13.IsPresent) {
        $protocols = $protocols -bor (Get-S2SecurityProtocolValue -Name 'Tls13' -LogFile $LogFile)
    }

    $Message = "Setting Security protocol to '$protocols'."
    Write-S2Debug `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
        
    [System.Net.ServicePointManager]::SecurityProtocol = $protocols
    return [System.Net.ServicePointManager]::SecurityProtocol
}
#endregion TLS configuration

#region Sensitive-data cleanup
function Clear-S2SensitiveData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [ref]$Value,

        [ValidateNotNull()]
        [string]$LogFile
    )
    $Message = "Clearing Sensitive Data."
    Write-S2Debug `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
    $Value.Value = $null
}
#endregion Sensitive-data cleanup

#region Public Exports
Export-ModuleMember -Function @(
    'Protect-S2Credential',
    'Unprotect-S2Credential',
    'Test-S2Credential',
    'New-S2SecureCredential',
    'Protect-S2String',
    'Unprotect-S2String',
    'Test-S2PathSafety',
    'Clear-S2SensitiveData',
    'Test-S2TlsProtocol',
    'Set-S2TlsProtocol'
)

#endregion Public Exports