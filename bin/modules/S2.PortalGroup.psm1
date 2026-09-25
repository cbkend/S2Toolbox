<#
.SYNOPSIS
    Provides NBAPI-only Portal Group resource operations.
.DESCRIPTION
    Implements Get, Resolve, Add, Set (NBAPI Modify), and Remove (NBAPI Delete)
    operations without using the Web API or published REST API.
.NOTES
    FileName   : S2.PortalGroup.psm1
    Application: S2 Toolbox
    Requires   : Windows PowerShell 5.1
    Version    : 1.0.0
#>
#requires -Version 5.1
Set-StrictMode -Version Latest

function Get-S2PortalGroup {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [string]$LogFile
    )
    return Get-S2NBApiResourceCollection -Connection $Connection -CommandName 'GetPortalGroups' -ItemXPath '/NETBOX/RESPONSE/DETAILS/PORTALGROUPS/PORTALGROUP' -PagingMode 'Key' -LogFile $LogFile
}

function Resolve-S2PortalGroupKey {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$Name,
        [Parameter(Mandatory)] [string]$LogFile
    )
    $items = @(Get-S2PortalGroup -Connection $Connection -LogFile $LogFile)
    return Resolve-S2NBApiResourceKey -InputObject $items -Name $Name `
        -NameProperty @('NAME') -KeyProperty @('PORTALGROUPKEY') -ResourceName 'Portal Group'
}

function Add-S2PortalGroup {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Values,
        [string[]]$RequiredElement = @(),
        [Parameter(Mandatory)] [string]$LogFile
    )
    Add-S2NBApiResource -Connection $Connection -CommandName 'AddPortalGroup' `
        -Values $Values -RequiredElement $RequiredElement -LogFile $LogFile
}

function Set-S2PortalGroup {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [ValidateRange(1, [int]::MaxValue)] [int]$Key,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Values,
        [Parameter(Mandatory)] [string]$LogFile
    )
    Set-S2NBApiResource -Connection $Connection -CommandName 'ModifyPortalGroup' `
        -KeyElement 'PORTALGROUPKEY' -Key $Key -Values $Values -LogFile $LogFile
}

function Remove-S2PortalGroup {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [ValidateRange(1, [int]::MaxValue)] [int]$Key,
        [Parameter(Mandatory)] [string]$LogFile
    )
    Remove-S2NBApiResource -Connection $Connection -CommandName 'DeletePortalGroup' `
        -KeyElement 'PORTALGROUPKEY' -Key $Key -LogFile $LogFile
}

Export-ModuleMember -Function @(
    'Get-S2PortalGroup',
    'Resolve-S2PortalGroupKey',
    'Add-S2PortalGroup',
    'Set-S2PortalGroup',
    'Remove-S2PortalGroup'
)
