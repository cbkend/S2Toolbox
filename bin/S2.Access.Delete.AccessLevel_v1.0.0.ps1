<#
.SYNOPSIS
    Deletes S2 NetBox Access Levels identified by name in a CSV file.
.DESCRIPTION
    Validates each Name, resolves its key through Resolve-S2NBApiResourceKey,
    deletes through Remove-S2AccessLevel, and verifies absence through the shared
    resource-validation module.

    Required CSV column and value:
        Name
.NOTES
    FileName   : S2.Access.Delete.AccessLevel_v1.0.0.ps1
    Application: S2 Toolbox
    Requires   : Windows PowerShell 5.1
#>
#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateNotNullOrEmpty()][string]$HostName,
    [ValidateNotNull()][System.Management.Automation.PSCredential]$Credential,
    [ValidateNotNullOrEmpty()][string]$CredentialPath,
    [ValidateSet('http', 'https')][string]$Protocol = 'https',
    [ValidateNotNullOrEmpty()][string]$InputFile = 'AccessLevelDelete.csv',
    [ValidateNotNullOrEmpty()][string]$LogFile = 'DeleteAccessLevel',
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
if (-not(Test-Path -LiteralPath $bootstrapPath -PathType Leaf)) { throw [System.IO.FileNotFoundException]::new("Required bootstrap was not found: $bootstrapPath") }
if (-not(Test-Path -LiteralPath $commonModulePath -PathType Leaf)) { throw [System.IO.FileNotFoundException]::new("Required Access Level common module was not found: $commonModulePath") }
. $bootstrapPath
Import-Module -Name $commonModulePath -Force -ErrorAction Stop
Assert-S2RequiredCommand -Name @(
    'Write-S2Information', 'Write-S2Warning', 'Write-S2Error', 'Write-S2ItemLog', 'Write-S2ScriptSummary',
    'Test-S2PathSafety', 'Test-S2CsvFile', 'Get-S2CsvSchemaValidation', 'Test-S2CsvRequiredValues', 'Test-S2DuplicateValues', 'Test-S2StringLength', 'Test-S2ImportRecord', 'Import-S2CsvData',
    'New-S2ApiConnection', 'Connect-S2NBApiSession', 'Disconnect-S2NBApiSession', 'Unprotect-S2Credential', 'Clear-S2SensitiveData', 'Get-S2NBApiCommand',
    'Resolve-S2NBApiResourceKey', 'Get-S2AccessLevel', 'Remove-S2AccessLevel', 'Test-S2ResourceState', 'Merge-S2ResourceVerificationResult', 'Get-S2ResourceVerificationSummary'
)

