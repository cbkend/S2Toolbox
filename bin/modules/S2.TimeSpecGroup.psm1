<#
.SYNOPSIS
    Provides NBAPI-only Time Spec Group resource operations.
.DESCRIPTION
    Implements Get, Resolve, Add, Set (NBAPI Modify), and Remove (NBAPI Delete)
    operations without using the Web API or published REST API.
.NOTES
    FileName   : S2.TimeSpecGroup.psm1
    Application: S2 Toolbox
    Requires   : Windows PowerShell 5.1
    Version    : 1.0.0
#>
#requires -Version 5.1
Set-StrictMode -Version Latest

function Get-S2TimeSpecGroup {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [string]$LogFile
    )
    return Get-S2NBApiResourceCollection -Connection $Connection -CommandName 'GetTimeSpecGroups' -ItemXPath '/NETBOX/RESPONSE/DETAILS/TIMESPECGROUPS/TIMESPECGROUP' -PagingMode 'Key' -LogFile $LogFile
}

function Resolve-S2TimeSpecGroupKey {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$Name,
        [Parameter(Mandatory)] [string]$LogFile
    )
    $items = @(Get-S2TimeSpecGroup -Connection $Connection -LogFile $LogFile)
    return Resolve-S2NBApiResourceKey -InputObject $items -Name $Name `
        -NameProperty @('NAME') -KeyProperty @('TIMESPECGROUPKEY') -ResourceName 'Time Spec Group'
}

function Add-S2TimeSpecGroup {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Values,
        [string[]]$RequiredElement = @(),
        [Parameter(Mandatory)] [string]$LogFile
    )
    Add-S2NBApiResource -Connection $Connection -CommandName 'AddTimeSpecGroup' `
        -Values $Values -RequiredElement $RequiredElement -LogFile $LogFile
}

function Set-S2TimeSpecGroup {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [ValidateRange(1, [int]::MaxValue)] [int]$Key,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Values,
        [Parameter(Mandatory)] [string]$LogFile
    )
    Set-S2NBApiResource -Connection $Connection -CommandName 'ModifyTimeSpecGroup' `
        -KeyElement 'TIMESPECGROUPKEY' -Key $Key -Values $Values -LogFile $LogFile
}

function Remove-S2TimeSpecGroup {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [ValidateRange(1, [int]::MaxValue)] [int]$Key,
        [Parameter(Mandatory)] [string]$LogFile
    )
    Remove-S2NBApiResource -Connection $Connection -CommandName 'DeleteTimeSpecGroup' `
        -KeyElement 'TIMESPECGROUPKEY' -Key $Key -LogFile $LogFile
}

Export-ModuleMember -Function @(
    'Get-S2TimeSpecGroup',
    'Resolve-S2TimeSpecGroupKey',
    'Add-S2TimeSpecGroup',
    'Set-S2TimeSpecGroup',
    'Remove-S2TimeSpecGroup'
)
