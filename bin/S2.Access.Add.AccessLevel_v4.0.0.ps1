<#
.SYNOPSIS
    Creates S2 NetBox Access Levels from a name-based CSV file.
.DESCRIPTION
    Validates CSV records, resolves Reader Group and Time Spec Group names through
    shared NBAPI resource modules, creates Access Levels through Add-S2AccessLevel,
    and verifies the final values through the shared resource-validation module.

    Expected CSV columns:
        Name,Description,ReaderGroup,TimeSpecGroup

    Optional CSV column:
        ThreatLevelGroup

    Required values:
        Name,ReaderGroup,TimeSpecGroup

    If ThreatLevelGroup is present, its value must remain blank until a verified
    NBAPI Threat Level Group retrieval and resolution module is available.
.NOTES
    FileName   : S2.Access.Add.AccessLevel_v4.0.0.ps1
    Application: S2 Toolbox
    Requires   : Windows PowerShell 5.1
#>

#requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [ValidateNotNullOrEmpty()]
    [string]$HostName,

    [ValidateNotNull()]
    [System.Management.Automation.PSCredential]$Credential,

    [ValidateNotNullOrEmpty()]
    [string]$CredentialPath,

    [ValidateSet('http', 'https')]
    [string]$Protocol = 'https',

    [ValidateNotNullOrEmpty()]
    [string]$InputFile = 'AccessLevelImport.csv',

    [ValidateNotNullOrEmpty()]
    [string]$LogFile = 'AddAccessLevel',

    [switch]$Preview,

    [switch]$Silent
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Script State

$script:NBApiConnection = $null
$script:ModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'modules'
$actionResults = New-Object System.Collections.Generic.List[object]
$verificationPlans = New-Object System.Collections.Generic.List[object]

#endregion Script State

#region Bootstrap

$bootstrapPath = Join-Path `
    -Path $script:ModulePath `
    -ChildPath 'S2.ToolboxBootStrap.psm1'

if (-not (Test-Path -LiteralPath $bootstrapPath -PathType Leaf)) {
    throw [System.IO.FileNotFoundException]::new(
        "Required bootstrap was not found: $bootstrapPath"
    )
}

. $bootstrapPath

if ($null -eq (
        Get-Command `
            -Name 'Assert-S2RequiredCommand' `
            -ErrorAction SilentlyContinue
    )) {

    throw [System.InvalidOperationException]::new(
        'The bootstrap did not load Assert-S2RequiredCommand.'
    )
}

Assert-S2RequiredCommand -Name @(
    'Write-S2Information',
    'Write-S2Warning',
    'Write-S2Error',
    'Write-S2Verbose',
    'Write-S2ItemLog',
    'Write-S2ScriptSummary',
    'Test-S2PathSafety',
    'Test-S2CsvFile',
    'Get-S2CsvSchemaValidation',
    'Test-S2CsvRequiredValues',
    'Test-S2DuplicateValues',
    'Test-S2StringLength',
    'Test-S2ImportRecord',
    'Import-S2CsvData',
    'New-S2ApiConnection',
    'Connect-S2NBApiSession',
    'Disconnect-S2NBApiSession',
    'Unprotect-S2Credential',
    'Clear-S2SensitiveData',
    'Get-S2NBApiCommand',
    'Resolve-S2NBApiResourceKey',
    'ConvertTo-S2NBApiParametersXml',
    'Get-S2AccessLevel',
    'Get-S2ReaderGroup',
    'Get-S2TimeSpecGroup',
    'Add-S2AccessLevel',
    'Get-S2CandidatePropertyValue',
    'Test-S2ResourceState',
    'Merge-S2ResourceVerificationResult',
    'Get-S2ResourceVerificationSummary',
    'Resolve-S2ImportPath',
    'New-S2ActionResult',
    'Write-S2ConsoleMessage',
    'Set-S2AccessLevelVerificationBatchFailure'
)

#endregion Bootstrap

#region Main Workflow

