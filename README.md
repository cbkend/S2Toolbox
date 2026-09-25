# S2 Toolbox

A Windows PowerShell 5.1 toolkit and WPF launcher for administering LenelS2 NetBox environments through documented NBAPI v2, published REST, and selected internal Web API workflows.

> **Project status:** Active refactor and modernization. The shared module architecture, WPF launcher, API catalogs, validation, logging, authentication, and several NBAPI resource modules are present in the current build. Some older operational scripts may still require migration to the shared architecture.

## Overview

S2 Toolbox is designed to make repeatable NetBox administration tasks easier to discover, launch, validate, and audit. The application combines:

- A WPF-based graphical launcher
- Automatic discovery of operational PowerShell scripts
- Add, Modify, and Delete script categories
- Quick search and filtering
- Centralized authentication, logging, validation, CSV, and security modules
- Data-only catalogs for NBAPI commands and REST/Web API endpoints
- Resource-specific NBAPI modules with consistent Get, Resolve, Add, Set, and Remove operations
- Post-action verification helpers for confirming final resource state

## Requirements

- Windows
- Windows PowerShell 5.1
- Windows Presentation Foundation (WPF)
- Network access to the target LenelS2 NetBox system
- A NetBox account with the permissions required by the operation
- NBAPI v2 enabled when using NBAPI workflows

The launcher entry point documents the following execution-policy configuration for the current user:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

Use the execution policy approved by your organization.

## Quick Start

1. Copy or clone the complete project directory without changing its folder structure.
2. Open **Windows PowerShell 5.1**.
3. Change to the project root.
4. If required and organizationally approved, configure the current-user execution policy:

   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

5. Start the toolbox:

   ```powershell
   .\Start-S2Toolbox.ps1
   ```

The launcher validates the UI module, XAML view, and `bin` directory before opening the interface.

## Using the Launcher

The WPF interface discovers `.ps1` files in the `bin` directory, identifies scripts whose names contain an Add, Modify, or Delete category, and creates the corresponding launch buttons.

Typical workflow:

1. Start `Start-S2Toolbox.ps1`.
2. Use **Quick Search** to filter the available scripts.
3. Select an operation from the **ADD**, **MODIFY**, or **DELETE** group.
4. Complete any prompts displayed by the launched script.
5. Review the child PowerShell session and generated log files for results.

Operational scripts are launched in a separate Windows PowerShell process. The current XAML marks the host, username, password, and protocol controls as unavailable or coming soon, so launched scripts may prompt for connection information.

## Project Structure

```text
S2Toolbox/
├── bin/
│   ├── modules/                 # Shared and resource-specific modules
│   └── *.ps1                    # Launchable operational scripts
├── documentation/               # Project and API documentation
├── import/                      # CSV and other import inputs
├── logs/                        # Generated logs
├── resources/
│   ├── S2.Toolbox.xaml          # WPF interface
│   ├── S2.NBAPI.Commands.psd1   # NBAPI command catalog
│   ├── S2.RestApi.Endpoints.psd1
│   └── S2.WebApi.Endpoints.psd1
├── tests/                       # Test assets and coverage
├── S2.CLI.ps1                   # Command-line entry point, where present
├── S2.Toolbox.ps1               # Application launcher
└── Start-S2Toolbox.ps1          # Validating startup entry point
```

Preserve this structure. Shared modules belong in `bin\modules`, documentation belongs in `documentation`, imports belong in `import`, and tests belong in `tests`.

## Architecture

### Launcher and UI

- `Start-S2Toolbox.ps1` validates required paths and imports the UI module.
- `S2.Toolbox.ps1` serves as the primary application entry point.
- `S2.Toolbox.UI.psm1` loads the XAML interface, discovers scripts, builds launch buttons, filters results, and launches selected scripts.
- `resources\S2.Toolbox.xaml` defines the WPF layout, accessibility properties, activity log, and status bar.

### Bootstrap

`S2.ToolboxBootStrap.psm1` imports and verifies required modules, then initializes the API catalogs. Logging is loaded first so later bootstrap activity can be recorded.

### Shared Modules

