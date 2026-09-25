# S2 Toolbox Logging Guide

This document describes the current S2 Toolbox file-logging implementation in `S2.Logging.psm1`. It is intended for developers, operators, and support personnel who need to create, locate, read, or troubleshoot S2 Toolbox log files.

## Overview

The logging module provides centralized, Windows PowerShell 5.1-compatible logging with:

- Validated, convention-based or explicit log paths
- Automatic creation of missing log directories
- UTF-8 file output
- Debug, Information, Warning, Error, and Verbose levels
- Standard source labels
- Sensitive-data redaction
- Sanitized API request and response diagnostics
- Item-level operation logging
- Compact and detailed end-of-script summaries
- Compatibility functions for existing scripts

Production scripts should use this shared module instead of defining local logging functions.

## Module

```text
bin\modules\S2.Logging.psm1
```

Import it directly when needed:

```powershell
Import-Module "$PSScriptRoot\modules\S2.Logging.psm1" -Force
```

In toolbox workflows, prefer the project bootstrap so logging and the other shared dependencies load in the expected order.

## Default Log Location

When `-LogFile` contains only a name and `-LogDirectory` is not supplied, the module resolves the file beneath the project directory:

```text
S2Toolbox\logs```

The module creates the parent directory when it does not exist.

An explicit rooted path, or a value that already contains a directory, is used as the target path after validation.

## File Naming

For a simple value such as:

```powershell
-LogFile 'AccessLevelImport'
```

the default naming convention is:

```text
AccessLevelImport_yyyyMMdd_HHmmss.log
```

Use `-DisableDateSuffix` when all entries must be appended to a stable filename:

```powershell
Write-S2Information `
    -Message 'Script started.' `
    -LogFile 'AccessLevelImport' `
    -DisableDateSuffix
```

This resolves to:

```text
AccessLevelImport.log
```

> When writing multiple entries during one run, initialize and reuse a complete log path or consistently use the stable-name option. Otherwise, a newly resolved timestamp can produce a different filename on later calls.

The toolbox UI currently initializes its log name with this pattern:

```text
S2.Toolbox.yyyy-MM-dd_HH_mm_ss_fff.log
```

Because that value already has an extension, it is treated as the supplied log name.

## Log Entry Format

Typed entries use this general format:

```text
yyyy-MM-dd<TAB>HH:mm:ss.fff<TAB>| LEVEL   |<TAB>[Source] Function :: Message
```

Example:

```text
2026-09-25  13:49:19.123  | INFO    |  [AccessLevel] Start-Import :: Script started.
```

Supported level labels are:

| Function | Log label | Intended use |
|---|---|---|
| `Write-S2Debug` | `DEBUG` | Detailed diagnostics and sanitized API data |
| `Write-S2Information` | `INFO` | Normal milestones and successful operations |
| `Write-S2Warning` | `WARNING` | Recoverable or attention-worthy conditions |
| `Write-S2Error` | `ERROR` | Failed operations and terminal error details |
| `Write-S2Verbose` | `VERBOSE` | Fine-grained execution flow and paging details |

When `-FileName` is supplied, the source label is derived by removing the file extension, the leading `S2` prefix, and a trailing version suffix. For example, `S2.AccessLevel.Add.Import_v2.0.0.ps1` is displayed as a shortened source label in square brackets.

## Basic Usage

### Information

```powershell
Write-S2Information `
    -Message 'Script started.' `
    -LogFile $LogFile `
    -FileName $PSCommandPath `
    -Source $MyInvocation.MyCommand.Name
```

### Warning

```powershell
Write-S2Warning `
    -Message 'The record was skipped because it already exists.' `
    -LogFile $LogFile `
    -FileName $PSCommandPath `
    -Source $MyInvocation.MyCommand.Name
```

### Error

```powershell
Write-S2Error `
    -Message ("Import failed: {0}" -f $_.Exception.Message) `
    -LogFile $LogFile `
    -FileName $PSCommandPath `
    -Source $MyInvocation.MyCommand.Name
```

### Debug and Verbose

```powershell
Write-S2Debug `
    -Message 'Validated input record.' `
    -LogFile $LogFile `
    -FileName $PSCommandPath `
    -Source $MyInvocation.MyCommand.Name

Write-S2Verbose `
    -Message 'Retrieving the next resource page.' `
    -LogFile $LogFile `
    -FileName $PSCommandPath `
    -Source $MyInvocation.MyCommand.Name
```

## Recommended Script Pattern

```powershell
$timestamp = Get-Date -Format 'yyyy-MM-dd_HH_mm_ss_fff'
$LogFile = Join-Path `
    -Path $ToolboxRoot `
    -ChildPath "logs\S2.AccessLevelImport.$timestamp.log"

Write-S2Information `
    -Message 'Script started.' `
    -LogFile $LogFile `
    -FileName $PSCommandPath `
    -Source $MyInvocation.MyCommand.Name

try {
    # Validation and operation logic

    Write-S2Information `
        -Message 'Script completed.' `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
}
catch {
    Write-S2Error `
        -Message $_.Exception.Message `
        -LogFile $LogFile `
        -FileName $PSCommandPath `
        -Source $MyInvocation.MyCommand.Name
    throw
}
```

At minimum, production workflows should record script start and completion, validation outcomes, API activity and results, errors, warnings, import activity, and record-processing status.

## API Diagnostics

Use `Write-S2ApiDebug` for API request and result data:

```powershell
Write-S2ApiDebug `
    -Direction Request `
    -Operation 'AddAccessLevel' `
    -Data $requestData `
    -LogFile $LogFile `
    -FileName $PSCommandPath `
    -Source $MyInvocation.MyCommand.Name
