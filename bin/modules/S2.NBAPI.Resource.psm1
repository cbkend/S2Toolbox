<#
.SYNOPSIS
    Provides shared NBAPI-only resource services for S2 Toolbox.
.DESCRIPTION
    Centralizes NBAPI parameter XML creation, command execution, XML-to-object
    conversion, paginated collection retrieval, name-to-key lookup resolution,
    and generic Add/Set/Remove operations.

    This module does not use the Web API or published REST API.
.NOTES
    FileName   : S2.NBAPI.Resource.psm1
    Application: S2 Toolbox
    Requires   : Windows PowerShell 5.1
    Version    : 1.0.0
#>
#requires -Version 5.1
Set-StrictMode -Version Latest

#region Constants
function Add-S2NBApiXmlValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Xml.XmlDocument]$Document,
        [Parameter(Mandatory)] [System.Xml.XmlElement]$Parent,
        [Parameter(Mandatory)] [ValidatePattern('^[A-Za-z][A-Za-z0-9_-]*$')] [string]$Name,
        [Parameter()] [AllowNull()] [object]$Value,
        [switch]$OmitEmpty
    )

    if ($null -eq $Value) {
        if (-not $OmitEmpty.IsPresent) {
            [void]$Parent.AppendChild($Document.CreateElement($Name))
        }
        return
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $container = $Document.CreateElement($Name)
        foreach ($entry in $Value.GetEnumerator()) {
            Add-S2NBApiXmlValue -Document $Document -Parent $container `
                -Name ([string]$entry.Key) -Value $entry.Value -OmitEmpty:$OmitEmpty
        }
        [void]$Parent.AppendChild($container)
        return
    }

    if ($Value -is [System.Xml.XmlNode]) {
        $container = $Document.CreateElement($Name)
        [void]$container.AppendChild($Document.ImportNode($Value, $true))
        [void]$Parent.AppendChild($container)
        return
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $container = $Document.CreateElement($Name)
        foreach ($item in @($Value)) {
            if ($item -is [System.Collections.IDictionary] -and $item.Contains('ElementName')) {
                $itemName = [string]$item.ElementName
                $itemValue = if ($item.Contains('Value')) { $item.Value } else { $null }
                Add-S2NBApiXmlValue -Document $Document -Parent $container `
                    -Name $itemName -Value $itemValue -OmitEmpty:$OmitEmpty
            }
            else {
                throw "Enumerable NBAPI values for '$Name' must contain ElementName and Value entries."
            }
        }
        [void]$Parent.AppendChild($container)
        return
    }

    $text = [string]$Value
    if ($OmitEmpty.IsPresent -and [string]::IsNullOrWhiteSpace($text)) { return }
    $node = $Document.CreateElement($Name)
    $node.InnerText = $text
    [void]$Parent.AppendChild($node)
}

function ConvertTo-S2NBApiParametersXml {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Values,
        [string[]]$RequiredElement = @(),
        [switch]$OmitEmpty
    )

    foreach ($required in $RequiredElement) {
        if (-not $Values.Contains($required) -or
            [string]::IsNullOrWhiteSpace([string]$Values[$required])) {
            throw "Required NBAPI parameter '$required' was not supplied."
        }
    }

    $document = New-Object System.Xml.XmlDocument
    $parameters = $document.CreateElement('PARAMS')
    [void]$document.AppendChild($parameters)

    foreach ($entry in $Values.GetEnumerator()) {
        Add-S2NBApiXmlValue -Document $document -Parent $parameters `
            -Name ([string]$entry.Key).ToUpperInvariant() `
            -Value $entry.Value -OmitEmpty:$OmitEmpty
    }

    return $parameters.OuterXml
}

