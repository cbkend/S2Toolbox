<#
.SYNOPSIS
    Provides the LenelS2 NetBox NBAPI communication layer.

.DESCRIPTION
    Centralizes NBAPI XML formatting, command invocation, response validation,
    and NBAPI error handling for the S2 Toolbox.

    This module only supports the NetBox XML NBAPI endpoint:

        /nbws/goforms/nbapi

    Session management, logging infrastructure, and connection creation
    are provided by S2.Api.Common.psm1.

.NOTES
    FileName   : S2.NBAPI.psm1
    Author     : Brian Kendrick
    Application: S2 Toolbox
    Requires   : Windows PowerShell 5.1
    Version    : 1.0.0

.CHANGELOG
    1.0.0
        - Refactored from S2.Api.psm1
        - Dedicated NBAPI command transport layer
#>

#requires -Version 5.1
Set-StrictMode -Version Latest

#region Catalog
function Initialize-S2NBAPICatalog {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )
    
    $commandCatalogPath = Join-Path `
        -Path $PSScriptRoot `
        -ChildPath '..\..\resources\S2.NBAPI.Commands.psd1'
    
    if (-not (Test-Path $commandCatalogPath)) {
        $Message = ("Required NBAPI command catalog not found: {0}" -f $commandCatalogPath )
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }

    $script:NBApiCommands =
    Import-PowerShellDataFile `
        -Path $commandCatalogPath

    if ($null -eq $script:NBApiCommands -or
        $script:NBApiCommands.Count -eq 0) {
        $Message = ( "NBAPI command catalog loaded successfully but contains no commands: {0}" -f $commandCatalogPath )
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    
    }
    return $script:NBApiCommands
}
#endregion Catalog 

#region Constants
$script:NbApiEndpoint = '/nbws/goforms/nbapi'

$script:S2NbApiErrors = @{
    1 = 'API initialization failure'
    2 = 'API is disabled'
    3 = 'Invalid API command'
    4 = 'API command parse failure'
    5 = 'API authentication failure'
    6 = 'Unknown API command'
}
#endregion Constants

#region XML Functions
function Format-S2NBApiCommandXml {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)]
        [string]$CommandName,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$CommandParameters,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$SessionId,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.OmitXmlDeclaration = $true
    $settings.Indent = $true

    $builder = New-Object System.Text.StringBuilder
    $writer = [System.Xml.XmlWriter]::Create($builder, $settings)

    try {
        $writer.WriteStartElement('NETBOX-API')

        if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
            $writer.WriteAttributeString('sessionid', $SessionId)
        }

        $writer.WriteStartElement('COMMAND')
        $writer.WriteAttributeString('name', $CommandName)
        $writer.WriteAttributeString('num', 1)
        $writer.WriteAttributeString('dateformat', 'tzoffset')

        if (-not [string]::IsNullOrWhiteSpace($CommandParameters)) {
            $fragment = New-Object System.Xml.XmlDocument
            $fragment.PreserveWhitespace = $true
            $wrapper = $fragment.CreateElement('WRAPPER')
            $wrapper.InnerXml = $CommandParameters
            foreach ($child in @($wrapper.ChildNodes)) {
                $child.WriteTo($writer)
            }
        }

        $writer.WriteEndElement()
        $writer.WriteEndElement()
        $writer.Flush()
    }
    finally {
        $writer.Dispose()
    }
    [xml]$commandXml = $builder.ToString()
    [xml]$logXml = $commandXml.OuterXml

    $currentId = [string]$logXml.'NETBOX-API'.sessionid

    if (-not [string]::IsNullOrWhiteSpace($currentId)) {
        $visibleLength = 4

        $currentId = [string]$logXml.'NETBOX-API'.sessionid

        if (-not [string]::IsNullOrWhiteSpace($currentId)) {
            $visibleLength = [Math]::Min(4, $currentId.Length)
            $maskedLength = $currentId.Length - $visibleLength

            $lastFour = $currentId.Substring(
                $currentId.Length - $visibleLength
            )

            $logXml.'NETBOX-API'.sessionid =
            ('*' * $maskedLength) + $lastFour
        }
    }

    Write-S2Debug `
        -Message ("NBAPI XML Command {0}" -f $logXml.OuterXml) `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name

    return $commandXml
}

function New-S2NBApiCommandXml {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Command,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$CommandParameters,

        [string]$SessionId,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $definition = Get-S2NBApiCommand -Name $Command -LogFile $LogFile

    Assert-S2NBApiDefinition -NBApiCommand $definition  -LogFile $LogFile 

    $Message = ("NBAPI Command for value {0} :: {1}" -f $definition.Number, $Command )
    Write-S2Debug `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
    Format-S2NBApiCommandXml -CommandName $Command -CommandParameters $CommandParameters -SessionId $SessionId -LogFile $LogFile
}
#endregion XML Functions

