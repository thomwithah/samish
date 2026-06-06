# Testing Guide

This document describes how to run, understand, and extend the SAMISH test suite.

## Prerequisites

| Requirement | Version | Notes |
|---|---|---|
| PowerShell | 5.1+ | Ships with Windows 10/11 |
| Pester | 5.x | Install: `Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser` |
| Execution Policy | RemoteSigned or Bypass | `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` |

## Running Tests

**Run the entire suite:**
```powershell
Invoke-Pester -Path Tests/ -Output Detailed
```

**Run a single test file:**
```powershell
Invoke-Pester -Path Tests/Engine.Tests.ps1 -Output Detailed
```

**Run with code coverage (optional):**
```powershell
Invoke-Pester -Path Tests/ -Output Detailed -CodeCoverage @("App/Modules/Logic.ps1", "App/Modules/ConfigBackup.Module.ps1")
```

## Lint Verification

Run PSScriptAnalyzer against the codebase to verify the warning baseline:
```powershell
Invoke-ScriptAnalyzer -Path ./App/ -Settings .github/workflows/PSScriptAnalyzerSettings.psd1 -Recurse
```

The current baseline is **0 errors, 21 warnings** in `App/Modules/`. The `CodeQuality.Tests.ps1` file enforces this baseline automatically.

## Test Suite Overview

| File | Purpose | Key Scenarios |
|---|---|---|
| `CodeQuality.Tests.ps1` | Lint baseline enforcement | PSScriptAnalyzer warning counts, ASCII compliance, header block validation |
| `Config.Tests.ps1` | Config read/write and schema | JSON parsing, atomic writes, schema validation |
| `Diagnostics.Tests.ps1` | Diagnostic report compilation | Report generation, output formatting |
| `Engine.Tests.ps1` | Engine main loop state machine | Idle-to-stop, stop-to-wake, blocker deferral, game mode guard, auto-recovery, sleep throttle, self-healing backoff |
| `FailStates.Tests.ps1` | Edge cases and error recovery | Corrupt config auto-fix, adapter stop failures, backup pruning |
| `Integration.Tests.ps1` | Cross-module workflows | Full install/uninstall sequence, config lifecycle, pre-flight gating |
| `Logger.Tests.ps1` | Logging module | Log file resolution, rotation |
| `Logic.Tests.ps1` | Business logic functions | UI input parsing, hotkey VK mapping, uninstall logic |
| `Setup.Tests.ps1` | Setup UI and install flow | Install parameters, setup validation |
| `UwpMedia.Tests.ps1` | UWP media control (SMTC) | Playback status detection, media session handling |
| `Validation.Tests.ps1` | Pre-flight validation | Package integrity checks, install directory validation |
| `WizardSync.Tests.ps1` | First-run wizard sync | Config-to-UI synchronization, profile selection |

## Writing Tests

### Mocking Guidelines

All tests must run safely without modifying the live system. Follow these patterns:

**Mock OS/hardware interactions:**
```powershell
Mock Get-Process { return $null }
Mock Test-Path { return $true }
Mock Get-CimInstance { return @() }
```

**Define stub functions for cross-file dependencies:**
```powershell
# In BeforeAll, define stubs for functions that live in other files
function Write-SetupLog { param($text) }
function Log-Always { param($msg) }
function Write-EventLogEntry { param($Message, $EntryType, $EventId) }
```

**Use `$script:ExitRequested` to terminate engine loops cleanly:**
```powershell
# Set inside a mock to prevent infinite loop
Mock Invoke-MixerStop {
    $script:ExitRequested = $true
    return $true
}
```

### Style Rules

- Every test file must start with `#requires -Version 5.1` and a standardized header block.
- Use ASCII characters only in test code (no em-dashes, arrows, or special characters).
- Name `Describe` blocks after the feature or flow being tested.
- Name `It` blocks with clear descriptions of the expected behavior.
- Clean up temporary files in `AfterEach` or `AfterAll` blocks.
