<#
.SYNOPSIS
    Provides NBAPI-only Reader Group resource operations.
.DESCRIPTION
    Implements Get, Resolve, Add, Set (NBAPI Modify), and Remove (NBAPI Delete)
    operations without using the Web API or published REST API.
.NOTES
    FileName   : S2.ReaderGroup.psm1
    Application: S2 Toolbox
    Requires   : Windows PowerShell 5.1
    Version    : 1.0.0
#>
#requires -Version 5.1
Set-StrictMode -Version Latest

function Get-S2ReaderGroup {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [string]$LogFile
    )
    return Get-S2NBApiResourceCollection -Connection $Connection -CommandName 'GetReaderGroups' -ItemXPath '/NETBOX/RESPONSE/DETAILS/READERGROUPS/READERGROUP' -PagingMode 'Key' -LogFile $LogFile
}

function Resolve-S2ReaderGroupKey {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$Name,
        [Parameter(Mandatory)] [string]$LogFile
    )
    $items = @(Get-S2ReaderGroup -Connection $Connection -LogFile $LogFile)
    return Resolve-S2NBApiResourceKey -InputObject $items -Name $Name `
        -NameProperty @('NAME') -KeyProperty @('READERGROUPKEY') -ResourceName 'Reader Group'
}

function Add-S2ReaderGroup {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Values,
        [string[]]$RequiredElement = @(),
        [Parameter(Mandatory)] [string]$LogFile
    )
    Add-S2NBApiResource -Connection $Connection -CommandName 'AddReaderGroup' `
        -Values $Values -RequiredElement $RequiredElement -LogFile $LogFile
}

function Set-S2ReaderGroup {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [ValidateRange(1, [int]::MaxValue)] [int]$Key,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Values,
        [Parameter(Mandatory)] [string]$LogFile
    )
    Set-S2NBApiResource -Connection $Connection -CommandName 'ModifyReaderGroup' `
        -KeyElement 'READERGROUPKEY' -Key $Key -Values $Values -LogFile $LogFile
}

function Remove-S2ReaderGroup {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [ValidateRange(1, [int]::MaxValue)] [int]$Key,
        [Parameter(Mandatory)] [string]$LogFile
    )
    Remove-S2NBApiResource -Connection $Connection -CommandName 'DeleteReaderGroup' `
        -KeyElement 'READERGROUPKEY' -Key $Key -LogFile $LogFile
}

Export-ModuleMember -Function @(
    'Get-S2ReaderGroup',
    'Resolve-S2ReaderGroupKey',
    'Add-S2ReaderGroup',
    'Set-S2ReaderGroup',
    'Remove-S2ReaderGroup'
)
