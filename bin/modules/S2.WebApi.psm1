<#
.SYNOPSIS
    Provides the internal LenelS2 NetBox Web API communication layer.

.DESCRIPTION
    Centralizes internal NetBox Web API endpoint lookup, authenticated web
    requests, optional CSRF handling, JSON form-body creation, response
    validation, and logging for the S2 Toolbox.

    Shared connection validation, URI construction, web-session creation,
    JSON form encoding, and logging are provided by S2.Api.Common.psm1.

    This module is intended for internal web endpoints that are separate from
    the published REST resources handled by S2.RestApi.psm1 and the XML NBAPI
    commands handled by S2.NBAPI.psm1.

    Internal endpoints may change between NetBox releases. Callers should use
    named endpoint definitions where available and explicit paths only when
    required.

.NOTES
    FileName   : S2.WebApi.psm1
    Author     : Brian Kendrick
    Application: S2 Toolbox
    Requires   : Windows PowerShell 5.1
    Version    : 1.0.0

.CHANGELOG
    1.0.0
        - Refactored internal Web API operations from S2.Api.psm1
        - Added centralized internal endpoint catalog
        - Added authenticated GET, POST, PUT, and DELETE request handling
        - Added configurable CSRF header handling
        - Added raw, JSON, and form-encoded JSON request-body support
        - Added endpoint catalog validation during module import
#>

#requires -Version 5.1
Set-StrictMode -Version Latest

#region Catalog
function Initialize-S2ApiWebCatalog {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $endpointCatalogPath = Join-Path `
        -Path $PSScriptRoot `
        -ChildPath '..\..\resources\S2.WebApi.Endpoints.psd1'

    if (-not (Test-Path -LiteralPath $endpointCatalogPath -PathType Leaf)) {
        $Message = ( "Required Web API endpoint catalog not found: {0}" -f $endpointCatalogPath )
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }

    $script:S2WebApiEndpoints = Import-PowerShellDataFile `
        -Path $endpointCatalogPath

    if (
        $null -eq $script:S2WebApiEndpoints -or
        $script:S2WebApiEndpoints.Count -eq 0
    ) {
        $Message = ( "Web API endpoint catalog loaded successfully but contains no endpoints: {0}" -f $endpointCatalogPath )
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
        'Description'
    )

    foreach ($endpointKey in $script:S2WebApiEndpoints.Keys) {
        $definition = $script:S2WebApiEndpoints[$endpointKey]

        if ($definition -isnot [hashtable]) {
            $Message = ( "Web API endpoint '{0}' must be defined as a hashtable." -f $endpointKey )
            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name
            throw [System.InvalidOperationException]::new($Message)
        }

        foreach ($property in $requiredEndpointProperties) {
            if (
                -not $definition.ContainsKey($property) -or
                [string]::IsNullOrWhiteSpace([string]$definition[$property])
            ) {
                $Message = ( "Web API endpoint '{0}' is missing required property '{1}'." -f $endpointKey, $property )
                Write-S2Error `
                    -Message $Message `
                    -LogFile $LogFile `
                    -FileName $PSCommandPath `
                    -Source $MyInvocation.MyCommand.Name
                throw [System.InvalidOperationException]::new($Message)
            }
        }

        if (
            [string]$definition.Method -notin @(
                'Get'
                'Post'
                'Put'
                'Delete'
            )
        ) {
            $Message = ( "Web API endpoint '{0}' has unsupported method '{1}'." -f $endpointKey, $definition.Method )
            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name
            throw [System.InvalidOperationException]::new($Message)
        }

        if (-not ([string]$definition.Path).StartsWith('/')) {
            $Message = ( "Web API endpoint '{0}' must define an absolute application path beginning with '/'." -f $endpointKey )
            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name
            throw [System.InvalidOperationException]::new($Message)
        }
    }
    return  $script:S2WebApiEndpoints
}
#endregion Catalog 

#region Endpoint Functions

function Get-S2WebApiEndpoint {
    <#
    .SYNOPSIS
        Resolves an internal S2 Web API endpoint by name.
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

    Assert-S2WebEndpointValues -Name $Name -Value $Value -LogFile $LogFile

    $Message = ( "Getting S2 Web API endpoint '{0}'." -f $endpointKey )
    Write-S2Information `
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
        Description   = [string]$definition.Description
        RequiresValue = $false
    }
}

