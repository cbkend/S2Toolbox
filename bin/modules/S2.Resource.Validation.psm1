<#
.SYNOPSIS
    Provides reusable post-action resource verification for S2 Toolbox.
.DESCRIPTION
    Compares expected resource state with a final resource collection after an
    Add, Modify, or Delete operation. The module is transport-neutral: callers
    retrieve final records through the appropriate S2 resource module and pass
    them to this module for deterministic comparison.
.NOTES
    FileName   : S2.Resource.Validation.psm1
    Application: S2 Toolbox
    Requires   : Windows PowerShell 5.1
    Version    : 1.0.0
#>
#requires -Version 5.1
Set-StrictMode -Version Latest

function Get-S2VerificationPropertyValue {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$PropertyName
    )

    if ($null -eq $InputObject) {
        return $null
    }

    foreach ($candidateName in $PropertyName) {
        $property = $InputObject.PSObject.Properties |
            Where-Object { $_.Name -ieq $candidateName } |
            Select-Object -First 1

        if ($null -ne $property) {
            return $property.Value
        }
    }

    return $null
}

function ConvertTo-S2VerificationText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$Value,

        [ValidateSet('Ordinal', 'OrdinalIgnoreCase', 'Trimmed', 'TrimmedIgnoreCase', 'Numeric', 'Boolean')]
        [string]$Comparison = 'Ordinal'
    )

    if ($null -eq $Value) {
        return ''
    }

    switch ($Comparison) {
        'Numeric' {
            $number = 0.0
            if ([double]::TryParse(
                    [string]$Value,
                    [System.Globalization.NumberStyles]::Any,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [ref]$number
                )) {
                return $number.ToString('R', [System.Globalization.CultureInfo]::InvariantCulture)
            }
            return ([string]$Value).Trim()
        }
        'Boolean' {
            $text = ([string]$Value).Trim()
            if ($text -match '^(?i:true|1|yes|y)$') { return 'true' }
            if ($text -match '^(?i:false|0|no|n)$') { return 'false' }
            return $text.ToLowerInvariant()
        }
        'Trimmed' { return ([string]$Value).Trim() }
        'TrimmedIgnoreCase' { return ([string]$Value).Trim().ToLowerInvariant() }
        'OrdinalIgnoreCase' { return ([string]$Value).ToLowerInvariant() }
        default { return [string]$Value }
    }
}

function Compare-S2VerificationValue {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()]
        [object]$Expected,

        [AllowNull()]
        [object]$Actual,

        [ValidateSet('Ordinal', 'OrdinalIgnoreCase', 'Trimmed', 'TrimmedIgnoreCase', 'Numeric', 'Boolean')]
        [string]$Comparison = 'Ordinal'
    )

    $expectedText = ConvertTo-S2VerificationText -Value $Expected -Comparison $Comparison
    $actualText = ConvertTo-S2VerificationText -Value $Actual -Comparison $Comparison

    [pscustomobject]@{
        PSTypeName = 'S2.ResourceVerificationValueComparison'
        Match      = ($expectedText -ceq $actualText)
        Expected   = $expectedText
        Actual     = $actualText
        Comparison = $Comparison
    }
}

function New-S2VerificationIndex {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowNull()]
        [object[]]$InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$PropertyName,

        [switch]$IgnoreCase
    )

    $index = @{}
    foreach ($record in @($InputObject)) {
        if ($null -eq $record) { continue }

        $value = [string](Get-S2VerificationPropertyValue `
            -InputObject $record `
            -PropertyName $PropertyName)

        if ([string]::IsNullOrWhiteSpace($value)) { continue }

        $key = $value.Trim()
        if ($IgnoreCase.IsPresent) {
            $key = $key.ToLowerInvariant()
        }

        if (-not $index.ContainsKey($key)) {
            $index[$key] = $record
        }
    }

    return $index
}

