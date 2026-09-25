<#
.SYNOPSIS
    Provides NBAPI-only Time Spec resource operations.
.DESCRIPTION
    Implements Get, Resolve, Add, Set (NBAPI Modify), and Remove (NBAPI Delete)
    operations without using the Web API or published REST API.
.NOTES
    FileName   : S2.TimeSpec.psm1
    Application: S2 Toolbox
    Requires   : Windows PowerShell 5.1
    Version    : 1.0.0
#>
#requires -Version 5.1
Set-StrictMode -Version Latest

function Get-S2TimeSpec {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [string]$LogFile
    )
    return Get-S2NBApiResourceCollection -Connection $Connection -CommandName 'GetTimeSpecs' -ItemXPath '/NETBOX/RESPONSE/DETAILS/TIMESPECS/TIMESPEC' -PagingMode 'Key' -LogFile $LogFile
}

function Resolve-S2TimeSpecKey {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$Name,
        [Parameter(Mandatory)] [string]$LogFile
    )
    $items = @(Get-S2TimeSpec -Connection $Connection -LogFile $LogFile)
    return Resolve-S2NBApiResourceKey -InputObject $items -Name $Name `
        -NameProperty @('NAME') -KeyProperty @('TIMESPECKEY') -ResourceName 'Time Spec'
}

function Add-S2TimeSpec {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Values,
        [string[]]$RequiredElement = @(),
        [Parameter(Mandatory)] [string]$LogFile
    )
    Add-S2NBApiResource -Connection $Connection -CommandName 'AddTimeSpec' `
        -Values $Values -RequiredElement $RequiredElement -LogFile $LogFile
}

function Set-S2TimeSpec {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [ValidateRange(1, [int]::MaxValue)] [int]$Key,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Values,
        [Parameter(Mandatory)] [string]$LogFile
    )
    Set-S2NBApiResource -Connection $Connection -CommandName 'ModifyTimeSpec' `
        -KeyElement 'TIMESPECKEY' -Key $Key -Values $Values -LogFile $LogFile
}

function Remove-S2TimeSpec {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [ValidateRange(1, [int]::MaxValue)] [int]$Key,
        [Parameter(Mandatory)] [string]$LogFile
    )
    Remove-S2NBApiResource -Connection $Connection -CommandName 'DeleteTimeSpec' `
        -KeyElement 'TIMESPECKEY' -Key $Key -LogFile $LogFile
}

Export-ModuleMember -Function @(
    'Get-S2TimeSpec',
    'Resolve-S2TimeSpecKey',
    'Add-S2TimeSpec',
    'Set-S2TimeSpec',
    'Remove-S2TimeSpec'
)