function Invoke-S2NBApiResourceCommand {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)] [ValidateNotNull()] [psobject]$Connection,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$CommandName,
        [System.Collections.IDictionary]$Values = ([ordered]@{}),
        [string[]]$RequiredElement = @(),
        [Parameter(Mandatory)] [ValidateNotNull()] [string]$LogFile
    )

    $null = Get-S2NBApiCommand -Name $CommandName -LogFile $LogFile
    $parameterXml = ConvertTo-S2NBApiParametersXml `
        -Values $Values -RequiredElement $RequiredElement -OmitEmpty

    [xml]$commandXml = New-S2NBApiCommandXml `
        -Command $CommandName `
        -CommandParameters $parameterXml `
        -SessionId $Connection.SessionId `
        -LogFile $LogFile

    return Invoke-S2NBApiCommand `
        -Connection $Connection `
        -Name $CommandName `
        -CommandXml $commandXml `
        -LogFile $LogFile
}

function ConvertFrom-S2NBApiXmlNode {
    [CmdletBinding()]
    [OutputType([object])]
    param([Parameter(Mandatory, ValueFromPipeline)] [System.Xml.XmlNode]$Node)

    process {
        $elementChildren = @($Node.ChildNodes | Where-Object NodeType -eq 'Element')
        if ($elementChildren.Count -eq 0) { return [string]$Node.InnerText }

        $result = [ordered]@{}
        foreach ($group in ($elementChildren | Group-Object Name)) {
            $converted = @($group.Group | ForEach-Object { ConvertFrom-S2NBApiXmlNode -Node $_ })
            $result[$group.Name] = if ($converted.Count -eq 1) { $converted[0] } else { $converted }
        }
        return [pscustomobject]$result
    }
}

function Get-S2NBApiResourceCollection {
    <#
    .SYNOPSIS
        Retrieves a complete paged NBAPI resource collection.

    .DESCRIPTION
        Retrieves every page of an NBAPI resource collection by following
        NEXTKEY or NEXTNAME continuation values.

        When DetailCommandName is supplied, each collection item is treated as
        a resource key. The corresponding detail command is then invoked and
        the detail result is converted to an object.

        Existing callers that do not specify detail parameters retain the
        original collection behavior.

    .PARAMETER Connection
        Authenticated S2 NBAPI connection.

    .PARAMETER CommandName
        NBAPI collection command name.

    .PARAMETER ItemXPath
        XPath selecting collection items from each response page.

    .PARAMETER PagingMode
        Key uses STARTFROMKEY and NEXTKEY.
        Name uses STARTFROMNAME and NEXTNAME.

    .PARAMETER NextValueXPath
        Optional continuation-token XPath override.

    .PARAMETER Values
        Additional values included with each collection request.

    .PARAMETER DetailCommandName
        Optional NBAPI command used to retrieve each item's detail record.

    .PARAMETER DetailKeyElement
        NBAPI parameter element supplied to the detail command.

    .PARAMETER DetailXPath
        XPath selecting the detail resource from the detail response.

    .PARAMETER KeyPropertyName
        Property added to the converted detail object containing the key.

    .PARAMETER MaximumPages
        Maximum number of collection pages that can be processed.

    .PARAMETER LogFile
        S2 log filename or path.
    #>

    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject]$Connection,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$CommandName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ItemXPath,

        [Parameter()]
        [ValidateSet('Key', 'Name')]
        [string]$PagingMode = 'Key',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$NextValueXPath,

        [Parameter()]
        [ValidateNotNull()]
        [System.Collections.IDictionary]$Values = ([ordered]@{}),

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$DetailCommandName,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$DetailKeyElement,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$DetailXPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$KeyPropertyName,

        [Parameter()]
        [ValidateRange(1, 100000)]
        [int]$MaximumPages = 10000,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string]$LogFile
    )

    $detailParameters = @(
        $DetailCommandName,
        $DetailKeyElement,
        $DetailXPath,
        $KeyPropertyName
    )

    $specifiedDetailParameterCount = @(
        $detailParameters |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_)
        }
    ).Count

    if ($specifiedDetailParameterCount -notin @(0, 4)) {
        $message = @(
            'Detail retrieval requires all detail parameters:'
            'DetailCommandName'
            'DetailKeyElement'
            'DetailXPath'
            'KeyPropertyName'
        ) -join ' '

        Write-S2Error `
            -Message $message `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name

        throw [System.ArgumentException]::new($message)
    }

    $retrieveDetails = ($specifiedDetailParameterCount -eq 4)

    # Validate command definitions before starting the paging loop.
    $null = Get-S2NBApiCommand `
        -Name $CommandName `
        -LogFile $LogFile

    if ($retrieveDetails) {
        $null = Get-S2NBApiCommand `
            -Name $DetailCommandName `
            -LogFile $LogFile
    }

    $results =
    New-Object System.Collections.Generic.List[object]

    $page = 0
    $visitedTokens = @{}

    switch ($PagingMode) {
        'Key' {
            $currentToken = 0
            $startParameter = 'STARTFROMKEY'

            if ([string]::IsNullOrWhiteSpace($NextValueXPath)) {
                $NextValueXPath =
                '/NETBOX/RESPONSE/DETAILS/NEXTKEY'
            }
        }

        'Name' {
            $currentToken = ''
            $startParameter = 'STARTFROMNAME'

            if ([string]::IsNullOrWhiteSpace($NextValueXPath)) {
                $NextValueXPath =
                '/NETBOX/RESPONSE/DETAILS/NEXTNAME'
            }
        }
    }

    do {
        $page++

        if ($page -gt $MaximumPages) {
            $message = (
                "Maximum NBAPI page count exceeded for command '{0}'." -f
                $CommandName
            )

            Write-S2Error `
                -Message $message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name

            throw [System.InvalidOperationException]::new($message)
        }

        Write-S2Verbose `
            -Message (
            'NBAPI paging :: Command={0}; Page={1}; Token={2}' -f
            $CommandName,
            $page,
            $currentToken
        ) `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name

        $requestValues = [ordered]@{}

        foreach ($item in $Values.GetEnumerator()) {
            $requestValues[$item.Key] = $item.Value
        }

        $requestValues[$startParameter] = $currentToken

        [xml]$response =
        Invoke-S2NBApiResourceCommand `
            -Connection $Connection `
            -CommandName $CommandName `
            -Values $requestValues `
            -LogFile $LogFile

        $pageNodes = @(
            $response.SelectNodes($ItemXPath)
        )

        foreach ($node in $pageNodes) {
            if (-not $retrieveDetails) {
                [void]$results.Add(
                    (ConvertFrom-S2NBApiXmlNode -Node $node)
                )

                continue
            }

            $keyValue = ([string]$node.InnerText).Trim()

            if ([string]::IsNullOrWhiteSpace($keyValue)) {
                $message = (
                    "NBAPI collection command '{0}' returned an empty key." -f
                    $CommandName
                )

                Write-S2Warning `
                    -Message $message `
                    -LogFile $LogFile `
                    -FileName $PSCommandPath `
                    -Source $MyInvocation.MyCommand.Name

                continue
            }

            $detailValues = [ordered]@{
                $DetailKeyElement = $keyValue
            }

            [xml]$detailResponse =
            Invoke-S2NBApiResourceCommand `
                -Connection $Connection `
                -CommandName $DetailCommandName `
                -Values $detailValues `
                -RequiredElement @($DetailKeyElement) `
                -LogFile $LogFile

            $detailNode =
            $detailResponse.SelectSingleNode($DetailXPath)

            if ($null -eq $detailNode) {
                $message = (
                    "NBAPI detail command '{0}' did not return XPath '{1}' " +
                    "for key '{2}'."
                ) -f
                $DetailCommandName,
                $DetailXPath,
                $keyValue

                Write-S2Error `
                    -Message $message `
                    -LogFile $LogFile `
                    -FileName $PSCommandPath `
                    -Source $MyInvocation.MyCommand.Name

                throw [System.InvalidOperationException]::new($message)
            }

            $detail =
            ConvertFrom-S2NBApiXmlNode `
                -Node $detailNode

            if ($detail -isnot [psobject]) {
                $message = (
                    "NBAPI detail command '{0}' returned a scalar value " +
                    "instead of a resource object for key '{1}'."
                ) -f
                $DetailCommandName,
                $keyValue

                Write-S2Error `
                    -Message $message `
                    -LogFile $LogFile `
                    -FileName $PSCommandPath `
                    -Source $MyInvocation.MyCommand.Name

                throw [System.InvalidOperationException]::new($message)
            }

            $detail |
            Add-Member `
                -NotePropertyName $KeyPropertyName `
                -NotePropertyValue $keyValue `
                -Force

            [void]$results.Add($detail)
        }

        $nextNode =
        $response.SelectSingleNode($NextValueXPath)

        if ($null -eq $nextNode -or
            [string]::IsNullOrWhiteSpace(
                [string]$nextNode.InnerText
            )) {

            break
        }

        $nextToken = ([string]$nextNode.InnerText).Trim()

        if ($visitedTokens.ContainsKey($nextToken)) {
            $message = (
                "Detected NBAPI paging loop for command '{0}'. " +
                "Token '{1}' was already processed."
            ) -f
            $CommandName,
            $nextToken

            Write-S2Error `
                -Message $message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name

            throw [System.InvalidOperationException]::new($message)
        }

        $visitedTokens[$nextToken] = $true
        $currentToken = $nextToken
    }
    while ($true)

    Write-S2Verbose `
        -Message (
        'NBAPI collection completed :: Command={0}; Pages={1}; Items={2}' -f
        $CommandName,
        $page,
        $results.Count
    ) `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name

    return , $results.ToArray()
}