#region Command Catalog Functions
function Get-S2NBApiCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $commandKey =
    $script:NBApiCommands.Keys |
    Where-Object { $_ -ieq $Name } |
    Select-Object -First 1

    if (-not $commandKey) {
        $Message = "Unknown NBAPI command '$Name'."
        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message)
    }
    $Message = ("Get NBAPI Command for value for {0}." -f $Name )
    Write-S2Debug `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
    return $script:NBApiCommands[$commandKey]
}

function Resolve-S2NBApiCommand {

    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $definition = Get-S2NBApiCommand -Name $Name -LogFile $LogFile

    $Message = ("Resolve NBAPI Command for value for {0}." -f $Name )
    Write-S2Debug `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
    [pscustomobject]@{
        Name        = $Name
        Number      = $definition.Number
        Category    = $definition.Category
        Action      = $definition.Action
        Description = $definition.Description
    }
}

function Get-S2NBApiCommandCatalog {

    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $Message = "Get NBAPI Command Catalog." 
    Write-S2Debug `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
    foreach ($key in $script:NBApiCommands.Keys) {

        $command = $script:NBApiCommands[$key]

        [pscustomobject]@{
            Name        = $key
            Number      = [int]$command.Number
            Category    = $command.Category
            Action      = $command.Action
            Description = $command.Description
        }
    }
}
#endregion Command Catalog Functions

#region Internal Functions
function Get-S2NBApiErrorDescription {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$ApiError
    )

    $errorCode = 0

    if (
        [int]::TryParse(
            [string]$ApiError,
            [ref]$errorCode
        ) -and
        $script:S2NbApiErrors.ContainsKey($errorCode)
    ) {
        return [string]$script:S2NbApiErrors[$errorCode]
    }

    return 'Unknown API error'
}

#endregion Internal Functions

#region Transport Functions
function Invoke-S2NBApiCommand {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)]
        [psobject]$Connection,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [xml]$CommandXml,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    if ($Name -ieq 'Login') {
        Assert-S2ApiConnection `
            -Connection $Connection `
            -LogFile $LogFile
    }
    else {
        Assert-S2NBApiConnection `
            -Connection $Connection `
            -LogFile $LogFile
    }

    $uri = Join-S2Uri `
        -Connection $Connection `
        -Path $script:NbApiEndpoint `
        -LogFile $LogFile

    try {
        $response = Invoke-RestMethod `
            -Uri $uri `
            -Method Post `
            -ContentType 'application/xml' `
            -Body $CommandXml.OuterXml `
            -ErrorAction Stop
    }
    catch {
        $Message = (
            "NBAPI command '{0}' failed against host '{1}'. {2}" -f
            $Name,
            $Connection.HostName,
            $_.Exception.Message
        )

        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name

        throw [System.InvalidOperationException]::new($Message)
    }

    $responseCode = [string]$response.NETBOX.RESPONSE.CODE

    if ($responseCode -ne 'SUCCESS') {

        $apiError = $response.NETBOX.RESPONSE.APIERROR
        $errorMessage = [string]$response.NETBOX.RESPONSE.DETAILS.ERRMSG
        $description = Get-S2NBApiErrorDescription `
            -ApiError $apiError 

        $Message = "NBAPI command '$Name' failed."

        if ($apiError) {
            $Message += " API Error: $apiError."
        }

        if ($description) {
            $Message += " Description: $description."
        }

        if (-not [string]::IsNullOrWhiteSpace($errorMessage)) {
            $Message += " API Error Message: $errorMessage."
        }

        Write-S2Error `
            -Message $Message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
        throw [System.InvalidOperationException]::new($Message) 
    }
    [xml]$responseXml = $response
    [xml]$logResponse = $responseXml.OuterXml

    $currentId = [string]$logResponse.NETBOX.sessionid

    if (-not [string]::IsNullOrWhiteSpace($currentId)) {
        $visibleLength = 4
        $logResponse.NETBOX.sessionid =
        ('*' * ($currentId.Length - $visibleLength)) +
        $currentId.Substring(
            $currentId.Length - $visibleLength
        )
    }

    Write-S2Debug `
        -Message (
        "Invoke NBAPI Command '{0}' :: {1} :: Host={2}" -f
        $Name,
        $logResponse.OuterXml,
        $Connection.HostName
    ) `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name

    return $responseXml
}
#endregion Transport Functions

#region Public Exports
Export-ModuleMember -Function @(
    'Initialize-S2NBAPICatalog',
    'Format-S2NBApiCommandXml',
    'New-S2NBApiCommandXml',
    'Invoke-S2NBApiCommand',
    'Get-S2NBApiCommand',
    'Get-S2NBApiCommandCatalog',
    'Resolve-S2NBApiCommand'
)
#endregion Public Exports