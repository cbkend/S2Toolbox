<#
.SYNOPSIS
    Modifies S2 NetBox Access Levels from a name-based CSV file.
.DESCRIPTION
    Resolves the existing Access Level and referenced resource keys through shared
    modules, submits changes through Set-S2AccessLevel, and verifies the final
    values through Test-S2ResourceState.

    Expected CSV columns:
        Name,NewName,Description,ReaderGroup,TimeSpecGroup,ThreatLevelGroup

    Required values:
        Name,NewName,ReaderGroup,TimeSpecGroup
.NOTES
    FileName   : S2.Access.Modify.AccessLevel_v1.0.0.ps1
    Application: S2 Toolbox
    Requires   : Windows PowerShell 5.1
#>
#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [ValidateNotNullOrEmpty()][string]$HostName,
    [ValidateNotNull()][System.Management.Automation.PSCredential]$Credential,
    [ValidateNotNullOrEmpty()][string]$CredentialPath,
    [ValidateSet('http', 'https')][string]$Protocol = 'https',
    [ValidateNotNullOrEmpty()][string]$InputFile = 'AccessLevelModify.csv',
    [ValidateNotNullOrEmpty()][string]$LogFile = 'ModifyAccessLevel',
    [switch]$Preview,
    [switch]$Silent
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:NBApiConnection = $null
$script:ModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'modules'
$actionResults = New-Object System.Collections.Generic.List[object]
$verificationPlans = New-Object System.Collections.Generic.List[object]

$bootstrapPath = Join-Path -Path $script:ModulePath -ChildPath 'S2.ToolboxBootStrap.psm1'
$commonModulePath = Join-Path -Path $script:ModulePath -ChildPath 'S2.AccessLevel.Import.Common.psm1'
if (-not (Test-Path -LiteralPath $bootstrapPath -PathType Leaf)) { throw [System.IO.FileNotFoundException]::new("Required bootstrap was not found: $bootstrapPath") }
if (-not (Test-Path -LiteralPath $commonModulePath -PathType Leaf)) { throw [System.IO.FileNotFoundException]::new("Required Access Level common module was not found: $commonModulePath") }
. $bootstrapPath
Import-Module -Name $commonModulePath -Force -ErrorAction Stop
Assert-S2RequiredCommand -Name @(
    'Write-S2Information', 'Write-S2Warning', 'Write-S2Error', 'Write-S2Verbose', 'Write-S2ItemLog', 'Write-S2ScriptSummary',
    'Test-S2PathSafety', 'Test-S2CsvFile', 'Get-S2CsvSchemaValidation', 'Test-S2CsvRequiredValues', 'Test-S2DuplicateValues', 'Test-S2StringLength', 'Test-S2ImportRecord', 'Import-S2CsvData',
    'New-S2ApiConnection', 'Connect-S2NBApiSession', 'Disconnect-S2NBApiSession', 'Unprotect-S2Credential', 'Clear-S2SensitiveData', 'Get-S2NBApiCommand',
    'Resolve-S2NBApiResourceKey', 'ConvertTo-S2NBApiParametersXml', 'Get-S2AccessLevel', 'Get-S2ReaderGroup', 'Get-S2TimeSpecGroup', 'Set-S2AccessLevel', 'Get-S2CandidatePropertyValue',
    'Test-S2ResourceState', 'Merge-S2ResourceVerificationResult', 'Get-S2ResourceVerificationSummary'
)

