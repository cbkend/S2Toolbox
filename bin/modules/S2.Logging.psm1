<#
.SYNOPSIS
    Provides centralized logging services for S2 Toolbox.
.DESCRIPTION
    Writes validated log entries to explicit or convention-based log paths and
    provides typed Debug, Information, Warning, Error, and Verbose logging functions.

    Supports standardized API diagnostics, item-level logging, and end-of-script
    summaries. Source labels remove the S2 application prefix, version suffix,
    and file extension before being placed in square brackets.

    The module remains compatible with current callers that invoke:
        Add-Log -Message <text> -LogFile <name-or-path>

    It does not depend on undeclared caller or module variables such as
    $Script:workingPath, $Script:LogFileDate, or $Script:Errors.
.NOTES
    FileName   : S2.Logging.psm1
    Author     : Brian Kendrick
    Application: S2 Toolbox
    Requires   : Windows PowerShell 5.1
    Version    : 1.1.0
.CHANGELOG
    1.1.0
        - Added standardized source labels in square brackets.
        - Added Debug support for sanitized API request and result details.
        - Added standardized item logging using Action :: Name :: Id.
        - Added compact and detailed end-of-script summary logging.
        - Added Warning and Error helpers with item context.
    1.0.0
        - Removed undeclared script-scope dependencies.
        - Added centralized Debug, Information, Warning, and Error functions.
        - Preserved Add-Log and Set-LogType for compatibility.
        - Added path validation, directory creation, and sensitive-data redaction.
#>

#requires -Version 5.1
Set-StrictMode -Version Latest

#region Private functions
function ConvertTo-S2SafeLogName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    $safeName = $Name.Trim()
    foreach ($character in [System.IO.Path]::GetInvalidFileNameChars()) {
        $safeName = $safeName.Replace([string]$character, '_')
    }

    $safeName = ($safeName -replace '\s+', ' ').Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($safeName)) {
        throw 'Log file name is empty after invalid characters are removed.'
    }

    return $safeName
}

function Test-S2LogPath {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
        return -not [string]::IsNullOrWhiteSpace($fullPath)
    }
    catch {
        return $false
    }
}

function Resolve-S2LogPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LogFile,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$LogDirectory,

        [ValidatePattern('^\.[A-Za-z0-9]+$')]
        [string]$Extension = '.log',

        [switch]$DisableDateSuffix
    )

    $value = $LogFile.Trim()
    $hasDirectory = -not [string]::IsNullOrWhiteSpace(
        [System.IO.Path]::GetDirectoryName($value)
    )

    if ([System.IO.Path]::IsPathRooted($value) -or $hasDirectory) {
        $candidatePath = [System.IO.Path]::GetFullPath($value)
    }
    else {
        if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
            $toolboxRoot = [System.IO.Path]::GetFullPath(
                (Join-Path -Path $PSScriptRoot -ChildPath '..\..')
            )
            $LogDirectory = Join-Path -Path $toolboxRoot -ChildPath 'logs'
        }
        else {
            $LogDirectory = [System.IO.Path]::GetFullPath($LogDirectory)
        }

        $safeName = ConvertTo-S2SafeLogName -Name $value
        if (-not [string]::IsNullOrWhiteSpace([System.IO.Path]::GetExtension($safeName))) {
            $safeName = [System.IO.Path]::GetFileNameWithoutExtension($safeName)
        }

        if ($DisableDateSuffix.IsPresent) {
            $fileName = '{0}{1}' -f $safeName, $Extension
        }
        else {
            $fileName = '{0}_{1}{2}' -f $safeName, (Get-Date -Format 'yyyyMMdd_HHmmss'), $Extension
        }

        $candidatePath = [System.IO.Path]::GetFullPath(
            (Join-Path -Path $LogDirectory -ChildPath $fileName)
        )
    }

    if (-not (Test-S2LogPath -Path $candidatePath)) {
        throw "Log path is invalid: $candidatePath"
    }

    return $candidatePath
}

function Get-S2LogSourceName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FileName
    )

    $name = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $name = $name -replace '^S2[._-]', ''
    $name = $name -replace '(?i)[._-]v\d+(?:\.\d+){1,3}$', ''
    $name = $name.Trim(' ', '.', '_', '-')

    if ([string]::IsNullOrWhiteSpace($name)) {
        return 'Unknown'
    }

    return $name
}

