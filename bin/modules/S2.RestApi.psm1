<#
.SYNOPSIS
    Provides the published LenelS2 NetBox REST API communication layer.

.DESCRIPTION
    Centralizes published NetBox REST endpoint lookup, authenticated GET requests,
    JSON response retrieval, and paginated row aggregation for the S2 Toolbox.

    Shared connection validation, URI construction, web-session creation, and
    logging are provided by S2.Api.Common.psm1.

    Endpoint metadata is stored in S2.RestApi.Endpoints.psd1. This module includes
    documented endpoints under /nbws/api/ and /nbws/ref/. Internal Web API and
    Mercury endpoints remain separate concerns.

.NOTES
    FileName   : S2.RestApi.psm1
    Author     : Brian Kendrick
    Application: S2 Toolbox
    Requires   : Windows PowerShell 5.1
    Version    : 1.0.0

.CHANGELOG
    1.0.0
        - Refactored published REST operations from S2.Api.psm1
        - Extracted endpoint metadata to S2.RestApi.Endpoints.psd1
        - Added endpoint catalog validation during module import
        - Added authenticated REST request handling
        - Added JSON collection retrieval
        - Added paginated row aggregation
#>

#requires -Version 5.1
Set-StrictMode -Version Latest

#region Catalog
function Initialize-S2RestApiCatalog {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $endpointCatalogPath = Join-Path `
        -Path $PSScriptRoot `
        -ChildPath '..\..\resources\S2.RestApi.Endpoints.psd1'
    
    if (-not (Test-Path -LiteralPath $endpointCatalogPath -PathType Leaf)) {
        $Message = ( "Required REST endpoint catalog not found: {0}" -f $endpointCatalogPath )
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }

    $script:S2RestEndpoints = Import-PowerShellDataFile `
        -Path $endpointCatalogPath

    if (
        $null -eq $script:S2RestEndpoints -or
        $script:S2RestEndpoints.Count -eq 0
    ) {
        $Message = ( "REST endpoint catalog loaded successfully but contains no endpoints: {0}" -f $endpointCatalogPath )
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }

    $requiredEndpointProperties = @(
        'Path'
        'Method'
        'Category'
        'Action'
        'ResponseType'
        'Description'
    )

    foreach ($endpointKey in $script:S2RestEndpoints.Keys) {
        $definition = $script:S2RestEndpoints[$endpointKey]

        if ($definition -isnot [System.Collections.IDictionary]) {
            $Message = ( "REST endpoint '{0}' must be defined as a dictionary." -f $endpointKey )
            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name
            throw [System.InvalidOperationException]::new($Message)
        }

        foreach ($property in $requiredEndpointProperties) {
            if (
                -not $definition.Contains($property) -or
                [string]::IsNullOrWhiteSpace([string]$definition[$property])
            ) {
                $Message = ( "REST endpoint '{0}' is missing required property '{1}'." -f $endpointKey, $property )
                Write-S2Error `
                    -Message $Message `
                    -LogFile $LogFile `
                    -FileName $PSCommandPath `
                    -Source $MyInvocation.MyCommand.Name
                throw [System.InvalidOperationException]::new($Message) 
            }
        }

        if ([string]$definition.Method -ne 'Get') {
            $Message = ( "REST endpoint '{0}' has unsupported method '{1}'." -f $endpointKey, $definition.Method )
            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name
            throw [System.InvalidOperationException]::new($Message) 
        }

        if ([string]$definition.ResponseType -notin @('Collection', 'Detail')) {
            $Message = ( "REST endpoint '{0}' has unsupported response type '{1}'." -f $endpointKey, $definition.ResponseType )
            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name
            throw [System.InvalidOperationException]::new($Message) 
        }

        if (-not ([string]$definition.Path).StartsWith('/')) {
            $Message = ( "REST endpoint '{0}' must define an application path beginning with '/'." -f $endpointKey )
            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name
            throw [System.InvalidOperationException]::new($Message)
        }

        if (
            -not ([string]$definition.Path).StartsWith('/nbws/api/') -and
            -not ([string]$definition.Path).StartsWith('/nbws/ref/')
        ) {
            $Message = ( "REST endpoint '{0}' must be under '/nbws/api/' or '/nbws/ref/'." -f $endpointKey )
            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name
            throw [System.InvalidOperationException]::new($Message) 
        }
    }
    return $script:S2RestEndpoints
}
#endregion Catalog

#region Endpoint Functions

function Get-S2RestEndpoint {
    <#
    .SYNOPSIS
        Resolves a published S2 REST endpoint by name.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [AllowNull()]
        [hashtable]$Value,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    Assert-S2RestEndpointValues -Name $Name -Value $Value -LogFile $LogFile

    $Message = ( "Get S2 REST endpoint '{0}'." -f $endpointKey )
    Write-S2Debug `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name

    return [pscustomobject]@{
        Name          = $endpointKey
        Path          = $path
        Method        = [string]$definition.Method
        Category      = [string]$definition.Category
        Action        = [string]$definition.Action
        ResponseType  = [string]$definition.ResponseType
        Description   = [string]$definition.Description
        RequiresValue = $false
    }
}