try {
    foreach ($commandName in @('GetAccessLevel', 'GetAccessLevels', 'GetReaderGroups', 'GetTimeSpecGroups', 'ModifyAccessLevel')) { Get-S2NBApiCommand -Name $commandName -LogFile $LogFile | Out-Null }
    if ([string]::IsNullOrWhiteSpace($HostName)) { $HostName = Read-Host 'Enter NetBox host name or IP address' }
    if ([string]::IsNullOrWhiteSpace($HostName)) { throw 'HostName is required.' }
    if ($null -eq $Credential -and -not [string]::IsNullOrWhiteSpace($CredentialPath)) { $Credential = Unprotect-S2Credential -Path $CredentialPath -LogFile $LogFile }
    if ($null -eq $Credential) { $Credential = Get-Credential -Message 'Enter your NetBox credentials' }
    if ($null -eq $Credential) { throw 'Credential is required.' }
    $InputFile = Resolve-S2ImportPath -Path $InputFile -ScriptRoot $PSScriptRoot
    if (-not (Test-S2PathSafety -Path $InputFile -LogFile $LogFile)) { throw "Input path is invalid or unsafe: $InputFile" }
    if (-not (Test-S2CsvFile -Path $InputFile -LogFile $LogFile)) { throw "CSV input file was not found: $InputFile" }
    Write-S2Information -Message 'Modify Access Level import started.' -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name

    $script:NBApiConnection = New-S2ApiConnection -HostName $HostName -Protocol $Protocol -LogFile $LogFile
    $script:NBApiConnection = Connect-S2NBApiSession -Connection $script:NBApiConnection -Credential $Credential -LogFile $LogFile
    $accessLevelModifyRecords = @(Import-S2CsvData -Path $InputFile -LogFile $LogFile)
    if ($accessLevelModifyRecords.Count -eq 0) { throw "No Access Level records were found in '$InputFile'." }
    $requiredColumns = @('Name', 'NewName', 'Description', 'ReaderGroup', 'TimeSpecGroup', 'ThreatLevelGroup')
    $csvSchemaValidation = Get-S2CsvSchemaValidation -Data $accessLevelModifyRecords -RequiredColumns $requiredColumns -LogFile $LogFile
    if (-not $csvSchemaValidation.Valid) { $missingColumns = @($requiredColumns | Where-Object { $_ -notin $csvSchemaValidation.ExistingColumns }); throw 'CSV is missing required columns: {0}' -f ($missingColumns -join ', ') }
    $requiredValueErrors = @(Test-S2CsvRequiredValues -Data $accessLevelModifyRecords -RequiredColumns @('Name', 'NewName', 'ReaderGroup', 'TimeSpecGroup') -LogFile $LogFile)
    if ($requiredValueErrors.Count -gt 0) { Write-S2Warning -Message "CSV contains $($requiredValueErrors.Count) missing required value(s)." -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name }
    $duplicateSourceNames = @(Test-S2DuplicateValues -Data $accessLevelModifyRecords -Column 'Name' -LogFile $LogFile)
    $duplicateTargetNames = @(Test-S2DuplicateValues -Data $accessLevelModifyRecords -Column 'NewName' -LogFile $LogFile)
    if ($duplicateSourceNames.Count -gt 0 -or $duplicateTargetNames.Count -gt 0) { Write-S2Warning -Message 'CSV contains duplicate source or target Access Level names. Later records are skipped or failed.' -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name }

    $accessLevels = @(Get-S2AccessLevel -Connection $script:NBApiConnection -LogFile $LogFile)
    $readerGroups = @(Get-S2ReaderGroup -Connection $script:NBApiConnection -LogFile $LogFile)
    $timeSpecGroups = @(Get-S2TimeSpecGroup -Connection $script:NBApiConnection -LogFile $LogFile)
    if ($accessLevels.Count -eq 0) { throw 'No Access Levels were returned by NBAPI.' }
    if ($readerGroups.Count -eq 0) { throw 'No Reader Groups were returned by NBAPI.' }
    if ($timeSpecGroups.Count -eq 0) { throw 'No Time Spec Groups were returned by NBAPI.' }
    $processedSourceNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $existingAccessLevelNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($accessLevel in $accessLevels) { $existingName = [string](Get-S2CandidatePropertyValue -InputObject $accessLevel -PropertyName @('ACCESSLEVELNAME', 'NAME')); if (-not [string]::IsNullOrWhiteSpace($existingName)) { [void]$existingAccessLevelNames.Add($existingName.Trim()) } }

    for ($recordIndex = 0; $recordIndex -lt $accessLevelModifyRecords.Count; $recordIndex++) {
        $accessLevelModifyRecord = $accessLevelModifyRecords[$recordIndex]
        $rowNumber = $recordIndex + 2
        $sourceAccessLevelName = ([string]$accessLevelModifyRecord.Name).Trim()
        $targetAccessLevelName = ([string]$accessLevelModifyRecord.NewName).Trim()
        try {
            $validationErrors = New-Object System.Collections.Generic.List[string]
            $recordValidation = Test-S2ImportRecord -Record $accessLevelModifyRecord -RequiredFields @('Name', 'NewName', 'ReaderGroup', 'TimeSpecGroup') -LogFile $LogFile
            foreach ($recordError in @($recordValidation.Errors)) { [void]$validationErrors.Add([string]$recordError) }
            if (-not [string]::IsNullOrWhiteSpace($sourceAccessLevelName) -and -not (Test-S2StringLength -Value $sourceAccessLevelName -MinimumLength 1 -MaximumLength 64 -LogFile $LogFile)) { [void]$validationErrors.Add('Name must contain between 1 and 64 characters.') }
            if (-not [string]::IsNullOrWhiteSpace($targetAccessLevelName) -and -not (Test-S2StringLength -Value $targetAccessLevelName -MinimumLength 1 -MaximumLength 64 -LogFile $LogFile)) { [void]$validationErrors.Add('NewName must contain between 1 and 64 characters.') }
            if (-not [string]::IsNullOrWhiteSpace([string]$accessLevelModifyRecord.ThreatLevelGroup)) { [void]$validationErrors.Add('ThreatLevelGroup must remain blank until a verified NBAPI resolver is available.') }
            if ($validationErrors.Count -gt 0) { $validationMessage = $validationErrors -join ' '; [void]$actionResults.Add((New-S2ActionResult -RowNumber $rowNumber -Name $sourceAccessLevelName -Status Failed -Message $validationMessage)); Write-S2ItemLog -Level Error -Action 'Validate' -Name $sourceAccessLevelName -Id ([string]$rowNumber) -Detail $validationMessage -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name; continue }
            if (-not $processedSourceNames.Add($sourceAccessLevelName)) { $skipMessage = 'Duplicate source Name in CSV.'; [void]$actionResults.Add((New-S2ActionResult -RowNumber $rowNumber -Name $sourceAccessLevelName -Status Skipped -Message $skipMessage)); Write-S2ItemLog -Level Warning -Action 'Skip' -Name $sourceAccessLevelName -Id ([string]$rowNumber) -Detail $skipMessage -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name; continue }

            $accessLevelKey = Resolve-S2NBApiResourceKey -InputObject $accessLevels -Name $sourceAccessLevelName -NameProperty @('ACCESSLEVELNAME', 'NAME') -KeyProperty @('ACCESSLEVELKEY', 'KEY') -ResourceName 'Access Level' -LogFile $LogFile
            if ($targetAccessLevelName -ine $sourceAccessLevelName -and $existingAccessLevelNames.Contains($targetAccessLevelName)) { throw "Another Access Level already uses NewName '$targetAccessLevelName'." }
            $readerGroupKey = Resolve-S2NBApiResourceKey -InputObject $readerGroups -Name ([string]$accessLevelModifyRecord.ReaderGroup) -NameProperty @('NAME') -KeyProperty @('READERGROUPKEY') -ResourceName 'Reader Group' -LogFile $LogFile
            $timeSpecGroupKey = Resolve-S2NBApiResourceKey -InputObject $timeSpecGroups -Name ([string]$accessLevelModifyRecord.TimeSpecGroup) -NameProperty @('NAME') -KeyProperty @('TIMESPECGROUPKEY') -ResourceName 'Time Spec Group' -LogFile $LogFile
            $description = ([string]$accessLevelModifyRecord.Description).Trim()
            $accessLevelValues = [ordered]@{ACCESSLEVELNAME = $targetAccessLevelName; ACCESSLEVELDESCRIPTION = $description; READERGROUPKEY = $readerGroupKey; TIMESPECGROUPKEY = $timeSpecGroupKey }
            $null = ConvertTo-S2NBApiParametersXml -Values $accessLevelValues -RequiredElement @('ACCESSLEVELNAME', 'READERGROUPKEY', 'TIMESPECGROUPKEY') -OmitEmpty

            if ($Preview.IsPresent -or $WhatIfPreference) { $previewMessage = 'NBAPI resource values validated; modification not submitted.'; [void]$actionResults.Add((New-S2ActionResult -RowNumber $rowNumber -Name $targetAccessLevelName -AccessLevelKey $accessLevelKey -Status Previewed -Message $previewMessage)); Write-S2ItemLog -Level Information -Action 'Preview' -Name $targetAccessLevelName -Id $accessLevelKey -Detail $previewMessage -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name; continue }
            if (-not $PSCmdlet.ShouldProcess($sourceAccessLevelName, "Modify S2 Access Level to '$targetAccessLevelName'")) { $skipMessage = 'Access Level modification was declined through ShouldProcess.'; [void]$actionResults.Add((New-S2ActionResult -RowNumber $rowNumber -Name $sourceAccessLevelName -AccessLevelKey $accessLevelKey -Status Skipped -Message $skipMessage)); Write-S2ItemLog -Level Warning -Action 'Skip' -Name $sourceAccessLevelName -Id $accessLevelKey -Detail $skipMessage -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name; continue }

            $null = Set-S2AccessLevel -Connection $script:NBApiConnection -Key ([int]$accessLevelKey) -Values $accessLevelValues -LogFile $LogFile
            [void]$actionResults.Add((New-S2ActionResult -RowNumber $rowNumber -Name $targetAccessLevelName -AccessLevelKey $accessLevelKey -Status Modified -Message 'Access Level modification submitted.'))
            [void]$verificationPlans.Add([pscustomobject]@{RowNumber = $rowNumber; Name = $targetAccessLevelName; AccessLevelKey = [string]$accessLevelKey; Description = $description; ReaderGroupKey = [string]$readerGroupKey; TimeSpecGroupKey = [string]$timeSpecGroupKey })
            [void]$existingAccessLevelNames.Remove($sourceAccessLevelName); [void]$existingAccessLevelNames.Add($targetAccessLevelName)
            Write-S2ItemLog -Level Information -Action 'Modify' -Name $targetAccessLevelName -Id $accessLevelKey -Detail 'Access Level modification submitted.' -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name
        }
        catch {
            $existingResult = $actionResults | Where-Object { $_.RowNumber -eq $rowNumber } | Select-Object -First 1
            if ($null -ne $existingResult) { $previousStatus = $existingResult.Status; $existingResult.Status = 'Failed'; $existingResult.Verified = $false; $existingResult.VerificationMessage = ''; $existingResult.Message = if ($previousStatus -eq 'Modified') { 'Post-modification processing failed: {0}' -f $_.Exception.Message }else { $_.Exception.Message } }
            else { [void]$actionResults.Add((New-S2ActionResult -RowNumber $rowNumber -Name $sourceAccessLevelName -Status Failed -Message $_.Exception.Message)) }
            Write-S2ItemLog -Level Error -Action 'Modify' -Name $sourceAccessLevelName -Id ([string]$rowNumber) -Detail $_.Exception.Message -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name
        }
    }

    $verificationResults = @()
    if (-not $Preview.IsPresent -and -not $WhatIfPreference -and $verificationPlans.Count -gt 0) {
        try {
            $finalAccessLevels = @(Get-S2AccessLevel -Connection $script:NBApiConnection -LogFile $LogFile)
            $comparisonMap = @(
                @{Label = 'AccessLevelKey'; Expected = @('AccessLevelKey'); Actual = @('ACCESSLEVELKEY', 'KEY'); Comparison = 'Trimmed' },
                @{Label = 'Name'; Expected = @('Name'); Actual = @('ACCESSLEVELNAME', 'NAME'); Comparison = 'TrimmedIgnoreCase' },
                @{Label = 'Description'; Expected = @('Description'); Actual = @('ACCESSLEVELDESCRIPTION', 'DESCRIPTION'); Comparison = 'Trimmed' },
                @{Label = 'ReaderGroupKey'; Expected = @('ReaderGroupKey'); Actual = @('READERGROUPKEY'); Comparison = 'Trimmed' },
                @{Label = 'TimeSpecGroupKey'; Expected = @('TimeSpecGroupKey'); Actual = @('TIMESPECGROUPKEY'); Comparison = 'Trimmed' }
            )
            $verificationResults = @(Test-S2ResourceState -ResourceName 'AccessLevel' -Operation Modify -VerificationPlan @($verificationPlans) -ActualRecord $finalAccessLevels -KeyMap @{Expected = @('AccessLevelKey'); Actual = @('ACCESSLEVELKEY', 'KEY') } -NameMap @{Expected = @('Name'); Actual = @('ACCESSLEVELNAME', 'NAME') } -ComparisonMap $comparisonMap -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name)
            $mergedResults = @(Merge-S2ResourceVerificationResult -ActionResult @($actionResults) -VerificationResult $verificationResults)
            $actionResults = New-Object System.Collections.Generic.List[object]; foreach ($mergedResult in $mergedResults) { [void]$actionResults.Add($mergedResult) }
        }
        catch { $verificationFailure = "Post-modification Access Level verification failed: $($_.Exception.Message)"; Write-S2Error -Message $verificationFailure -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name; $verificationResults = @(Set-S2AccessLevelVerificationBatchFailure -ActionResult @($actionResults) -VerificationPlan @($verificationPlans) -Operation Modify -Message $verificationFailure) }
    }

    $verificationSummary = Get-S2ResourceVerificationSummary -ActionResult @($actionResults) -VerificationResult @($verificationResults)
    $modifiedAndVerified = @($actionResults | Where-Object { $_.Status -eq 'Modified' -and $_.Verified })
    $summaryText = 'Imported={0}; ModifiedAndVerified={1}; VerificationFailed={2}; Previewed={3}; Skipped={4}; Failed={5}' -f @($accessLevelModifyRecords.Count, $modifiedAndVerified.Count, @($verificationSummary.VerificationFailed).Count, @($verificationSummary.Previewed).Count, @($verificationSummary.Skipped).Count, @($verificationSummary.Failed).Count)
    Write-S2Information -Message "Modify Access Level import completed. $summaryText" -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name
    $null = Write-S2ScriptSummary -Resource 'AccessLevel' -CsvPath $InputFile -RowCount $accessLevelModifyRecords.Count -PlanCount $verificationPlans.Count -Created $modifiedAndVerified -Verified $verificationSummary.Verified -VerificationFailed $verificationSummary.VerificationFailed -Skipped $verificationSummary.Skipped -Previewed $verificationSummary.Previewed -Failed $verificationSummary.Failed -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name -PassThru
    Write-S2ConsoleMessage -Message $summaryText -Silent:$Silent
    $actionResults
}
catch { $fatalErrorMessage = "Modify Access Level import terminated: $($_.Exception.Message)"; if ($null -eq $_.Exception.Data -or -not $_.Exception.Data.Contains('S2Logged')) { Write-S2Error -Message $fatalErrorMessage -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name }; Write-S2ConsoleMessage -Message $fatalErrorMessage -Level Error -Silent:$Silent; throw }
finally { if ($null -ne $script:NBApiConnection -and $null -ne $script:NBApiConnection.PSObject.Properties['SessionId'] -and -not [string]::IsNullOrWhiteSpace([string]$script:NBApiConnection.SessionId)) { try { Disconnect-S2NBApiSession -Connection $script:NBApiConnection -LogFile $LogFile }catch { Write-S2Warning -Message "NBAPI logout failed during cleanup: $($_.Exception.Message)" -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name } }; if ($null -ne (Get-Command Clear-S2SensitiveData -ErrorAction SilentlyContinue)) { Clear-S2SensitiveData -Value ([ref]$Credential) -LogFile $LogFile }else { $Credential = $null }; $script:NBApiConnection = $null }