function Resolve-S2NBApiResourceKey {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [object[]]$InputObject,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$Name,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string[]]$NameProperty,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string[]]$KeyProperty,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$ResourceName,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$LogFile
    )

    $matches = @($InputObject | Where-Object {
            $candidate = $null
            foreach ($propertyName in $NameProperty) {
                $property = $_.PSObject.Properties | Where-Object Name -ieq $propertyName | Select-Object -First 1
                if ($null -ne $property) { $candidate = [string]$property.Value; break }
            }
            -not [string]::IsNullOrWhiteSpace($candidate) -and $candidate.Trim() -ieq $Name.Trim()
        })

    if ($matches.Count -eq 0) { throw "$ResourceName '$Name' was not found." }
    if ($matches.Count -gt 1) { throw "Multiple $ResourceName records matched '$Name'." }

    foreach ($propertyName in $KeyProperty) {
        $property = $matches[0].PSObject.Properties | Where-Object Name -ieq $propertyName | Select-Object -First 1
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            return [string]$property.Value
        }
    }
    $Message = "$ResourceName '$Name' did not contain a usable key."
    Write-S2Error `
        -Message $Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
    throw [System.InvalidOperationException]::new($Message) 
}

function Add-S2NBApiResource {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [string]$CommandName,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Values,
        [string[]]$RequiredElement = @(),
        [Parameter(Mandatory)] [string]$LogFile
    )
    Invoke-S2NBApiResourceCommand -Connection $Connection -CommandName $CommandName `
        -Values $Values -RequiredElement $RequiredElement -LogFile $LogFile
}

