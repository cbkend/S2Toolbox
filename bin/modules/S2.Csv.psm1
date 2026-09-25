<#
.SYNOPSIS
    CSV import, export, and validation utilities for S2 Toolbox.

.DESCRIPTION
    Provides reusable CSV processing functions used throughout the S2 Toolbox.
    This module centralizes CSV import, export, validation, and transformation
    logic to support DRY principles and maintainable code.

.NOTES
    File Name  : S2.Csv.psm1
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

#region 

function Import-S2CsvData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    if (-not (Test-Path -Path $Path)) {
        $Message = "CSV file not found: $Path"
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }

    try {
        Import-Csv -Path $Path
        $Message = "Import CSV file '$Path'. $_"
        Write-S2Information `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
    }
    catch {
        $Message = "Failed to import CSV file '$Path'. $_"
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }
}

function Export-S2CsvData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$InputObject,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    try {
        $InputObject |
        Export-Csv `
            -Path $Path `
            -NoTypeInformation `
            -Force
        $Message = "Exporting CSV data '$Path'. $_"
        Write-S2Information `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
    }
    catch {
        $Message = "Failed to export CSV file '$Path'. $_"
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }
}

function Get-S2CsvColumns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Data,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    if (-not $Data -or $Data.Count -eq 0) {
        return @()
    }
    $Message = ("'{0}' is in the csv.'." -f $Data[0].PSObject.Properties.Name)
    Write-S2Debug `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
    return $Data[0].PSObject.Properties.Name
}

function ConvertTo-S2Hashtable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Data,

        [Parameter(Mandatory)]
        [string]$KeyColumn,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $table = @{}

    foreach ($row in $Data) {

        $key = $row.$KeyColumn

        if ([string]::IsNullOrWhiteSpace($key)) {
            continue
        }
        $Message = ("Building hashtable {0}, {1}" -f $key, $row)
        Write-S2Debug `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name

        $table[$key] = $row
    }

    return $table
}


#endregion 

#region Public Exports
Export-ModuleMember -Function @(
    'Import-S2CsvData',
    'Export-S2CsvData',
    'Get-S2CsvColumns',
    'ConvertTo-S2Hashtable'
)

#endregion Public Exports