function Get-S2RestEndpointCatalog {
    <#
    .SYNOPSIS
        Returns the published S2 REST endpoint catalog.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    foreach ($key in $script:S2RestEndpoints.Keys) {
        $definition = $script:S2RestEndpoints[$key]
        $path = [string]$definition.Path

        $Message = ( "Get S2 REST endpoint '{0}'. definition from Catalog. {1} :: {2}" -f $key, $definition.Category, $definition.Action)
        Write-S2Debug `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        [pscustomobject]@{
            Name            = $key
            Path            = $path
            Method          = [string]$definition.Method
            Category        = [string]$definition.Category
            Action          = [string]$definition.Action
            ResponseType    = [string]$definition.ResponseType
            Description     = [string]$definition.Description
            RequiresValue   = [bool]($path -match '\{[^}]+\}')
            CollectionStyle = [bool]($definition.ResponseType -eq 'Collection')
        }
    }
}

#endregion Endpoint Functions

#region REST Request Functions

function Invoke-S2RestRequest {
    <#
    .SYNOPSIS
        Invokes an authenticated request against a published S2 REST endpoint.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject]$Connection,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'Endpoint')]
        [ValidateNotNullOrEmpty()]
        [string]$EndpointName,

        [Parameter(ParameterSetName = 'Endpoint')]
        [AllowNull()]
        [hashtable]$EndpointValue,

        [ValidateSet('Get')]
        [string]$Method = 'Get',

        [AllowNull()]
        [hashtable]$Query,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    Assert-S2WebConnection -Connection $Connection -LogFile $LogFile

    if ($PSCmdlet.ParameterSetName -eq 'Endpoint') {
        $endpoint = Get-S2RestEndpoint `
            -Name $EndpointName `
            -Value $EndpointValue `
            -LogFile $LogFile

        $Path = $endpoint.Path
        $Method = $endpoint.Method
    }

    $uri = Join-S2Uri -Connection $Connection -Path $Path -LogFile $LogFile

    Assert-S2QueryCollection -Query $Query -LogFile $LogFile
    
    if ($null -ne $Query -and $Query.Count -gt 0) {
        $queryParts = foreach ($key in $Query.Keys) {
            if ($null -ne $Query[$key]) {
                '{0}={1}' -f (
                    [System.Uri]::EscapeDataString([string]$key)
                ), (
                    [System.Uri]::EscapeDataString([string]$Query[$key])
                )
            }
        }

        if (@($queryParts).Count -gt 0) {
            $separator = if ($uri.Contains('?')) { '&' } else { '?' }
            $uri = '{0}{1}{2}' -f $uri, $separator, ($queryParts -join '&')
        }
    }

    $session = New-S2WebSession -Connection $Connection -LogFile $LogFile

    try {
        $response = Invoke-RestMethod `
            -UseBasicParsing `
            -Uri $uri `
            -Method $Method `
            -WebSession $session `
            -ErrorAction Stop

        if ($null -eq $response) {
            $Message = 'The S2 REST endpoint returned an empty response.'
            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name
            throw [System.InvalidOperationException]::new($Message) 
        }

        $Message = ("Retrieved S2 REST resource: {0}" -f $Path) 
        Write-S2Information `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name

        return $response
    }
    catch {
        $Message = "Unable to retrieve S2 REST resource '$Path' from host '$($Connection.HostName)': $($_.Exception.Message)"

        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message) 
    }
}