function Set-S2NBApiResource {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [string]$CommandName,
        [Parameter(Mandatory)] [string]$KeyElement,
        [Parameter(Mandatory)] [ValidateRange(1, [int]::MaxValue)] [int]$Key,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Values,
        [Parameter(Mandatory)] [string]$LogFile
    )
    $parameters = [ordered]@{ $KeyElement = $Key }
    foreach ($entry in $Values.GetEnumerator()) { $parameters[[string]$entry.Key] = $entry.Value }
    Invoke-S2NBApiResourceCommand -Connection $Connection -CommandName $CommandName `
        -Values $parameters -RequiredElement @($KeyElement) -LogFile $LogFile
}

function Remove-S2NBApiResource {
    [CmdletBinding()]
    [OutputType([xml])]
    param(
        [Parameter(Mandatory)] [psobject]$Connection,
        [Parameter(Mandatory)] [string]$CommandName,
        [Parameter(Mandatory)] [string]$KeyElement,
        [Parameter(Mandatory)] [ValidateRange(1, [int]::MaxValue)] [int]$Key,
        [Parameter(Mandatory)] [string]$LogFile
    )
    Invoke-S2NBApiResourceCommand -Connection $Connection -CommandName $CommandName `
        -Values ([ordered]@{ $KeyElement = $Key }) `
        -RequiredElement @($KeyElement) -LogFile $LogFile
}

function Get-S2CandidatePropertyValue {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$PropertyName
    )

    foreach ($candidate in $PropertyName) {
        $property = $InputObject.PSObject.Properties |
        Where-Object { $_.Name -ieq $candidate } |
        Select-Object -First 1

        if ($null -ne $property -and
            -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            return $property.Value
        }
    }

    return $null
}
#endregion Constants

#region Public Exports
Export-ModuleMember -Function @(
    'ConvertTo-S2NBApiParametersXml',
    'Invoke-S2NBApiResourceCommand',
    'ConvertFrom-S2NBApiXmlNode',
    'Get-S2NBApiResourceCollection',
    'Resolve-S2NBApiResourceKey',
    'Add-S2NBApiResource',
    'Set-S2NBApiResource',
    'Remove-S2NBApiResource',
    'Get-S2CandidatePropertyValue'
)
#endregion Public Exports