| Module | Responsibility |
|---|---|
| `S2.Api.Common.psm1` | Connection objects, URI construction, Web sessions, and shared API utilities |
| `S2.Authentication.psm1` | Separate Web and NBAPI authentication workflows |
| `S2.Logging.psm1` | Centralized typed logging, redaction, API diagnostics, item logs, and summaries |
| `S2.Security.psm1` | Credential and string protection, path checks, sensitive-data cleanup, and TLS helpers |
| `S2.Validation.psm1` | Connection, request, CSV, path, identifier, and compatibility validation |
| `S2.Csv.psm1` | Reusable CSV import, export, inspection, and transformation |
| `S2.Import.Common.psm1` | Shared import-path, command-validation, result, and console helpers |
| `S2.NBAPI.psm1` | XML command construction, NBAPI transport, catalog lookup, and response checking |
| `S2.NBAPI.Resource.psm1` | Generic resource paging, XML conversion, key resolution, and CRUD helpers |
| `S2.RestApi.psm1` | Published REST endpoint lookup and authenticated read operations |
| `S2.WebApi.psm1` | Internal Web API request handling with optional CSRF support |
| `S2.Resource.Validation.psm1` | Deterministic post-action verification for Add, Modify, and Delete operations |

### Current NBAPI Resource Modules

The current build includes resource modules for:

- Access Levels
- Access Level Groups
- Holidays
- Network Nodes
- Portal Groups
- Reader Groups
- Time Specifications
- Time Specification Groups

Each follows the same general interface:

- `Get-S2<Resource>`
- `Resolve-S2<Resource>Key`
- `Add-S2<Resource>`
- `Set-S2<Resource>`
- `Remove-S2<Resource>`

These modules use the shared NBAPI resource layer rather than implementing connection, XML, paging, and mutation logic independently.

## API Layers

S2 Toolbox keeps the supported integration paths separate:

### NBAPI v2

- XML-based command interface
- Endpoint: `/nbws/goforms/nbapi`
- Session-based Login and Logout commands
- Used for resource operations supported by the NBAPI command catalog

### Published REST API

- Read-oriented JSON endpoints under `/nbws/api/` and `/nbws/ref/`
- Endpoint definitions stored in `S2.RestApi.Endpoints.psd1`
- Supports collection and detail retrieval, including paginated row aggregation

### Internal Web API

- Separate from published REST and XML NBAPI
- Supports configured GET, POST, PUT, and DELETE operations
- Can include CSRF handling and raw, JSON, or form-encoded JSON bodies
- Internal endpoints may change between NetBox releases and should be used through named catalog definitions where available

## Configuration and Catalogs

API metadata is intentionally separated from executable module logic.

- `S2.NBAPI.Commands.psd1` defines supported NBAPI command metadata.
- `S2.RestApi.Endpoints.psd1` defines documented published REST endpoints.
- `S2.WebApi.Endpoints.psd1` defines selected internal Web endpoints.

Do not invent endpoint paths, commands, request properties, or response fields. Add or change catalog entries only after confirming them through official documentation, testing, or explicit project requirements.

## Logging

Production scripts should use `S2.Logging.psm1` instead of implementing local logging functions.

The logging layer supports:

- Debug, Information, Warning, Error, and Verbose entries
- Validated log paths and automatic log-directory creation
- Sensitive-value redaction
- Sanitized API request and response diagnostics
- Item-level operation logs
- Compact and detailed script summaries

Unless an explicit path is supplied, logs are resolved under the project `logs` directory.

## Security

Security requirements include:

- Never hardcode passwords, tokens, session IDs, or other secrets.
- Prefer `PSCredential` and `SecureString` inputs.
- Validate file paths before access.
- Do not disable certificate validation.
- Do not expose passwords, cookies, CSRF tokens, or NBAPI session IDs in logs.
- Clear sensitive values when they are no longer required.
- Use HTTPS whenever supported and required by the environment.

The launcher includes a protected CLIXML pattern for transferring a credential to a child PowerShell process without placing the credential on the command line. The temporary credential file is scoped to the current Windows user and deleted by the child command.

## CSV Imports

Reusable CSV support is provided through `S2.Csv.psm1`, `S2.Validation.psm1`, and `S2.Import.Common.psm1`.

Import scripts should:

1. Resolve the input path.
2. Import CSV data through the shared CSV module.
3. Validate required columns and values.
4. Reject or report duplicate or invalid records as appropriate.
5. Build an action plan.
6. Execute the requested operation through a resource module.
7. Retrieve final state and verify the result.
8. Write item-level and summary logs.

Place default import files in the `import` directory unless the script accepts another path.

## Development Standards

All contributions must follow the project coding standards:

- Target Windows PowerShell 5.1.
- Use verified API behavior only.
- Reuse existing modules before creating new functions.
- Keep UI, validation, logging, transport, business logic, and data concerns separate.
- Give functions a single responsibility where practical.
- Use Microsoft-approved PowerShell verbs.
- Keep shared functions in modules under `bin\modules`.
- Use strict mode and terminating error handling where appropriate.
- Centralize logging and credential handling.
- Update documentation with code changes.

### Naming

Executable scripts:

```text
<Application>.<Area>.<Verb>.<Noun>_v<Major>.<Minor>.<Patch>.ps1
```

Modules:

```text
<Application>.<Module>.psm1
```

Functions:

```text
<ApprovedVerb>-<Noun>
```

Examples:

```text
S2.Access.Get.Credential_v1.0.0.ps1
S2.Panel.Add.MercuryPanel_v2.3.1.ps1
S2.Logging.psm1
Get-S2Credential
Test-S2PanelConnection
```

## Adding a Launchable Script

1. Create the script in `bin`.
2. Include `Add`, `Modify`, or `Delete` as a distinct filename segment so the launcher can categorize it.
3. Follow the versioned script naming standard.
4. Keep the script focused on orchestration.
5. Import or bootstrap existing shared modules rather than copying helper functions.
6. Accept standard connection or credential parameters when appropriate.
7. Use centralized logging and validation.
8. Add tests and update documentation.

## Testing

The project structure reserves `tests` for test artifacts. Before merging or releasing changes, verify:

- Windows PowerShell 5.1 compatibility
- PowerShell parsing and module import
- Bootstrap dependency validation
- Error and failure paths
- Input and CSV validation
- Authentication and logout cleanup
- Logging redaction
- API catalog lookup
- Paging behavior
- Add, Modify, and Delete final-state verification
- Launcher discovery and categorization

Do not run destructive integration tests against a production NetBox system.

## Known Limitations and Current Work

- The codebase is still transitioning from legacy, monolithic scripts to shared modules and thin orchestration scripts.
- Some older scripts may duplicate authentication, logging, validation, or API helpers.
- Some legacy scripts may use inconsistent names or insecure string-based credential patterns and should be migrated.
- The current UI marks host, username, password, and protocol overrides as unavailable or coming soon.
- Internal Web API endpoints are less stable than published APIs and may change between NetBox releases.
- Test coverage should continue to be expanded under `tests`.

## Troubleshooting

### The launcher reports a missing component

Confirm these paths exist relative to the project root:

```text
bin\modules\S2.Toolbox.UI.psm1
resources\S2.Toolbox.xaml
bin\
```

### A required module fails to load

- Confirm the module exists in `bin\modules`.
- Run Windows PowerShell 5.1, not PowerShell 7.
- Review the newest log under `logs`.
- Check for parser errors or missing dependent modules.

### No scripts appear in the launcher

- Confirm the scripts are `.ps1` files directly under `bin`.
- Confirm each launchable filename contains Add, Modify, or Delete as a distinct segment.
- Confirm the script parses successfully.

### Authentication fails

- Confirm the target host is reachable.
- Confirm the selected authentication workflow matches the API layer.
- Confirm the account has the required NetBox permissions.
- Confirm NBAPI v2 and the required authentication settings are enabled for NBAPI operations.
- Do not place credentials in logs or source files.

## Reference Documentation

The project repository includes or references:

- S2 Toolbox coding standards
- Current build resource and module inventories
- URL endpoint reference
- LenelS2 NetBox NBAPI v2 Guide, April 2025
- Application review and refactor discussion

Use the official NBAPI guide and verified endpoint catalogs as the source of truth for API behavior.

## License

No project license was identified in the reviewed materials. Add an approved license file before external distribution.

## Maintainer

Current source materials identify Brian Kendrick as the author or maintainer of the reviewed S2 Toolbox components.