function Get-S2JsonCollection {
    <#
    .SYNOPSIS
        Retrieves a JSON response from a published S2 REST endpoint.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject]$Connection,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'Endpoint')]
        [ValidateNotNullOrEmpty()]
        [string]$EndpointName,

        [Parameter(ParameterSetName = 'Endpoint')]
        [AllowNull()]
        [hashtable]$EndpointValue,

        [ValidateRange(1, 2147483647)]
        [int]$Page,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $requestParameters = @{
        Connection = $Connection
        LogFile    = $LogFile
    }

    if ($PSCmdlet.ParameterSetName -eq 'Endpoint') {
        $requestParameters.EndpointName = $EndpointName
        $requestParameters.EndpointValue = $EndpointValue
    }
    else {
        $requestParameters.Path = $Path
    }

    if ($PSBoundParameters.ContainsKey('Page')) {
        $requestParameters.Query = @{ page = $Page }
    }

    $Message = (" Get S2 Json Collection for  {0}" -f $EndpointName)
    Write-S2Verbose `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
    return Invoke-S2RestRequest @requestParameters
}

function Get-S2JsonRows {
    <#
    .SYNOPSIS
        Retrieves and aggregates rows from a paginated S2 REST collection.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject]$Connection,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'Endpoint')]
        [ValidateNotNullOrEmpty()]
        [string]$EndpointName,

        [Parameter(ParameterSetName = 'Endpoint')]
        [AllowNull()]
        [hashtable]$EndpointValue,

        [ValidateRange(1, 2147483647)]
        [int]$StartPage = 1,

        [ValidateRange(1, 100000)]
        [int]$MaximumPages = 10000,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    if ($PSCmdlet.ParameterSetName -eq 'Endpoint') {
        $endpoint = Get-S2RestEndpoint `
            -Name $EndpointName `
            -Value $EndpointValue `
            -LogFile $LogFile 

        if ($endpoint.ResponseType -ne 'Collection') {
            $Message = ( "S2 REST endpoint '{0}' is not a collection endpoint." -f $endpoint.Name )
            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name
            throw [System.InvalidOperationException]::new($Message) 
        }

        $resolvedPath = $endpoint.Path
    }
    else {
        $resolvedPath = $Path
    }

    $rows = New-Object System.Collections.Generic.List[object]
    $pageNumber = $StartPage
    $pageCount = $null

    do {
        if (($pageNumber - $StartPage + 1) -gt $MaximumPages) {
            $Message = "Pagination exceeded MaximumPages ($MaximumPages) for '$resolvedPath'."
            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name
            throw [System.InvalidOperationException]::new($Message) 
        }

        $response = Get-S2JsonCollection `
            -Connection $Connection `
            -Path $resolvedPath `
            -Page $pageNumber `
            -LogFile $LogFile 

        if ($null -eq $response.PSObject.Properties['rows']) {
            $Message = "S2 REST collection '$resolvedPath' did not return a rows property."
            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name
            throw [System.InvalidOperationException]::new($Message) 
        }

        foreach ($row in @($response.rows)) {
            if ($null -ne $row) {
                [void]$rows.Add($row)
            }
        }

        if (
            $null -ne $response.PSObject.Properties['total'] -and
            -not [string]::IsNullOrWhiteSpace($response.total)
        ) {
            $parsedPageCount = 0

            if (
                $null -ne $response.PSObject.Properties['total'] -and
                [int]::TryParse(
                    [string]$response.total,
                    [ref]$parsedPageCount
                ) -and
                $parsedPageCount -ge 1
            ) {
                $pageCount = $parsedPageCount
            }
            else {
                $Message = (
                    "S2 REST collection '{0}' returned invalid pagination metadata." `
                        -f $resolvedPath
                )

                Write-S2Error `
                    -Message $Message `
                    -LogFile $LogFile `
                    -FileName $PSCommandPath `
                    -Source $MyInvocation.MyCommand.Name

                throw [System.InvalidOperationException]::new($Message)
            }

            $pageCount = $parsedPageCount
        }
        else {
            $pageCount = $pageNumber
        }
        $Message = ("Retrieved page {0} of {1} from {2}" -f $pageNumber, $pageCount, $resolvedPath)
        Write-S2Verbose `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name

        $pageNumber++
    }
    while ($pageNumber -le $pageCount)

    return , $rows.ToArray()
}

#endregion REST Request Functions

#region Public Exports

Export-ModuleMember -Function @(
    'Initialize-S2RestApiCatalog',
    'Get-S2RestEndpoint',
    'Get-S2RestEndpointCatalog',
    'Invoke-S2RestRequest',
    'Get-S2JsonCollection',
    'Get-S2JsonRows'
)

#endregion Public Exports