function Get-S2WebApiEndpointCatalog {
    <#
    .SYNOPSIS
        Returns the internal S2 Web API endpoint catalog.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    foreach ($key in $script:S2WebApiEndpoints.Keys) {
        $definition = $script:S2WebApiEndpoints[$key]
        $Message = ( "Get S2 Web API endpoint '{0}'. definition from Catalog. {1} :: {2}" -f $key, $definition.Category, $definition.Action)
        Write-S2Debug `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        [pscustomobject]@{
            Name          = $key
            Path          = [string]$definition.Path
            Method        = [string]$definition.Method
            Category      = [string]$definition.Category
            Action        = [string]$definition.Action
            Description   = [string]$definition.Description
            RequiresValue = [bool]([string]$definition.Path -match '\{[^}]+\}')
        }
    }
}

#endregion Endpoint Functions

#region Request Functions

function Invoke-S2WebApiRequest {
    <#
    .SYNOPSIS
        Invokes an authenticated request against an internal S2 Web API endpoint.
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

        [ValidateSet('Get', 'Post', 'Put', 'Delete')]
        [string]$Method,

        [AllowNull()]
        [hashtable]$Query,

        [AllowNull()]
        [object]$Body,

        [ValidateSet('Raw', 'Json', 'JsonForm')]
        [string]$BodyFormat = 'Raw',

        [ValidateRange(1, 100)]
        [int]$JsonDepth = 10,

        [AllowNull()]
        [hashtable]$Headers,

        [switch]$IncludeCsrfToken,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$CsrfHeaderName,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    Assert-S2WebConnection -Connection $Connection -LogFile $LogFile

    if ($PSCmdlet.ParameterSetName -eq 'Endpoint') {
        $endpoint = Get-S2WebApiEndpoint `
            -Name $EndpointName `
            -Value $EndpointValue `
            -LogFile $LogFile

        $Path = $endpoint.Path

        if (
            $PSBoundParameters.ContainsKey('Method') -and
            $Method -ine $endpoint.Method
        ) {
            $Message = ( "Web API endpoint '{0}' requires method '{1}', but method '{2}' was requested." -f $endpoint.Name, $endpoint.Method, $Method )
            Write-S2Error `
                -Message $Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name
            throw [System.InvalidOperationException]::new($Message)
        }

        $Method = $endpoint.Method
    }
    elseif (-not $PSBoundParameters.ContainsKey('Method')) {
        $Method = 'Get'
    }

    Assert-S2WebRequest -Method $Method -Body $Body -BodyFormat $BodyFormat -LogFile $LogFile

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

    $requestHeaders = @{}
    Assert-S2HeaderCollection -Headers $Headers -LogFile $LogFile

    if ($null -ne $Headers) {
        foreach ($key in $Headers.Keys) {
            $requestHeaders[$key] = $Headers[$key]
        }
    }

    if ($IncludeCsrfToken.IsPresent) {
        $requestHeaders[$CsrfHeaderName] = Assert-S2CsrfRequest -Connection $Connection -IncludeCsrfToken $IncludeCsrfToken -CsrfHeaderName $CsrfHeaderName -LogFile $LogFile

    }
   
    $requestParameters = @{
        Uri         = $uri
        Method      = $Method
        WebSession  = New-S2WebSession -Connection $Connection -LogFile $LogFile
        ErrorAction = 'Stop'
    }

    if ($requestHeaders.Count -gt 0) {
        $requestParameters.Headers = $requestHeaders
    }

    if ($null -ne $Body) {
        switch ($BodyFormat) {
            'Json' {
                $requestParameters.Body = ConvertTo-Json `
                    -InputObject $Body `
                    -Compress `
                    -Depth $JsonDepth
                $requestParameters.ContentType = 'application/json'
            }

            'JsonForm' {
                $requestParameters.Body = ConvertTo-S2JsonFormBody `
                    -InputObject $Body `
                    -Depth $JsonDepth `
                    -LogFile $LogFile
                $requestParameters.ContentType = 'application/x-www-form-urlencoded'
            }

            'Raw' {
                $requestParameters.Body = $Body
            }
        }
    }

    try {
        $response = Invoke-RestMethod @requestParameters

        if ($null -eq $response) {
            throw 'The S2 Web API endpoint returned an empty response.'
        }

        $Message = ("S2 Web API request succeeded: {0} {1}" -f $Method, $Path)
        Write-S2Information `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name

        return $response
    }
    catch {
        $Message = "S2 Web API request '$Method $Path' failed for host '$($Connection.HostName)': $($_.Exception.Message)"

        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }
}

#endregion Request Functions

#region Convenience Functions

function Get-S2WebApiResource {
    <#
    .SYNOPSIS
        Retrieves a resource from an internal S2 Web API endpoint.
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

        [AllowNull()]
        [hashtable]$Query,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $parameters = @{
        Connection = $Connection
        Method     = 'Get'
        Query      = $Query
        LogFile    = $LogFile
    }

    if ($PSCmdlet.ParameterSetName -eq 'Endpoint') {
        $parameters.EndpointName = $EndpointName
        $parameters.EndpointValue = $EndpointValue
    }
    else {
        $parameters.Path = $Path
    }

    return Invoke-S2WebApiRequest @parameters 
}

function Send-S2WebApiResource {
    <#
    .SYNOPSIS
        Sends a request body to an internal S2 Web API endpoint.
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

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Body,

        [ValidateSet('Post', 'Put', 'Delete')]
        [string]$Method = 'Post',

        [ValidateSet('Raw', 'Json', 'JsonForm')]
        [string]$BodyFormat = 'JsonForm',

        [ValidateRange(1, 100)]
        [int]$JsonDepth = 10,

        [AllowNull()]
        [hashtable]$Query,

        [AllowNull()]
        [hashtable]$Headers,

        [switch]$IncludeCsrfToken,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$CsrfHeaderName,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $parameters = @{
        Connection = $Connection
        Method     = $Method
        Body       = $Body
        BodyFormat = $BodyFormat
        JsonDepth  = $JsonDepth
        Query      = $Query
        Headers    = $Headers
        LogFile    = $LogFile
    }

    if ($IncludeCsrfToken.IsPresent) {
        $parameters.IncludeCsrfToken = $true
        $parameters.CsrfHeaderName = $CsrfHeaderName
    }

    if ($PSCmdlet.ParameterSetName -eq 'Endpoint') {
        $parameters.EndpointName = $EndpointName
        $parameters.EndpointValue = $EndpointValue
    }
    else {
        $parameters.Path = $Path
    }
    $Message = (" Get Web Api resource  {0}" -f $EndpointName)
    Write-S2Information `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
    return Invoke-S2WebApiRequest @parameters 
}

#endregion Convenience Functions

#region Public Exports

Export-ModuleMember -Function @(
    'Initialize-S2ApiWebCatalog',
    'Get-S2WebApiEndpoint',
    'Get-S2WebApiEndpointCatalog',
    'Invoke-S2WebApiRequest',
    'Get-S2WebApiResource',
    'Send-S2WebApiResource'
)

#endregion Public Exports