function Protect-S2LogMessage {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message
    )

    $protectedMessage = $Message
    $patterns = @(
        '(?i)(password\s*[=:]\s*)([^\s,;<>]+)',
        '(?i)(passwd\s*[=:]\s*)([^\s,;<>]+)',
        '(?i)(secret\s*[=:]\s*)([^\s,;<>]+)',
        '(?i)(token\s*[=:]\s*)([^\s,;<>]+)',
        '(?i)(sessionid\s*[=:]\s*["'']?)([^"''\s,;<>]+)',
        '(?i)(authorization\s*[=:]\s*)([^\r\n]+)',
        '(?i)(<PASSWORD>)(.*?)(</PASSWORD>)',
        '(?i)(<USERNAME>)(.*?)(</USERNAME>)'
    )

    foreach ($pattern in $patterns) {
        if ($pattern -match '<PASSWORD>|<USERNAME>') {
            $protectedMessage = [regex]::Replace(
                $protectedMessage,
                $pattern,
                '$1[REDACTED]$3'
            )
        }
        else {
            $protectedMessage = [regex]::Replace(
                $protectedMessage,
                $pattern,
                '$1[REDACTED]'
            )
        }
    }

    return $protectedMessage
}

function ConvertTo-S2LogText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$InputObject,

        [ValidateRange(1, 100)]
        [int]$Depth = 10
    )

    if ($null -eq $InputObject) {
        return '<null>'
    }

    if ($InputObject -is [string]) {
        return [string]$InputObject
    }

    if ($InputObject -is [xml]) {
        return $InputObject.OuterXml
    }

    try {
        return ConvertTo-Json -InputObject $InputObject -Depth $Depth -Compress
    }
    catch {
        return ($InputObject | Out-String).Trim()
    }
}

function Format-S2LogEntry {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Debug', 'Information', 'Warning', 'Error', 'Verbose')]
        [string]$Level,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Source,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$FileName
    )

    $levelName = switch ($Level) {
        'Debug' { 'DEBUG' }
        'Information' { 'INFO' }
        'Warning' { 'WARNING' }
        'Error' { 'ERROR' }
        'Verbose' { 'VERBOSE' }
    }

    $safeMessage = Protect-S2LogMessage -Message $Message
    if (-not [string]::IsNullOrWhiteSpace($Source)) {
        $safeMessage = '{0} :: {1}' -f $Source.Trim(), $safeMessage
    }

    if (-not [string]::IsNullOrWhiteSpace($FileName)) {
        $sourceName = Get-S2LogSourceName -FileName $FileName
        $safeMessage = '[{0}] {1}' -f $sourceName, $safeMessage
    }

    return "{0}`t| {1,-7} |`t{2}" -f (
        Get-Date -Format "yyyy-MM-dd`tHH:mm:ss.fff"
    ), $levelName, $safeMessage
}

function Write-S2Log {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Debug', 'Information', 'Warning', 'Error', 'Verbose')]
        [string]$Level,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message,

        [AllowNull()]
        [AllowEmptyString()]
        [Alias('Log')]
        [string]$LogFile,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$LogDirectory,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Source,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$FileName,

        [switch]$PassThru,

        [switch]$DisableDateSuffix
    )

    $entry = Format-S2LogEntry `
        -Level $Level `
        -Message $Message `
        -Source $Source `
        -FileName $FileName

    if (-not [string]::IsNullOrWhiteSpace($LogFile)) {
        Add-Log `
            -Message $entry `
            -LogFile $LogFile `
            -LogDirectory $LogDirectory `
            -DisableDateSuffix:$DisableDateSuffix
    }

    switch ($Level) {
        'Debug' { Write-Debug $entry }
        'Information' { Write-Verbose $entry }
        'Warning' { Write-Warning $entry }
        'Error' { Write-Warning -Message $entry }
        'Verbose' { Write-Verbose -Message $entry }
    }

    if ($PassThru.IsPresent) {
        return $entry
    }
}