```

```powershell
Write-S2ApiDebug `
    -Direction Result `
    -Operation 'AddAccessLevel' `
    -Data $responseData `
    -LogFile $LogFile `
    -FileName $PSCommandPath `
    -Source $MyInvocation.MyCommand.Name
```

Objects are converted to compact JSON when possible. XML values are represented by their outer XML. Sensitive patterns are redacted before output.

## Item-Level Logging

Use `Write-S2ItemLog` to standardize resource-operation entries:

```powershell
Write-S2ItemLog `
    -Level Information `
    -Action 'Create' `
    -Name 'Employees' `
    -Id '42' `
    -Detail 'Access level created and verified.' `
    -LogFile $LogFile `
    -FileName $PSCommandPath `
    -Source $MyInvocation.MyCommand.Name
```

The message body follows this pattern:

```text
Action :: Name :: Id :: Detail
```

If the name or ID is unavailable, the formatter identifies that the value was not returned.

## Script Summaries

`Write-S2ScriptSummary` writes a compact `INFO` summary and detailed `DEBUG` lines for import workflows.

```powershell
$summary = Write-S2ScriptSummary `
    -Resource 'AccessLevel' `
    -CsvPath $CsvPath `
    -RowCount $rows.Count `
    -PlanCount $plan.Count `
    -Created $created `
    -Verified $verified `
    -VerificationFailed $verificationFailed `
    -Skipped $skipped `
    -Previewed $previewed `
    -Failed $failed `
    -LogPath $LogFile `
    -LogFile $LogFile `
    -FileName $PSCommandPath `
    -Source $MyInvocation.MyCommand.Name `
    -PassThru
```

The returned object includes the supplied collections, calculated success state, counts used in the summary, and log path. Success is false when failed items or verification failures are present.

## Sensitive-Data Redaction

Before a message is written, the logging module redacts recognized values associated with:

- `password`
- `passwd`
- `secret`
- `token`
- `sessionid`
- `authorization`
- XML `PASSWORD` elements
- XML `USERNAME` elements

Redacted values are replaced with:

```text
[REDACTED]
```

NBAPI command and response diagnostics also mask session IDs before logging. Authentication workflows are designed not to log passwords, cookies, CSRF tokens, or NBAPI session IDs.

Redaction is a safeguard, not permission to pass secrets to the logger. Do not intentionally include credentials, cookies, tokens, secure strings, authorization headers, or unfiltered authentication objects in log messages.

## Compatibility Functions

### `Add-Log`

Existing scripts can continue to call:

```powershell
Add-Log -Message 'Operation completed.' -LogFile $LogFile
```

`Add-Log` resolves and validates the path, creates the parent directory, redacts sensitive patterns, and writes UTF-8 content.

### `Set-LogType`

`Set-LogType` remains available for legacy callers. It returns `ERROR` for null or empty values, non-success NBAPI response codes, or strings containing failure wording; otherwise it returns `INFO`.

New development should prefer the typed logging functions.

## Troubleshooting

### No log file is created

- Confirm `S2.Logging.psm1` was imported.
- Confirm `-LogFile` is not null, empty, or whitespace.
- Confirm the process can create and write to the target directory.
- If using the bootstrap, confirm the logging module exists in `bin\modules`.
- Check the calling script for an exception raised before logging was initialized.

### Entries are split across multiple files

Create one complete log path at script startup and reuse it. Alternatively, pass `-DisableDateSuffix` consistently when using a simple logical log name.

### The log path is unexpected

- A simple filename defaults to the project `logs` directory.
- A rooted path or value containing a directory is treated as an explicit path.
- `-LogDirectory` overrides the default directory for simple filenames.

### A log filename changes unexpectedly

The module removes invalid filename characters and strips an existing extension before applying its configured `.log` extension when it builds a convention-based path.

### A write operation fails

The module raises an error containing the resolved target path and the underlying exception message. Check directory permissions, invalid paths, locked files, disk capacity, and endpoint-security controls.

### Debug or verbose messages are not visible in the console

File logging and PowerShell stream visibility are separate. The typed functions write to the file when `-LogFile` is provided, while console display also follows the current Debug and Verbose preferences.

## Security and Handling

- Do not send logs externally without reviewing them.
- Do not rely solely on automatic redaction.
- Store logs only in approved locations.
- Restrict access according to the operational environment.
- Remove logs according to the applicable retention process.
- Do not disable certificate validation to troubleshoot an API error.
- Review `ERROR` and `WARNING` entries before sharing a diagnostic log.

## Exported Logging Commands

```text
Add-Log
Set-LogType
Write-S2Debug
Write-S2Information
Write-S2Warning
Write-S2Error
Write-S2Verbose
Write-S2ApiDebug
Write-S2ItemLog
Write-S2ScriptSummary
```

## Related Documentation

- `README.md`
- `S2-Toolbox-Coding-Standards.md`
- `CurrentBuildSharedModulesv4.docx`
- `S2.Security.psm1`
