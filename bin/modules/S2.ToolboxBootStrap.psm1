<#
.SYNOPSIS
    Initializes and validates the required S2 Toolbox core modules.

.DESCRIPTION
    This script imports and verifies all mandatory S2 Toolbox shared modules
    required for authentication, security, logging, CSV processing, and API
    communications.

    The module loader enforces centralized module reuse in accordance with
    S2 Toolbox Coding Standards and prevents execution when required modules
    are missing or fail validation.


    Each module is imported from the toolbox module directory defined by
    $script:ModulePath and is validated after loading.

.NOTES
    FileName: S2.ToolboxBootStrap.psm1
    Application : S2 Toolbox
    Component   : Module Initialization
    Author      : Brian Kendrick
    PowerShell  : Windows PowerShell 5.1
    Version     : 1.0.0

.REQUIREMENTS
    - $script:ModulePath must be initialized prior to execution.
    - Required modules must exist within the configured module path.
    - Imported modules must successfully pass verification.

.EXAMPLE
    $script:ModulePath = Join-Path $PSScriptRoot 'bin\modules'
    .\Initialize-S2Modules.ps1

.CHANGELOG
    1.0.0
        - Initial release.
        - Added centralized module import and verification logic.

#>

#requires -Version 5.1
Set-StrictMode -Version Latest

function Import-S2ToolboxModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    if (-not $script:ModulePath) {
        if (Get-Command Write-S2Error  -ErrorAction SilentlyContinue) {
            $Message = 'ModulePath has not been initialized.'
            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name
            throw [System.InvalidOperationException]::new($Message)
        }
        else {
            throw 'ModulePath has not been initialized.'
        }
    }

    $moduleFile = Join-Path $script:ModulePath $Name

    if (-not (Test-Path -LiteralPath $moduleFile -PathType Leaf)) {
        if (Get-Command Write-S2Error  -ErrorAction SilentlyContinue) {
            $Message = "Required toolbox module not found: $moduleFile"
            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name
            throw [System.InvalidOperationException]::new($Message)
        }
        else {
            throw "Required toolbox module not found: $moduleFile"
        }
    }

    Import-Module $moduleFile -Force -ErrorAction Stop

    $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($Name)

    if (-not (Get-Module -Name $moduleName)) {
        if (Get-Command Write-S2Error  -ErrorAction SilentlyContinue) {
            $Message = "Module verification failed: $moduleName"
            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name
            throw [System.InvalidOperationException]::new($Message)
        }
        else {
            throw "Module verification failed: $moduleName"
        }
    }
}

function Import-S2Catalogs {
    [CmdletBinding()]
    param(

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    Initialize-S2NBAPICatalog -LogFile $LogFile

    Initialize-S2RestApiCatalog -LogFile $LogFile

    Initialize-S2ApiWebCatalog -LogFile $LogFile
}

$modules = @(
    # Logging module must remain first so import activity can be logged.
    'S2.Logging.psm1'
    'S2.Validation.psm1'
    'S2.Security.psm1'
    'S2.Csv.psm1'
    'S2.Api.Common.psm1'
    'S2.NBAPI.psm1'
    'S2.RestApi.psm1'
    'S2.WebApi.psm1'
    'S2.Authentication.psm1'
    'S2.NBAPI.Resource.psm1'
    'S2.AccessLevel.psm1'
    'S2.AccessLevelGroup.psm1'
    'S2.Holiday.psm1'
    'S2.PortalGroup.psm1'
    'S2.ReaderGroup.psm1'
    'S2.TimeSpec.psm1'
    'S2.TimeSpecGroup.psm1'
    'S2.NetworkNode.psm1'
    'S2.Resource.Validation.psm1'
    'S2.Import.Common.psm1'
)

foreach ($module in $modules) {
    try {
        Import-S2ToolboxModule -Name $module -LogFile $LogFile

        if (Get-Command Write-S2Information -ErrorAction SilentlyContinue) {
            $Message = "Imported module: $module"
            Write-S2Information `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name
        }
    }
    catch {
        if (Get-Command Write-S2Error  -ErrorAction SilentlyContinue) {
            $Message = "Failed to import module '$module'. $_"
            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name
            throw [System.InvalidOperationException]::new($Message)
        }
        else {
            throw "Failed to import module '$module'. $_"
        }
    }
    $loadedModule = Get-Module -Name (
        [System.IO.Path]::GetFileNameWithoutExtension($module)
    )

    if (-not $loadedModule) {
        if (Get-Command Write-S2Error  -ErrorAction SilentlyContinue) {
            $Message = "Module failed verification: $module"
            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name
            throw [System.InvalidOperationException]::new($Message)
        }
        else {
            throw "Module failed verification: $module"
        }
    }
}
Import-S2Catalogs -LogFile $LogFile