function Format-S2ItemIdentity {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Action,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Name,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Id,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Detail
    )

    $itemName = if ([string]::IsNullOrWhiteSpace($Name)) { 'Name not returned' } else { $Name.Trim() }
    $itemId = if ([string]::IsNullOrWhiteSpace($Id)) { 'ID not returned' } else { $Id.Trim() }
    $parts = @($Action.Trim(), $itemName, $itemId)

    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        $parts += $Detail.Trim()
    }

    return ($parts -join ' :: ')
}

function Format-S2SummaryCollection {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object[]]$Items
    )

    if ($null -eq $Items -or @($Items).Count -eq 0) {
        return '{}'
    }

    $values = foreach ($item in @($Items)) {
        if ($item -is [string]) {
            [string]$item
            continue
        }

        $name = $null
        $id = $null
        if ($null -ne $item.PSObject.Properties['Name']) {
            $name = [string]$item.Name
        }
        if ($null -ne $item.PSObject.Properties['Id']) {
            $id = [string]$item.Id
        }

        if (-not [string]::IsNullOrWhiteSpace($name) -and
            -not [string]::IsNullOrWhiteSpace($id)) {
            '{0} :: {1}' -f $name, $id
        }
        elseif (-not [string]::IsNullOrWhiteSpace($name)) {
            $name
        }
        else {
            [string]$item
        }
    }

    return '{' + ($values -join '; ') + '}'
}
#endregion  Private functions