try {
    #region Initialization

    foreach ($commandName in @(
            'GetAccessLevel',
            'GetAccessLevels',
            'GetReaderGroups',
            'GetTimeSpecGroups',
            'AddAccessLevel'
        )) {

        Get-S2NBApiCommand `
            -Name $commandName `
            -LogFile $LogFile |
        Out-Null
    }

    if ([string]::IsNullOrWhiteSpace($HostName)) {
        $HostName = Read-Host 'Enter NetBox host name or IP address'
    }

    if ([string]::IsNullOrWhiteSpace($HostName)) {
        throw [System.InvalidOperationException]::new(
            'HostName is required.'
        )
    }

    if ($null -eq $Credential -and
        -not [string]::IsNullOrWhiteSpace($CredentialPath)) {

        $Credential = Unprotect-S2Credential `
            -Path $CredentialPath `
            -LogFile $LogFile
    }

    if ($null -eq $Credential) {
        $Credential = Get-Credential `
            -Message 'Enter your NetBox credentials'
    }

    if ($null -eq $Credential) {
        throw [System.InvalidOperationException]::new(
            'Credential is required.'
        )
    }

    $InputFile = Resolve-S2ImportPath `
        -Path $InputFile `
        -ScriptRoot $PSScriptRoot

    if (-not (Test-S2PathSafety -Path $InputFile -LogFile $LogFile)) {
        throw [System.InvalidOperationException]::new(
            "Input path is invalid or unsafe: $InputFile"
        )
    }

    if (-not (Test-S2CsvFile -Path $InputFile -LogFile $LogFile)) {
        throw [System.IO.FileNotFoundException]::new(
            "CSV input file was not found: $InputFile"
        )
    }

    Write-S2Information `
        -Message 'Add Access Level import started.' `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name

    #endregion Initialization

    #region NBAPI Authentication

    $script:NBApiConnection = New-S2ApiConnection `
        -HostName $HostName `
        -Protocol $Protocol `
        -LogFile $LogFile

    $script:NBApiConnection = Connect-S2NBApiSession `
        -Connection $script:NBApiConnection `
        -Credential $Credential `
        -LogFile $LogFile

    #endregion NBAPI Authentication

    #region CSV Import And Validation

    $accessLevelImportRecords = @(
        Import-S2CsvData `
            -Path $InputFile `
            -LogFile $LogFile
    )

    if ($accessLevelImportRecords.Count -eq 0) {
        throw [System.InvalidOperationException]::new(
            "No Access Level records were found in '$InputFile'."
        )
    }

    $requiredColumns = @(
        'Name',
        'Description',
        'ReaderGroup',
        'TimeSpecGroup'
    )

    $csvSchemaValidation = Get-S2CsvSchemaValidation `
        -Data $accessLevelImportRecords `
        -RequiredColumns $requiredColumns `
        -LogFile $LogFile

    if (-not $csvSchemaValidation.Valid) {
        $missingColumns = @(
            $requiredColumns | Where-Object {
                $_ -notin $csvSchemaValidation.ExistingColumns
            }
        )

        throw [System.InvalidOperationException]::new(
            'CSV is missing required columns: {0}' -f
            ($missingColumns -join ', ')
        )
    }

    $requiredValueErrors = @(
        Test-S2CsvRequiredValues `
            -Data $accessLevelImportRecords `
            -RequiredColumns @(
            'Name',
            'ReaderGroup',
            'TimeSpecGroup'
        ) `
            -LogFile $LogFile
    )

    if ($requiredValueErrors.Count -gt 0) {
        Write-S2Warning `
            -Message (
            'CSV contains {0} missing required value(s).' -f
            $requiredValueErrors.Count
        ) `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
    }

    $duplicateNames = @(
        Test-S2DuplicateValues `
            -Data $accessLevelImportRecords `
            -Column 'Name' `
            -LogFile $LogFile
    )

    if ($duplicateNames.Count -gt 0) {
        Write-S2Warning `
            -Message (
            'CSV contains duplicate Access Level names. ' +
            'Later rows are skipped.'
        ) `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
    }

    #endregion CSV Import And Validation

    #region NBAPI Lookup Caching

    $readerGroups = @(
        Get-S2ReaderGroup `
            -Connection $script:NBApiConnection `
            -LogFile $LogFile
    )

    $timeSpecGroups = @(
        Get-S2TimeSpecGroup `
            -Connection $script:NBApiConnection `
            -LogFile $LogFile
    )

    $accessLevels = @(
        Get-S2AccessLevel `
            -Connection $script:NBApiConnection `
            -LogFile $LogFile
    )

    if ($readerGroups.Count -eq 0) {
        throw [System.InvalidOperationException]::new(
            'No Reader Groups were returned by NBAPI.'
        )
    }

    if ($timeSpecGroups.Count -eq 0) {
        throw [System.InvalidOperationException]::new(
            'No Time Spec Groups were returned by NBAPI.'
        )
    }

    $existingAccessLevelNames = New-Object `
        'System.Collections.Generic.HashSet[string]' `
    ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($accessLevel in $accessLevels) {
        $existingAccessLevelName = [string](
            Get-S2CandidatePropertyValue `
                -InputObject $accessLevel `
                -PropertyName @(
                'ACCESSLEVELNAME',
                'NAME'
            )
        )

        if (-not [string]::IsNullOrWhiteSpace($existingAccessLevelName)) {
            [void]$existingAccessLevelNames.Add(
                $existingAccessLevelName.Trim()
            )
        }
    }

    $processedAccessLevelNames = New-Object `
        'System.Collections.Generic.HashSet[string]' `
    ([System.StringComparer]::OrdinalIgnoreCase)

    #endregion NBAPI Lookup Caching

    #region Record Processing

    for (
        $recordIndex = 0;
        $recordIndex -lt $accessLevelImportRecords.Count;
        $recordIndex++
    ) {
        $accessLevelImportRecord = $accessLevelImportRecords[$recordIndex]
        $rowNumber = $recordIndex + 2
        $accessLevelName = ([string]$accessLevelImportRecord.Name).Trim()

        try {
            #region Record Validation

            $validationErrors =
            New-Object System.Collections.Generic.List[string]

            $recordValidation = Test-S2ImportRecord `
                -Record $accessLevelImportRecord `
                -RequiredFields @(
                'Name',
                'ReaderGroup',
                'TimeSpecGroup'
            ) `
                -LogFile $LogFile

            foreach ($recordError in @($recordValidation.Errors)) {
                [void]$validationErrors.Add([string]$recordError)
            }

            if (-not [string]::IsNullOrWhiteSpace($accessLevelName) -and
                -not (Test-S2StringLength `
                        -Value $accessLevelName `
                        -MinimumLength 1 `
                        -MaximumLength 64 `
                        -LogFile $LogFile)) {

                [void]$validationErrors.Add(
                    'Name must contain between 1 and 64 characters.'
                )
            }

            $threatLevelGroup = ''

            if ($null -ne (
                    $accessLevelImportRecord.PSObject.Properties[
                    'ThreatLevelGroup'
                    ]
                )) {

                $threatLevelGroup = (
                    [string]$accessLevelImportRecord.ThreatLevelGroup
                ).Trim()
            }

            if (-not [string]::IsNullOrWhiteSpace($threatLevelGroup)) {
                [void]$validationErrors.Add(
                    'ThreatLevelGroup must remain blank until a verified ' +
                    'NBAPI resolver is available.'
                )
            }

            if ($validationErrors.Count -gt 0) {
                $validationMessage = $validationErrors -join ' '

                [void]$actionResults.Add(
                    (New-S2ActionResult `
                        -RowNumber $rowNumber `
                        -Name $accessLevelName `
                        -Status Failed `
                        -Message $validationMessage)
                )

                Write-S2ItemLog `
                    -Level Error `
                    -Action 'Validate' `
                    -Name $accessLevelName `
                    -Id ([string]$rowNumber) `
                    -Detail $validationMessage `
                    -LogFile $LogFile `
                    -FileName $PSCommandPath `
                    -Source $MyInvocation.MyCommand.Name

                continue
            }

            if (-not $processedAccessLevelNames.Add($accessLevelName)) {
                $skipMessage =
                'Duplicate Name in CSV. A previous row already used this value.'

                [void]$actionResults.Add(
                    (New-S2ActionResult `
                        -RowNumber $rowNumber `
                        -Name $accessLevelName `
                        -Status Skipped `
                        -Message $skipMessage)
                )

                Write-S2ItemLog `
                    -Level Warning `
                    -Action 'Skip' `
                    -Name $accessLevelName `
                    -Id ([string]$rowNumber) `
                    -Detail $skipMessage `
                    -LogFile $LogFile `
                    -FileName $PSCommandPath `
                    -Source $MyInvocation.MyCommand.Name

                continue
            }

            if ($existingAccessLevelNames.Contains($accessLevelName)) {
                $skipMessage =
                'An Access Level with this name already exists in NetBox.'

                [void]$actionResults.Add(
                    (New-S2ActionResult `
                        -RowNumber $rowNumber `
                        -Name $accessLevelName `
                        -Status Skipped `
                        -Message $skipMessage)
                )

                Write-S2ItemLog `
                    -Level Warning `
                    -Action 'Skip' `
                    -Name $accessLevelName `
                    -Id ([string]$rowNumber) `
                    -Detail $skipMessage `
                    -LogFile $LogFile `
                    -FileName $PSCommandPath `
                    -Source $MyInvocation.MyCommand.Name

                continue
            }

            $readerGroupKey = Resolve-S2NBApiResourceKey `
                -InputObject $readerGroups `
                -Name ([string]$accessLevelImportRecord.ReaderGroup) `
                -NameProperty @('NAME') `
                -KeyProperty @('READERGROUPKEY') `
                -ResourceName 'Reader Group' `
                -LogFile $LogFile

            $timeSpecGroupKey = Resolve-S2NBApiResourceKey `
                -InputObject $timeSpecGroups `
                -Name ([string]$accessLevelImportRecord.TimeSpecGroup) `
                -NameProperty @('NAME') `
                -KeyProperty @('TIMESPECGROUPKEY') `
                -ResourceName 'Time Spec Group' `
                -LogFile $LogFile

            $description = ([string]$accessLevelImportRecord.Description).Trim()

            $accessLevelValues = [ordered]@{
                ACCESSLEVELNAME        = $accessLevelName
                ACCESSLEVELDESCRIPTION = $description
                READERGROUPKEY         = $readerGroupKey
                TIMESPECGROUPKEY       = $timeSpecGroupKey
            }

            $null = ConvertTo-S2NBApiParametersXml `
                -Values $accessLevelValues `
                -RequiredElement @(
                'ACCESSLEVELNAME',
                'READERGROUPKEY',
                'TIMESPECGROUPKEY'
            ) `
                -OmitEmpty

            #endregion Record Validation

            #region Preview And Submission

            if ($Preview.IsPresent -or $WhatIfPreference) {
                $previewMessage =
                'NBAPI resource values validated; command not submitted.'

                [void]$actionResults.Add(
                    (New-S2ActionResult `
                        -RowNumber $rowNumber `
                        -Name $accessLevelName `
                        -Status Previewed `
                        -Message $previewMessage)
                )

                Write-S2ItemLog `
                    -Level Information `
                    -Action 'Preview' `
                    -Name $accessLevelName `
                    -Id ([string]$rowNumber) `
                    -Detail $previewMessage `
                    -LogFile $LogFile `
                    -FileName $PSCommandPath `
                    -Source $MyInvocation.MyCommand.Name

                continue
            }

            if (-not $PSCmdlet.ShouldProcess(
                    $accessLevelName,
                    'Create S2 Access Level'
                )) {

                $skipMessage =
                'Access Level creation was declined through ShouldProcess.'

                [void]$actionResults.Add(
                    (New-S2ActionResult `
                        -RowNumber $rowNumber `
                        -Name $accessLevelName `
                        -Status Skipped `
                        -Message $skipMessage)
                )

                Write-S2ItemLog `
                    -Level Warning `
                    -Action 'Skip' `
                    -Name $accessLevelName `
                    -Id ([string]$rowNumber) `
                    -Detail $skipMessage `
                    -LogFile $LogFile `
                    -FileName $PSCommandPath `
                    -Source $MyInvocation.MyCommand.Name

                continue
            }

            [xml]$addResponse = Add-S2AccessLevel `
                -Connection $script:NBApiConnection `
                -Values $accessLevelValues `
                -RequiredElement @(
                'ACCESSLEVELNAME',
                'READERGROUPKEY',
                'TIMESPECGROUPKEY'
            ) `
                -LogFile $LogFile

            $accessLevelKey =
            [string]$addResponse.NETBOX.RESPONSE.DETAILS.ACCESSLEVELKEY

            if ([string]::IsNullOrWhiteSpace($accessLevelKey)) {
                throw [System.InvalidOperationException]::new(
                    'AddAccessLevel completed without returning an ' +
                    'Access Level key.'
                )
            }

            $parsedAccessLevelKey = 0

            if (-not [int]::TryParse(
                    $accessLevelKey,
                    [ref]$parsedAccessLevelKey
                ) -or
                $parsedAccessLevelKey -le 0) {

                throw [System.InvalidOperationException]::new(
                    "AddAccessLevel returned an invalid Access Level key: " +
                    "'$accessLevelKey'."
                )
            }

            [void]$existingAccessLevelNames.Add($accessLevelName)

            [void]$actionResults.Add(
                (New-S2ActionResult `
                    -RowNumber $rowNumber `
                    -Name $accessLevelName `
                    -AccessLevelKey $accessLevelKey `
                    -Status Created `
                    -Message 'Access Level creation submitted.')
            )

            [void]$verificationPlans.Add(
                [pscustomobject]@{
                    RowNumber        = $rowNumber
                    Name             = $accessLevelName
                    AccessLevelKey   = $accessLevelKey
                    Description      = $description
                    ReaderGroupKey   = [string]$readerGroupKey
                    TimeSpecGroupKey = [string]$timeSpecGroupKey
                }
            )

            Write-S2ItemLog `
                -Level Information `
                -Action 'Create' `
                -Name $accessLevelName `
                -Id $accessLevelKey `
                -Detail 'Access Level creation submitted.' `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name

            #endregion Preview And Submission
        }
        catch {
            $resultRecord = $actionResults |
            Where-Object {
                $_.RowNumber -eq $rowNumber
            } |
            Select-Object -First 1

            if ($null -ne $resultRecord) {
                $resultRecord.Status = 'Failed'
                $resultRecord.Verified = $false
                $resultRecord.Message = $_.Exception.Message
                $resultRecord.VerificationMessage = ''
            }
            else {
                [void]$actionResults.Add(
                    (New-S2ActionResult `
                        -RowNumber $rowNumber `
                        -Name $accessLevelName `
                        -Status Failed `
                        -Message $_.Exception.Message)
                )
            }

            Write-S2ItemLog `
                -Level Error `
                -Action 'Create' `
                -Name $accessLevelName `
                -Id ([string]$rowNumber) `
                -Detail $_.Exception.Message `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name
        }
    }

    #endregion Record Processing

    #region Post-Add Verification

    $verificationResults = @()

    if (-not $Preview.IsPresent -and
        -not $WhatIfPreference -and
        $verificationPlans.Count -gt 0) {

        try {
            $finalAccessLevels = @(
                Get-S2AccessLevel `
                    -Connection $script:NBApiConnection `
                    -LogFile $LogFile
            )

            $comparisonMap = @(
                @{
                    Label                 = 'AccessLevelKey'
                    Expected              = @('AccessLevelKey')
                    Actual                = @('ACCESSLEVELKEY', 'KEY')
                    Comparison            = 'Trimmed'
                    SkipWhenExpectedEmpty = $true
                }
                @{
                    Label      = 'Name'
                    Expected   = @('Name')
                    Actual     = @('ACCESSLEVELNAME', 'NAME')
                    Comparison = 'TrimmedIgnoreCase'
                }
                @{
                    Label      = 'Description'
                    Expected   = @('Description')
                    Actual     = @(
                        'ACCESSLEVELDESCRIPTION',
                        'DESCRIPTION'
                    )
                    Comparison = 'Trimmed'
                }
                @{
                    Label      = 'ReaderGroupKey'
                    Expected   = @('ReaderGroupKey')
                    Actual     = @('READERGROUPKEY')
                    Comparison = 'Trimmed'
                }
                @{
                    Label      = 'TimeSpecGroupKey'
                    Expected   = @('TimeSpecGroupKey')
                    Actual     = @('TIMESPECGROUPKEY')
                    Comparison = 'Trimmed'
                }
            )

            $verificationResults = @(
                Test-S2ResourceState `
                    -ResourceName 'AccessLevel' `
                    -Operation Add `
                    -VerificationPlan @($verificationPlans) `
                    -ActualRecord $finalAccessLevels `
                    -KeyMap @{
                    Expected = @('AccessLevelKey')
                    Actual   = @('ACCESSLEVELKEY', 'KEY')
                } `
                    -NameMap @{
                    Expected = @('Name')
                    Actual   = @('ACCESSLEVELNAME', 'NAME')
                } `
                    -ComparisonMap $comparisonMap `
                    -LogFile $LogFile `
                    -FileName $PSCommandPath `
                    -Source $MyInvocation.MyCommand.Name
            )

            $mergedResults = @(
                Merge-S2ResourceVerificationResult `
                    -ActionResult @($actionResults) `
                    -VerificationResult $verificationResults
            )

            $actionResults =
            New-Object System.Collections.Generic.List[object]

            foreach ($mergedResult in $mergedResults) {
                [void]$actionResults.Add($mergedResult)
            }
        }
        catch {
            $verificationFailure = (
                'Post-import Access Level verification failed: {0}' -f
                $_.Exception.Message
            )

            Write-S2Error `
                -Message $verificationFailure `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name

            $verificationResults = @(
                Set-S2AccessLevelVerificationBatchFailure `
                    -ActionResult @($actionResults) `
                    -VerificationPlan @($verificationPlans) `
                    -Operation Add `
                    -Message $verificationFailure
            )
        }
    }

    #endregion Post-Add Verification

    #region Summary

    $verificationSummary = Get-S2ResourceVerificationSummary `
        -ActionResult @($actionResults) `
        -VerificationResult @($verificationResults)

    $summaryText = (
        'Imported={0}; CreatedAndVerified={1}; VerificationFailed={2}; ' +
        'Previewed={3}; Skipped={4}; Failed={5}'
    ) -f @(
        $accessLevelImportRecords.Count,
        @($verificationSummary.Created).Count,
        @($verificationSummary.VerificationFailed).Count,
        @($verificationSummary.Previewed).Count,
        @($verificationSummary.Skipped).Count,
        @($verificationSummary.Failed).Count
    )

    Write-S2Information `
        -Message "Add Access Level import completed. $summaryText" `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name

    $null = Write-S2ScriptSummary `
        -Resource 'AccessLevel' `
        -CsvPath $InputFile `
        -RowCount $accessLevelImportRecords.Count `
        -PlanCount $verificationPlans.Count `
        -Created $verificationSummary.Created `
        -Verified $verificationSummary.Verified `
        -VerificationFailed $verificationSummary.VerificationFailed `
        -Skipped $verificationSummary.Skipped `
        -Previewed $verificationSummary.Previewed `
        -Failed $verificationSummary.Failed `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name `
        -PassThru

    Write-S2ConsoleMessage `
        -Message $summaryText `
        -Silent:$Silent

    $actionResults

    #endregion Summary
}
catch {
    #region Fatal Error Handling

    $fatalErrorMessage = (
        'Add Access Level import terminated: {0}' -f
        $_.Exception.Message
    )

    if ($null -eq $_.Exception.Data -or
        -not $_.Exception.Data.Contains('S2Logged')) {

        Write-S2Error `
            -Message $fatalErrorMessage `
            -LogFile $LogFile `
            -FileName $PSCommandPath `
            -Source $MyInvocation.MyCommand.Name
    }

    Write-S2ConsoleMessage `
        -Message $fatalErrorMessage `
        -Level Error `
        -Silent:$Silent

    throw

    #endregion Fatal Error Handling
}
finally {
    #region Cleanup

    if ($null -ne $script:NBApiConnection -and
        $null -ne $script:NBApiConnection.PSObject.Properties['SessionId'] -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$script:NBApiConnection.SessionId
        )) {

        try {
            Disconnect-S2NBApiSession `
                -Connection $script:NBApiConnection `
                -LogFile $LogFile
        }
        catch {
            Write-S2Warning `
                -Message (
                'NBAPI logout failed during cleanup: {0}' -f
                $_.Exception.Message
            ) `
                -LogFile $LogFile `
                -FileName $PSCommandPath `
                -Source $MyInvocation.MyCommand.Name
        }
    }

    if ($null -ne (
            Get-Command `
                -Name Clear-S2SensitiveData `
                -ErrorAction SilentlyContinue
        )) {

        Clear-S2SensitiveData `
            -Value ([ref]$Credential) `
            -LogFile $LogFile
    }
    else {
        $Credential = $null
    }

    $script:NBApiConnection = $null

    #endregion Cleanup
}

#endregion Main Workflow
