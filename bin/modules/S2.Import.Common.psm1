<#
.SYNOPSIS
    Provides shared orchestration helpers for S2 Access Level CSV scripts.
.DESCRIPTION
    Centralizes import-path resolution, required-command validation, action-result
    creation, console output, and verification-batch failure handling. API,
    authentication, CSV, security, logging, resource, and final-state verification
    behavior remains delegated to the existing S2 Toolbox modules.
.NOTES
    FileName   : S2.Import.Common.psm1
    Application: S2 Toolbox
    Requires   : Windows PowerShell 5.1
#>
#requires -Version 5.1
Set-StrictMode -Version Latest

function Resolve-S2ImportPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptRoot
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    $toolboxRoot = [System.IO.Path]::GetFullPath(
        (Join-Path -Path $ScriptRoot -ChildPath '..')
    )
    $defaultImportPath = Join-Path -Path $toolboxRoot -ChildPath (
        Join-Path -Path 'import' -ChildPath $Path
    )

    if (Test-Path -LiteralPath $defaultImportPath -PathType Leaf) {
        return [System.IO.Path]::GetFullPath($defaultImportPath)
    }

    return [System.IO.Path]::GetFullPath(
        (Join-Path -Path (Get-Location) -ChildPath $Path)
    )
}

function Assert-S2RequiredCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name
    )

    $missingCommands = @(
        $Name | Where-Object {
            $null -eq (Get-Command -Name $_ -ErrorAction SilentlyContinue)
        }
    )

    if ($missingCommands.Count -gt 0) {
        throw [System.InvalidOperationException]::new(
            'The bootstrap did not load required commands: {0}' -f
            ($missingCommands -join ', ')
        )
    }
}

function New-S2ActionResult {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [int]$RowNumber,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('Created', 'Modified', 'Deleted', 'Previewed', 'Skipped', 'Failed')]
        [string]$Status,

        [AllowEmptyString()]
        [string]$AccessLevelKey = '',

        [AllowEmptyString()]
        [string]$Message = ''
    )

    return [pscustomobject]@{
        RowNumber           = $RowNumber
        Name                = $Name
        AccessLevelKey      = $AccessLevelKey
        Status              = $Status
        Message             = $Message
        Verified            = $false
        VerificationMessage = ''
    }
}

function Write-S2ConsoleMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet('Information', 'Warning', 'Error')]
        [string]$Level = 'Information',

        [switch]$Silent
    )

    if ($Silent.IsPresent) {
        return
    }

    switch ($Level) {
        'Warning' { Write-Warning $Message }
        'Error' { Write-Host $Message -ForegroundColor Red }
        default { Write-Host $Message }
    }
}


Export-ModuleMember -Function @(
    'Resolve-S2ImportPath',
    'Assert-S2RequiredCommand',
    'New-S2ActionResult',
    'Write-S2ConsoleMessage'
)