#region Public file logging
function Add-Log {
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Alias('Log')]
        [string]$LogFile,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$LogDirectory,

        [switch]$DisableDateSuffix,

        [switch]$PassThru
    )

    $path = Resolve-S2LogPath `
        -LogFile $LogFile `
        -LogDirectory $LogDirectory `
        -DisableDateSuffix:$DisableDateSuffix

    $parentPath = Split-Path -Path $path -Parent
    if (-not (Test-Path -LiteralPath $parentPath -PathType Container)) {
        $null = New-Item -Path $parentPath -ItemType Directory -Force -ErrorAction Stop
    }

    try {
        Add-Content `
            -LiteralPath $path `
            -Value (Protect-S2LogMessage -Message $Message) `
            -Encoding UTF8 `
            -ErrorAction Stop
    }
    catch {
        throw "Unable to write S2 log file '$path'. $($_.Exception.Message)"
    }

    if ($PassThru.IsPresent) {
        return Get-Item -LiteralPath $path -ErrorAction Stop
    }
}
#endregion Public file logging

#region Public typed logging
function Write-S2Debug {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string]$Message,
        [AllowNull()][AllowEmptyString()][Alias('Log')][string]$LogFile,
        [AllowNull()][AllowEmptyString()][string]$LogDirectory,
        [AllowNull()][AllowEmptyString()][string]$Source,
        [AllowNull()][AllowEmptyString()][string]$FileName,
        [switch]$PassThru,
        [switch]$DisableDateSuffix
    )
    process { Write-S2Log @PSBoundParameters -Level Debug }
}

function Write-S2Information {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string]$Message,
        [AllowNull()][AllowEmptyString()][Alias('Log')][string]$LogFile,
        [AllowNull()][AllowEmptyString()][string]$LogDirectory,
        [AllowNull()][AllowEmptyString()][string]$Source,
        [AllowNull()][AllowEmptyString()][string]$FileName,
        [switch]$PassThru,
        [switch]$DisableDateSuffix
    )
    process { Write-S2Log @PSBoundParameters -Level Information }
}

function Write-S2Warning {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string]$Message,
        [AllowNull()][AllowEmptyString()][Alias('Log')][string]$LogFile,
        [AllowNull()][AllowEmptyString()][string]$LogDirectory,
        [AllowNull()][AllowEmptyString()][string]$Source,
        [AllowNull()][AllowEmptyString()][string]$FileName,
        [switch]$PassThru,
        [switch]$DisableDateSuffix
    )
    process { Write-S2Log @PSBoundParameters -Level Warning }
}

function Write-S2Error {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string]$Message,
        [AllowNull()][AllowEmptyString()][Alias('Log')][string]$LogFile,
        [AllowNull()][AllowEmptyString()][string]$LogDirectory,
        [AllowNull()][AllowEmptyString()][string]$Source,
        [AllowNull()][AllowEmptyString()][string]$FileName,
        [switch]$PassThru,
        [switch]$DisableDateSuffix
    )
    process { Write-S2Log @PSBoundParameters -Level Error }
}

function Write-S2Verbose {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string]$Message,
        [AllowNull()][AllowEmptyString()][Alias('Log')][string]$LogFile,
        [AllowNull()][AllowEmptyString()][string]$LogDirectory,
        [AllowNull()][AllowEmptyString()][string]$Source,
        [AllowNull()][AllowEmptyString()][string]$FileName,
        [switch]$PassThru,
        [switch]$DisableDateSuffix
    )
    process { Write-S2Log @PSBoundParameters -Level Verbose }
}
#endregion Public typed logging

#region API, item, and summary logging
function Write-S2ApiDebug {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Request', 'Result')]
        [string]$Direction,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Operation,

        [AllowNull()]
        [object]$Data,

        [AllowNull()][AllowEmptyString()][Alias('Log')][string]$LogFile,
        [AllowNull()][AllowEmptyString()][string]$LogDirectory,
        [AllowNull()][AllowEmptyString()][string]$Source,
        [AllowNull()][AllowEmptyString()][string]$FileName,
        [ValidateRange(1, 100)][int]$Depth = 10,
        [switch]$DisableDateSuffix
    )

    $detail = Protect-S2LogMessage -Message (ConvertTo-S2LogText -InputObject $Data -Depth $Depth)
    $Message = 'API {0} :: {1} :: {2}' -f $Direction.ToLowerInvariant(), $Operation, $detail

    Write-S2Debug `
        -Message $Message `
        -LogFile $LogFile `
        -LogDirectory $LogDirectory `
        -Source $Source `
        -FileName $FileName `
        -DisableDateSuffix:$DisableDateSuffix
}

function Write-S2ItemLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Debug', 'Information', 'Warning', 'Error', 'Verbose')]
        [string]$Level,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Action,

        [AllowNull()][AllowEmptyString()][string]$Name,
        [AllowNull()][AllowEmptyString()][string]$Id,
        [AllowNull()][AllowEmptyString()][string]$Detail,
        [AllowNull()][AllowEmptyString()][Alias('Log')][string]$LogFile,
        [AllowNull()][AllowEmptyString()][string]$LogDirectory,
        [AllowNull()][AllowEmptyString()][string]$Source,
        [AllowNull()][AllowEmptyString()][string]$FileName,
        [switch]$DisableDateSuffix
    )

    $Message = Format-S2ItemIdentity -Action $Action -Name $Name -Id $Id -Detail $Detail
    Write-S2Log `
        -Level $Level `
        -Message $Message `
        -LogFile $LogFile `
        -LogDirectory $LogDirectory `
        -Source $Source `
        -FileName $FileName `
        -DisableDateSuffix:$DisableDateSuffix
}