function Test-S2ResourceState {
    <#
    .SYNOPSIS
        Verifies final resource state after Add, Modify, or Delete operations.
    .PARAMETER VerificationPlan
        Expected records. Each plan may include RowNumber and caller-defined fields.
    .PARAMETER ActualRecord
        Final records retrieved after the action phase.
    .PARAMETER Operation
        Add and Modify require the expected resource to be present and matching.
        Delete requires the resource to be absent.
    .PARAMETER KeyMap
        Expected/actual key mapping. Example:
        @{ Expected = @('AccessLevelKey'); Actual = @('ACCESSLEVELKEY','KEY') }
    .PARAMETER NameMap
        Required fallback identity mapping. Names are matched case-insensitively.
    .PARAMETER ComparisonMap
        Array of dictionaries. Each dictionary supports Label, Expected, Actual,
        Comparison, and optional SkipWhenExpectedEmpty.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceName,

        [Parameter(Mandatory)]
        [ValidateSet('Add', 'Modify', 'Delete')]
        [string]$Operation,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object[]]$VerificationPlan,

        [AllowNull()]
        [object[]]$ActualRecord,

        [AllowNull()]
        [System.Collections.IDictionary]$KeyMap,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Collections.IDictionary]$NameMap,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Collections.IDictionary[]]$ComparisonMap,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$LogFile,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$FileName,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Source
    )

    if (-not $NameMap.Contains('Expected') -or -not $NameMap.Contains('Actual')) {
        throw [System.ArgumentException]::new(
            'NameMap must contain Expected and Actual property arrays.'
        )
    }

    $nameIndex = New-S2VerificationIndex `
        -InputObject @($ActualRecord) `
        -PropertyName @($NameMap.Actual) `
        -IgnoreCase

    $keyIndex = @{}
    if ($null -ne $KeyMap) {
        if (-not $KeyMap.Contains('Expected') -or -not $KeyMap.Contains('Actual')) {
            throw [System.ArgumentException]::new(
                'KeyMap must contain Expected and Actual property arrays.'
            )
        }
        $keyIndex = New-S2VerificationIndex `
            -InputObject @($ActualRecord) `
            -PropertyName @($KeyMap.Actual)
    }

    foreach ($plan in @($VerificationPlan)) {
        $errors = New-Object System.Collections.Generic.List[string]
        $matchedBy = ''
        $actual = $null

        $expectedKey = ''
        if ($null -ne $KeyMap) {
            $expectedKey = [string](Get-S2VerificationPropertyValue `
                -InputObject $plan `
                -PropertyName @($KeyMap.Expected))

            if (-not [string]::IsNullOrWhiteSpace($expectedKey)) {
                $normalizedKey = $expectedKey.Trim()
                if ($keyIndex.ContainsKey($normalizedKey)) {
                    $actual = $keyIndex[$normalizedKey]
                    $matchedBy = 'Key'
                }
            }
        }

        $expectedName = [string](Get-S2VerificationPropertyValue `
            -InputObject $plan `
            -PropertyName @($NameMap.Expected))

        if ($null -eq $actual -and -not [string]::IsNullOrWhiteSpace($expectedName)) {
            $normalizedName = $expectedName.Trim().ToLowerInvariant()
            if ($nameIndex.ContainsKey($normalizedName)) {
                $actual = $nameIndex[$normalizedName]
                $matchedBy = 'Name'
            }
        }

        if ($Operation -eq 'Delete') {
            if ($null -ne $actual) {
                [void]$errors.Add(
                    "The $ResourceName is still present after the delete operation."
                )
            }
        }
        elseif ($null -eq $actual) {
            [void]$errors.Add(
                "The $ResourceName was not present in the final resource results."
            )
        }
        else {
            foreach ($map in $ComparisonMap) {
                foreach ($requiredName in @('Label', 'Expected', 'Actual')) {
                    if (-not $map.Contains($requiredName)) {
                        throw [System.ArgumentException]::new(
                            "ComparisonMap entry is missing '$requiredName'."
                        )
                    }
                }

                $comparison = 'Ordinal'
                if ($map.Contains('Comparison') -and
                    -not [string]::IsNullOrWhiteSpace([string]$map.Comparison)) {
                    $comparison = [string]$map.Comparison
                }

                $expectedValue = Get-S2VerificationPropertyValue `
                    -InputObject $plan `
                    -PropertyName @($map.Expected)

                if ($map.Contains('SkipWhenExpectedEmpty') -and
                    [bool]$map.SkipWhenExpectedEmpty -and
                    [string]::IsNullOrWhiteSpace([string]$expectedValue)) {
                    continue
                }

                $actualValue = Get-S2VerificationPropertyValue `
                    -InputObject $actual `
                    -PropertyName @($map.Actual)

                $comparisonResult = Compare-S2VerificationValue `
                    -Expected $expectedValue `
                    -Actual $actualValue `
                    -Comparison $comparison

                if (-not $comparisonResult.Match) {
                    [void]$errors.Add(
                        "{0} mismatch. Expected '{1}'; actual '{2}'." -f `
                            [string]$map.Label,
                            $comparisonResult.Expected,
                            $comparisonResult.Actual
                    )
                }
            }
        }

        $verified = ($errors.Count -eq 0)
        $message = if ($verified) {
            if ($Operation -eq 'Delete') {
                "$ResourceName deletion verified through final resource retrieval."
            }
            else {
                "Final $ResourceName values match the expected values."
            }
        }
        else {
            $errors -join ' '
        }

        $rowNumber = Get-S2VerificationPropertyValue `
            -InputObject $plan `
            -PropertyName @('RowNumber')

        $actualKey = ''
        if ($null -ne $actual -and $null -ne $KeyMap) {
            $actualKey = [string](Get-S2VerificationPropertyValue `
                -InputObject $actual `
                -PropertyName @($KeyMap.Actual))
        }

        $verificationResult = [pscustomobject]@{
            PSTypeName          = 'S2.ResourceVerificationResult'
            Resource            = $ResourceName
            Operation           = $Operation
            RowNumber           = $rowNumber
            Name                = $expectedName
            ExpectedKey         = $expectedKey
            ActualKey           = $actualKey
            MatchedBy           = $matchedBy
            Verified            = $verified
            Status              = if ($verified) { 'Verified' } else { 'VerificationFailed' }
            Message             = $message
            VerificationMessage = $message
            Errors              = @($errors)
            Plan                = $plan
            ActualRecord        = $actual
        }

        $logCommand = Get-Command -Name Write-S2ItemLog -ErrorAction SilentlyContinue
        if ($null -ne $logCommand) {
            Write-S2ItemLog `
                -Level $(if ($verified) { 'Information' } else { 'Error' }) `
                -Action 'Verify' `
                -Name $expectedName `
                -Id $(if (-not [string]::IsNullOrWhiteSpace($actualKey)) { $actualKey } else { $expectedKey }) `
                -Detail $message `
                -LogFile $LogFile `
                -FileName $FileName `
                -Source $Source
        }

        $verificationResult
    }
}

function Merge-S2ResourceVerificationResult {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object[]]$ActionResult,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object[]]$VerificationResult
    )

    foreach ($verification in @($VerificationResult)) {
        $target = @($ActionResult) |
            Where-Object {
                $_.RowNumber -eq $verification.RowNumber -and
                $_.Name -ieq $verification.Name
            } |
            Select-Object -First 1

        if ($null -eq $target) { continue }

        foreach ($propertyName in @('Verified', 'VerificationMessage')) {
            if ($null -eq $target.PSObject.Properties[$propertyName]) {
                $target | Add-Member `
                    -MemberType NoteProperty `
                    -Name $propertyName `
                    -Value $null
            }
        }

        $target.Verified = [bool]$verification.Verified
        $target.VerificationMessage = [string]$verification.VerificationMessage
        $target.Message = [string]$verification.Message

        if (-not $verification.Verified) {
            $target.Status = 'Failed'
        }
    }

    return @($ActionResult)
}

function Get-S2ResourceVerificationSummary {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()]
        [object[]]$ActionResult,

        [AllowNull()]
        [object[]]$VerificationResult
    )

    $actions = @($ActionResult)
    $verifications = @($VerificationResult)

    [pscustomobject]@{
        PSTypeName         = 'S2.ResourceVerificationSummary'
        Created            = @($actions | Where-Object { $_.Status -eq 'Created' -and $_.Verified })
        Verified           = @($verifications | Where-Object Verified)
        VerificationFailed = @($verifications | Where-Object { -not $_.Verified })
        Previewed          = @($actions | Where-Object Status -eq 'Previewed')
        Skipped            = @($actions | Where-Object Status -eq 'Skipped')
        Failed             = @($actions | Where-Object Status -eq 'Failed')
        Success            = (@($actions | Where-Object Status -eq 'Failed').Count -eq 0)
    }
}

Export-ModuleMember -Function @(
    'Test-S2ResourceState',
    'Merge-S2ResourceVerificationResult',
    'Get-S2ResourceVerificationSummary'
)
