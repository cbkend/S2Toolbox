<#
.SYNOPSIS
    Provides NBAPI-only Access Level Group resource operations.
.DESCRIPTION
    Implements Get, Resolve, Add, Set (NBAPI Modify), and Remove (NBAPI Delete)
    operations without using the Web API or published REST API.
.NOTES
    FileName   : S2.AccessLevelGroup.psm1
    Application: S2 Toolbox
    Requires   : Windows PowerShell 5.1
    Version    : 1.0.0
#>
#requires -Version 5.1
Set-StrictMode -Version Latest

function Get-S2AccessLevelGroup {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [string]$LogFile
    )
    return Get-S2NBApiResourceCollection -Connection $Connection -CommandName 'GetAccessLevelGroups' -ItemXPath '/NETBOX/RESPONSE/DETAILS/ACCESSLEVELGROUPS/ACCESSLEVELGROUP' -PagingMode 'Key' -LogFile $LogFile
}

function Resolve-S2AccessLevelGroupKey {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$Name,
        [Parameter(Mandatory)] [string]$LogFile
    )
    $items = @(Get-S2AccessLevelGroup -Connection $Connection -LogFile $LogFile)
    return Resolve-S2NBApiResourceKey -InputObject $items -Name $Name `
        -NameProperty @('NAME') -KeyProperty @('ACCESSLEVELGROUPKEY', 'KEY') -ResourceName 'Access Level Group'
}

function Add-S2AccessLevelGroup {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Values,
        [string[]]$RequiredElement = @(),
        [Parameter(Mandatory)] [string]$LogFile
    )
    Add-S2NBApiResource -Connection $Connection -CommandName 'AddAccessLevelGroup' `
        -Values $Values -RequiredElement $RequiredElement -LogFile $LogFile
}

function Set-S2AccessLevelGroup {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [ValidateRange(1, [int]::MaxValue)] [int]$Key,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Values,
        [Parameter(Mandatory)] [string]$LogFile
    )
    Set-S2NBApiResource -Connection $Connection -CommandName 'ModifyAccessLevelGroup' `
        -KeyElement 'ACCESSLEVELGROUPKEY' -Key $Key -Values $Values -LogFile $LogFile
}

function Remove-S2AccessLevelGroup {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [ValidateRange(1, [int]::MaxValue)] [int]$Key,
        [Parameter(Mandatory)] [string]$LogFile
    )
    Remove-S2NBApiResource -Connection $Connection -CommandName 'DeleteAccessLevelGroup' `
        -KeyElement 'ACCESSLEVELGROUPKEY' -Key $Key -LogFile $LogFile
}

Export-ModuleMember -Function @(
    'Get-S2AccessLevelGroup',
    'Resolve-S2AccessLevelGroupKey',
    'Add-S2AccessLevelGroup',
    'Set-S2AccessLevelGroup',
    'Remove-S2AccessLevelGroup'
)