function Write-S2ScriptSummary {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Resource,
        [AllowNull()][AllowEmptyString()][string]$CsvPath,
        [ValidateRange(0, [int]::MaxValue)][int]$RowCount = 0,
        [ValidateRange(0, [int]::MaxValue)][int]$PlanCount = 0,
        [AllowNull()][object[]]$Deleted,
        [AllowNull()][object[]]$Created,
        [AllowNull()][object[]]$Verified,
        [AllowNull()][object[]]$VerificationFailed,
        [AllowNull()][object[]]$Skipped,
        [AllowNull()][object[]]$Previewed,
        [AllowNull()][object[]]$Failed,
        [AllowNull()][AllowEmptyString()][string]$LogPath,
        [AllowNull()][AllowEmptyString()][Alias('Log')][string]$LogFile,
        [AllowNull()][AllowEmptyString()][string]$LogDirectory,
        [AllowNull()][AllowEmptyString()][string]$Source,
        [AllowNull()][AllowEmptyString()][string]$FileName,
        [switch]$DisableDateSuffix,
        [switch]$PassThru
    )

    $deletedItems = @($Deleted)
    $createdItems = @($Created)
    $verifiedItems = @($Verified)
    $verificationFailedItems = @($VerificationFailed)
    $skippedItems = @($Skipped)
    $previewedItems = @($Previewed)
    $failedItems = @($Failed)
    $success = ($failedItems.Count -eq 0 -and $verificationFailedItems.Count -eq 0)

    $compact = 'Import summary :: Resource={0}; Plans={1}; Deleted={2}; Created={3}; Verified={4}; VerificationFailed={5}; Skipped={6}; Previewed={7}; Failed={8}; Success={9}' -f @(
        $Resource,
        $PlanCount,
        $deletedItems.Count,
        $createdItems.Count,
        $verifiedItems.Count,
        $verificationFailedItems.Count,
        $skippedItems.Count,
        $previewedItems.Count,
        $failedItems.Count,
        $success
    )

    Write-S2Information `
        -Message $compact `
        -LogFile $LogFile `
        -LogDirectory $LogDirectory `
        -Source $Source `
        -FileName $FileName `
        -DisableDateSuffix:$DisableDateSuffix

    $detailLines = @(
        'Import summary',
        ('Resource           : {0}' -f $Resource),
        ('CsvPath            : {0}' -f $CsvPath),
        ('RowCount           : {0}' -f $RowCount),
        ('PlanCount          : {0}' -f $PlanCount),
        ('Deleted            : {0}' -f (Format-S2SummaryCollection -Items $deletedItems)),
        ('Created            : {0}' -f (Format-S2SummaryCollection -Items $createdItems)),
        ('Verified           : {0}' -f (Format-S2SummaryCollection -Items $verifiedItems)),
        ('VerificationFailed : {0}' -f (Format-S2SummaryCollection -Items $verificationFailedItems)),
        ('Skipped            : {0}' -f (Format-S2SummaryCollection -Items $skippedItems)),
        ('Previewed          : {0}' -f (Format-S2SummaryCollection -Items $previewedItems)),
        ('Failed             : {0}' -f (Format-S2SummaryCollection -Items $failedItems)),
        ('Success            : {0}' -f $success),
        ('LogPath            : {0}' -f $LogPath)
    )

    foreach ($line in $detailLines) {
        Write-S2Debug `
            -Message $line `
            -LogFile $LogFile `
            -LogDirectory $LogDirectory `
            -Source $Source `
            -FileName $FileName `
            -DisableDateSuffix:$DisableDateSuffix
    }

    $result = [pscustomobject]@{
        PSTypeName         = 'S2.ScriptSummary'
        Resource           = $Resource
        CsvPath            = $CsvPath
        RowCount           = $RowCount
        PlanCount          = $PlanCount
        Deleted            = $deletedItems
        Created            = $createdItems
        Verified           = $verifiedItems
        VerificationFailed = $verificationFailedItems
        Skipped            = $skippedItems
        Previewed          = $previewedItems
        Failed             = $failedItems
        Success            = $success
        LogPath            = $LogPath
    }

    if ($PassThru.IsPresent) {
        return $result
    }
}

#endregion API, item, and summary logging

#region Compatibility function
function Set-LogType {
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([string])]
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$FunctionName
    )

    if ($null -eq $Value) { return 'ERROR' }
    if ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) { return 'ERROR' }

    $responseCode = $null
    if ($null -ne $Value.PSObject.Properties['NETBOX']) {
        $netbox = $Value.NETBOX
        if ($null -ne $netbox -and $null -ne $netbox.PSObject.Properties['RESPONSE']) {
            $response = $netbox.RESPONSE
            if ($null -ne $response -and $null -ne $response.PSObject.Properties['CODE']) {
                $responseCode = [string]$response.CODE
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($responseCode) -and $responseCode -ine 'SUCCESS') {
        return 'ERROR'
    }
    if ($Value -is [string] -and $Value -match '(?i)\bfail(?:ure|ed)?\b') {
        return 'ERROR'
    }

    return 'INFO'
}
#endregion Compatibility function

#region Public Exports
Export-ModuleMember -Function @(
    'Add-Log',
    'Set-LogType',
    'Write-S2Debug',
    'Write-S2Information',
    'Write-S2Warning',
    'Write-S2Error',
    'Write-S2Verbose',
    'Write-S2ApiDebug',
    'Write-S2ItemLog',
    'Write-S2ScriptSummary'
)
#endregion Public Exports