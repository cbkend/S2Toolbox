<#
.SYNOPSIS
    Provides NBAPI-only Holiday resource operations.
.DESCRIPTION
    Implements Get, Resolve, Add, Set (NBAPI Modify), and Remove (NBAPI Delete)
    operations without using the Web API or published REST API.
.NOTES
    FileName   : S2.Holiday.psm1
    Application: S2 Toolbox
    Requires   : Windows PowerShell 5.1
    Version    : 1.0.0
#>
#requires -Version 5.1
Set-StrictMode -Version Latest

function Get-S2Holiday {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [string]$LogFile
    )
    [xml]$keysResponse = Invoke-S2NBApiResourceCommand `
        -Connection $Connection -CommandName 'GetHolidays' -LogFile $LogFile
    $keyText = [string]$keysResponse.NETBOX.RESPONSE.DETAILS.HOLIDAYS
    $keys = @($keyText -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($keyValue in $keys) {
        [xml]$detailResponse = Invoke-S2NBApiResourceCommand `
            -Connection $Connection -CommandName 'GetHoliday' `
            -Values ([ordered]@{ HOLIDAYKEY = [int]$keyValue }) `
            -RequiredElement @('HOLIDAYKEY') -LogFile $LogFile
        $node = $detailResponse.SelectSingleNode('/NETBOX/RESPONSE/DETAILS/HOLIDAY')
        if ($null -ne $node) {
            $item = ConvertFrom-S2NBApiXmlNode -Node $node
            $item | Add-Member -NotePropertyName HOLIDAYKEY -NotePropertyValue ([int]$keyValue) -Force
            [void]$items.Add($item)
        }
    }
    return , $items.ToArray()
}

function Resolve-S2HolidayKey {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$Name,
        [Parameter(Mandatory)] [string]$LogFile
    )
    $items = @(Get-S2Holiday -Connection $Connection -LogFile $LogFile)
    return Resolve-S2NBApiResourceKey -InputObject $items -Name $Name `
        -NameProperty @('NAME', 'HOLIDAYNAME') -KeyProperty @('HOLIDAYKEY') -ResourceName 'Holiday'
}

function Add-S2Holiday {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Values,
        [string[]]$RequiredElement = @(),
        [Parameter(Mandatory)] [string]$LogFile
    )
    Add-S2NBApiResource -Connection $Connection -CommandName 'AddHoliday' `
        -Values $Values -RequiredElement $RequiredElement -LogFile $LogFile
}

function Set-S2Holiday {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [ValidateRange(1, [int]::MaxValue)] [int]$Key,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Values,
        [Parameter(Mandatory)] [string]$LogFile
    )
    Set-S2NBApiResource -Connection $Connection -CommandName 'ModifyHoliday' `
        -KeyElement 'HOLIDAYKEY' -Key $Key -Values $Values -LogFile $LogFile
}

function Remove-S2Holiday {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [ValidateRange(1, [int]::MaxValue)] [int]$Key,
        [Parameter(Mandatory)] [string]$LogFile
    )
    Remove-S2NBApiResource -Connection $Connection -CommandName 'DeleteHoliday' `
        -KeyElement 'HOLIDAYKEY' -Key $Key -LogFile $LogFile
}

Export-ModuleMember -Function @(
    'Get-S2Holiday',
    'Resolve-S2HolidayKey',
    'Add-S2Holiday',
    'Set-S2Holiday',
    'Remove-S2Holiday'
)