try {
    foreach ($commandName in @('GetAccessLevel', 'GetAccessLevels', 'DeleteAccessLevel')) { Get-S2NBApiCommand -Name $commandName -LogFile $LogFile | Out-Null }
    if ([string]::IsNullOrWhiteSpace($HostName)) { $HostName = Read-Host 'Enter NetBox host name or IP address' }
    if ([string]::IsNullOrWhiteSpace($HostName)) { throw 'HostName is required.' }
    if ($null -eq $Credential -and -not [string]::IsNullOrWhiteSpace($CredentialPath)) { $Credential = Unprotect-S2Credential -Path $CredentialPath -LogFile $LogFile }
    if ($null -eq $Credential) { $Credential = Get-Credential -Message 'Enter your NetBox credentials' }
    if ($null -eq $Credential) { throw 'Credential is required.' }
    $InputFile = Resolve-S2ImportPath -Path $InputFile -ScriptRoot $PSScriptRoot
    if (-not(Test-S2PathSafety -Path $InputFile -LogFile $LogFile)) { throw "Input path is invalid or unsafe: $InputFile" }
    if (-not(Test-S2CsvFile -Path $InputFile -LogFile $LogFile)) { throw "CSV input file was not found: $InputFile" }
    Write-S2Information -Message 'Delete Access Level import started.' -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name

    $script:NBApiConnection = New-S2ApiConnection -HostName $HostName -Protocol $Protocol -LogFile $LogFile
    $script:NBApiConnection = Connect-S2NBApiSession -Connection $script:NBApiConnection -Credential $Credential -LogFile $LogFile
    $accessLevelDeleteRecords = @(Import-S2CsvData -Path $InputFile -LogFile $LogFile)
    if ($accessLevelDeleteRecords.Count -eq 0) { throw 'No delete records found.' }
    $csvSchemaValidation = Get-S2CsvSchemaValidation -Data $accessLevelDeleteRecords -RequiredColumns @('Name') -LogFile $LogFile
    if (-not $csvSchemaValidation.Valid) { throw 'CSV must contain Name.' }
    $requiredValueErrors = @(Test-S2CsvRequiredValues -Data $accessLevelDeleteRecords -RequiredColumns @('Name') -LogFile $LogFile)
    if ($requiredValueErrors.Count -gt 0) { Write-S2Warning -Message "CSV contains $($requiredValueErrors.Count) missing Name value(s)." -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name }
    $duplicateNames = @(Test-S2DuplicateValues -Data $accessLevelDeleteRecords -Column 'Name' -LogFile $LogFile)
    if ($duplicateNames.Count -gt 0) { Write-S2Warning -Message 'CSV contains duplicate Access Level names. Later rows are skipped.' -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name }

    $accessLevels = @(Get-S2AccessLevel -Connection $script:NBApiConnection -LogFile $LogFile)
    $processedAccessLevelNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    for ($recordIndex = 0; $recordIndex -lt $accessLevelDeleteRecords.Count; $recordIndex++) {
        $accessLevelDeleteRecord = $accessLevelDeleteRecords[$recordIndex]
        $rowNumber = $recordIndex + 2
        $accessLevelName = ([string]$accessLevelDeleteRecord.Name).Trim()
        try {
            $recordValidation = Test-S2ImportRecord -Record $accessLevelDeleteRecord -RequiredFields @('Name') -LogFile $LogFile
            if (-not $recordValidation.Valid) { $validationMessage = $recordValidation.Errors -join ' '; [void]$actionResults.Add((New-S2ActionResult -RowNumber $rowNumber -Name $accessLevelName -Status Failed -Message $validationMessage)); Write-S2ItemLog -Level Error -Action 'Validate' -Name $accessLevelName -Id ([string]$rowNumber) -Detail $validationMessage -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name; continue }
            if (-not(Test-S2StringLength -Value $accessLevelName -MinimumLength 1 -MaximumLength 64 -LogFile $LogFile)) { $validationMessage = 'Name must contain between 1 and 64 characters.'; [void]$actionResults.Add((New-S2ActionResult -RowNumber $rowNumber -Name $accessLevelName -Status Failed -Message $validationMessage)); Write-S2ItemLog -Level Error -Action 'Validate' -Name $accessLevelName -Id ([string]$rowNumber) -Detail $validationMessage -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name; continue }
            if (-not $processedAccessLevelNames.Add($accessLevelName)) { $skipMessage = 'Duplicate Name in CSV.'; [void]$actionResults.Add((New-S2ActionResult -RowNumber $rowNumber -Name $accessLevelName -Status Skipped -Message $skipMessage)); Write-S2ItemLog -Level Warning -Action 'Skip' -Name $accessLevelName -Id ([string]$rowNumber) -Detail $skipMessage -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name; continue }
            if ($accessLevels.Count -eq 0) { $skipMessage = 'Access Level does not exist.'; [void]$actionResults.Add((New-S2ActionResult -RowNumber $rowNumber -Name $accessLevelName -Status Skipped -Message $skipMessage)); Write-S2ItemLog -Level Warning -Action 'Skip' -Name $accessLevelName -Id ([string]$rowNumber) -Detail $skipMessage -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name; continue }
            try { $accessLevelKey = Resolve-S2NBApiResourceKey -InputObject $accessLevels -Name $accessLevelName -NameProperty @('ACCESSLEVELNAME', 'NAME') -KeyProperty @('ACCESSLEVELKEY', 'KEY') -ResourceName 'Access Level' -LogFile $LogFile }catch { if ($_.Exception.Message -match 'was not found') { $skipMessage = 'Access Level does not exist.'; [void]$actionResults.Add((New-S2ActionResult -RowNumber $rowNumber -Name $accessLevelName -Status Skipped -Message $skipMessage)); Write-S2ItemLog -Level Warning -Action 'Skip' -Name $accessLevelName -Id ([string]$rowNumber) -Detail $skipMessage -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name; continue }; throw }

            if ($Preview.IsPresent -or $WhatIfPreference) { $previewMessage = 'Delete target validated; command not submitted.'; [void]$actionResults.Add((New-S2ActionResult -RowNumber $rowNumber -Name $accessLevelName -AccessLevelKey $accessLevelKey -Status Previewed -Message $previewMessage)); Write-S2ItemLog -Level Information -Action 'Preview' -Name $accessLevelName -Id $accessLevelKey -Detail $previewMessage -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name; continue }
            if (-not $PSCmdlet.ShouldProcess($accessLevelName, 'Delete S2 Access Level')) { $skipMessage = 'Access Level deletion was declined through ShouldProcess.'; [void]$actionResults.Add((New-S2ActionResult -RowNumber $rowNumber -Name $accessLevelName -AccessLevelKey $accessLevelKey -Status Skipped -Message $skipMessage)); Write-S2ItemLog -Level Warning -Action 'Skip' -Name $accessLevelName -Id $accessLevelKey -Detail $skipMessage -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name; continue }
            $null = Remove-S2AccessLevel -Connection $script:NBApiConnection -Key ([int]$accessLevelKey) -LogFile $LogFile
            [void]$actionResults.Add((New-S2ActionResult -RowNumber $rowNumber -Name $accessLevelName -AccessLevelKey $accessLevelKey -Status Deleted -Message 'Access Level deletion submitted.'))
            [void]$verificationPlans.Add([pscustomobject]@{RowNumber = $rowNumber; Name = $accessLevelName; AccessLevelKey = [string]$accessLevelKey })
            Write-S2ItemLog -Level Information -Action 'Delete' -Name $accessLevelName -Id $accessLevelKey -Detail 'Access Level deletion submitted.' -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name
        }
        catch { $resultRecord = $actionResults | Where-Object { $_.RowNumber -eq $rowNumber } | Select-Object -First 1; if ($null -ne $resultRecord) { $resultRecord.Status = 'Failed'; $resultRecord.Verified = $false; $resultRecord.Message = $_.Exception.Message; $resultRecord.VerificationMessage = '' }else { [void]$actionResults.Add((New-S2ActionResult -RowNumber $rowNumber -Name $accessLevelName -Status Failed -Message $_.Exception.Message)) }; Write-S2ItemLog -Level Error -Action 'Delete' -Name $accessLevelName -Id ([string]$rowNumber) -Detail $_.Exception.Message -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name }
    }

    $verificationResults = @()
    if (-not $Preview.IsPresent -and -not $WhatIfPreference -and $verificationPlans.Count -gt 0) { try { $finalAccessLevels = @(Get-S2AccessLevel -Connection $script:NBApiConnection -LogFile $LogFile); $verificationResults = @(Test-S2ResourceState -ResourceName 'AccessLevel' -Operation Delete -VerificationPlan @($verificationPlans) -ActualRecord $finalAccessLevels -KeyMap @{Expected = @('AccessLevelKey'); Actual = @('ACCESSLEVELKEY', 'KEY') } -NameMap @{Expected = @('Name'); Actual = @('ACCESSLEVELNAME', 'NAME') } -ComparisonMap @() -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name); $mergedResults = @(Merge-S2ResourceVerificationResult -ActionResult @($actionResults) -VerificationResult $verificationResults); $actionResults = New-Object System.Collections.Generic.List[object]; foreach ($mergedResult in $mergedResults) { [void]$actionResults.Add($mergedResult) } }catch { $verificationFailure = "Post-deletion Access Level verification failed: $($_.Exception.Message)"; Write-S2Error -Message $verificationFailure -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name; $verificationResults = @(Set-S2AccessLevelVerificationBatchFailure -ActionResult @($actionResults) -VerificationPlan @($verificationPlans) -Operation Delete -Message $verificationFailure) } }

    $verificationSummary = Get-S2ResourceVerificationSummary -ActionResult @($actionResults) -VerificationResult @($verificationResults)
    $deletedAndVerified = @($actionResults | Where-Object { $_.Status -eq 'Deleted' -and $_.Verified })
    $summaryText = 'Imported={0}; DeletedAndVerified={1}; VerificationFailed={2}; Previewed={3}; Skipped={4}; Failed={5}' -f @($accessLevelDeleteRecords.Count, $deletedAndVerified.Count, @($verificationSummary.VerificationFailed).Count, @($verificationSummary.Previewed).Count, @($verificationSummary.Skipped).Count, @($verificationSummary.Failed).Count)
    Write-S2Information -Message "Delete Access Level import completed. $summaryText" -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name
    $null = Write-S2ScriptSummary -Resource 'AccessLevel' -CsvPath $InputFile -RowCount $accessLevelDeleteRecords.Count -PlanCount $verificationPlans.Count -Created $deletedAndVerified -Verified $verificationSummary.Verified -VerificationFailed $verificationSummary.VerificationFailed -Skipped $verificationSummary.Skipped -Previewed $verificationSummary.Previewed -Failed $verificationSummary.Failed -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name -PassThru
    Write-S2ConsoleMessage -Message $summaryText -Silent:$Silent
    $actionResults
}
catch { $fatalErrorMessage = "Delete Access Level import terminated: $($_.Exception.Message)"; if ($null -eq $_.Exception.Data -or -not $_.Exception.Data.Contains('S2Logged')) { Write-S2Error -Message $fatalErrorMessage -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name }; Write-S2ConsoleMessage -Message $fatalErrorMessage -Level Error -Silent:$Silent; throw }
finally { if ($null -ne $script:NBApiConnection -and $null -ne $script:NBApiConnection.PSObject.Properties['SessionId'] -and -not [string]::IsNullOrWhiteSpace([string]$script:NBApiConnection.SessionId)) { try { Disconnect-S2NBApiSession -Connection $script:NBApiConnection -LogFile $LogFile }catch { Write-S2Warning -Message "NBAPI logout failed during cleanup: $($_.Exception.Message)" -LogFile $LogFile -FileName $PSCommandPath -Source $MyInvocation.MyCommand.Name } }; if ($null -ne (Get-Command Clear-S2SensitiveData -ErrorAction SilentlyContinue)) { Clear-S2SensitiveData -Value ([ref]$Credential) -LogFile $LogFile }else { $Credential = $null }; $script:NBApiConnection = $null }
