<#
.SYNOPSIS
    Provides NBAPI-only Access Level resource operations.
.DESCRIPTION
    Implements Get, Resolve, Add, Set (NBAPI Modify), and Remove (NBAPI Delete)
    operations without using the Web API or published REST API.
.NOTES
    FileName   : S2.AccessLevel.psm1
    Application: S2 Toolbox
    Requires   : Windows PowerShell 5.1
    Version    : 1.0.0
#>
#requires -Version 5.1
Set-StrictMode -Version Latest

function Assert-S2AccessLevelDependency {
    [CmdletBinding()]
    param()

    $requiredCommands = @(
        'Get-S2NBApiResourceCollection',
        'Resolve-S2NBApiResourceKey',
        'Add-S2NBApiResource',
        'Set-S2NBApiResource',
        'Remove-S2NBApiResource'
    )

    $missingCommands = @(
        $requiredCommands |
        Where-Object {
            $null -eq (
                Get-Command `
                    -Name $_ `
                    -ErrorAction SilentlyContinue
            )
        }
    )

    if ($missingCommands.Count -gt 0) {
        throw [System.InvalidOperationException]::new(
            "S2.AccessLevel.psm1 requires: $(
                $missingCommands -join ', '
            )"
        )
    }
}

Assert-S2AccessLevelDependency

function Get-S2AccessLevel {
    <#
    .SYNOPSIS
        Returns all S2 Access Levels through NBAPI.

    .DESCRIPTION
        Retrieves every Access Level key through the paged GetAccessLevels
        command and retrieves the final details through GetAccessLevel.

        Collection paging and detail retrieval are delegated to the shared
        NBAPI resource module.
    #>

    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject]$Connection,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    return Get-S2NBApiResourceCollection `
        -Connection $Connection `
        -CommandName 'GetAccessLevels' `
        -ItemXPath (
        '/NETBOX/RESPONSE/DETAILS/' +
        'ACCESSLEVELS/ACCESSLEVEL'
    ) `
        -PagingMode 'Key' `
        -NextValueXPath '/NETBOX/RESPONSE/DETAILS/NEXTKEY' `
        -Values ([ordered]@{
            WANTKEY = 'TRUE'
        }) `
        -DetailCommandName 'GetAccessLevel' `
        -DetailKeyElement 'ACCESSLEVELKEY' `
        -DetailXPath '/NETBOX/RESPONSE/DETAILS' `
        -KeyPropertyName 'ACCESSLEVELKEY' `
        -LogFile $LogFile
}

function Resolve-S2AccessLevelKey {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$Name,
        [Parameter(Mandatory)] [string]$LogFile
    )
    $items = @(Get-S2AccessLevel -Connection $Connection -LogFile $LogFile)
    return Resolve-S2NBApiResourceKey -InputObject $items -Name $Name `
        -NameProperty @('ACCESSLEVELNAME', 'NAME') -KeyProperty @('ACCESSLEVELKEY') -ResourceName 'Access Level'
}

function Add-S2AccessLevel {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Values,
        [string[]]$RequiredElement = @(),
        [Parameter(Mandatory)] [string]$LogFile
    )
    Add-S2NBApiResource -Connection $Connection -CommandName 'AddAccessLevel' `
        -Values $Values -RequiredElement $RequiredElement -LogFile $LogFile
}

function Set-S2AccessLevel {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [ValidateRange(1, [int]::MaxValue)] [int]$Key,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Values,
        [Parameter(Mandatory)] [string]$LogFile
    )
    Set-S2NBApiResource -Connection $Connection -CommandName 'ModifyAccessLevel' `
        -KeyElement 'ACCESSLEVELKEY' -Key $Key -Values $Values -LogFile $LogFile
}

function Remove-S2AccessLevel {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [ValidateRange(1, [int]::MaxValue)] [int]$Key,
        [Parameter(Mandatory)] [string]$LogFile
    )
    Remove-S2NBApiResource -Connection $Connection -CommandName 'DeleteAccessLevel' `
        -KeyElement 'ACCESSLEVELKEY' -Key $Key -LogFile $LogFile
}

Export-ModuleMember -Function @(
    'Get-S2AccessLevel',
    'Resolve-S2AccessLevelKey',
    'Add-S2AccessLevel',
    'Set-S2AccessLevel',
    'Remove-S2AccessLevel'
)
