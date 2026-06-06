# SAMISH Architecture

This document describes the codebase architecture, module loading, and
engineering conventions used throughout the SAMISH project.

## Module Structure

SAMISH has two entry points: `Setup.ps1` (the WinForms installer UI) and
`App/SAMISH.ps1` (the background engine). Both dot-source modules from
`App/Modules/` but load different subsets.

### Engine Loading Chain (SAMISH.ps1)

The background engine runs as a scheduled task and manages sleep/wake cycles:

```
App/SAMISH.ps1
  |-- NativeMethods.ps1          (P/Invoke, Win32 interop)
  |-- UwpMedia.Module.ps1        (SMTC media control)
  |-- ConfigBackup.Module.ps1    (Config merge, schema, backups)
  |-- App.Control.Common.ps1     (Shared engine logic)
  |-- PowerPlan.Read.Common.ps1  (Power plan queries)
  |-- App.Control.Classic.ps1    (Classic stop/start)
  |-- App.Control.Graceful.ps1   (Graceful WM_CLOSE stop)
  |-- GameModeGuard.ps1          (Game Mode detection)
  |-- AudioEndpoint.ps1          (Preferred audio device)
  |-- Logger.psm1                (Shared logging API)
  |-- Adapters/Adapter.*.ps1     (Per-device profile adapters)
```

### Setup UI Loading Chain (Setup.ps1)

The installer UI builds the WinForms dashboard and wires event handlers:

```
Setup.ps1
  |-- NativeMethods.ps1          (P/Invoke, Win32 interop)
  |-- Logger.psm1                (Shared logging API)
  |-- PowerPlan.Read.Common.ps1  (Power plan queries)
  |-- PowerPlan.Module.ps1       (Power plan read/write operations)
  |-- App.Control.Classic.ps1    (Classic stop/start)
  |-- App.Control.Common.ps1     (Shared engine logic)
  |-- App.Control.Graceful.ps1   (Graceful WM_CLOSE stop)
  |-- Diagnostics.Module.ps1     (Diagnostic report generation)
  |-- Install.Engine.ps1         (Task scheduler, setup actions)
  |-- Validation.Module.ps1      (Pre-flight install/uninstall checks)
  |-- Setup.Helpers.ps1          (Logging, dialogs, power plan helpers)
  |-- Task.Helpers.ps1           (Shortcuts, schtasks, process control)
  |-- Diagnostics.Display.ps1    (Diagnostics header, configuration display)
  |-- Config.Helpers.ps1         (Config write, log selection, profiles)
  |-- LiveLog.Module.ps1         (Live log streaming to Status box)
  |-- FirstRunWizard.ps1         (Guided first-run setup wizard)
  |-- UI.ps1                     (Main form layout)
  |   |-- UI.SetupTab.ps1        (Setup tab layout)
  |   |-- UI.DiagTab.ps1         (Diagnostics tab layout)
  |-- Events-handlers.ps1        (Events bootstrapper)
  |   |-- Logic.ps1              (Core engine logic)
  |   |-- Events.Setup.ps1       (Setup tab events)
  |   |-- Events.UI.Effects.ps1  (Custom owner-draw effects)
  |   |-- Events.Diagnostics.ps1 (Diagnostics tab events)
  |-- Theme-Extension.ps1        (Neon theme, custom theme, animations)
  |-- Adapters/Adapter.*.ps1     (Per-device profile adapters)
```

## WinForms Event Handler Convention

SAMISH uses **named functions** for WinForms event handlers instead of inline
scriptblocks. This convention was adopted to allow per-handler
`[SuppressMessage]` attributes for PSScriptAnalyzer's
`PSAvoidAssignmentToAutomaticVariable` rule, which flags `$sender` in
`param($sender, $e)` because `$sender` is a PowerShell automatic variable
in remote sessions.

### Pattern

```powershell
# 1. Define a named handler function with [SuppressMessage]
function Handle-ButtonClick {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidAssignmentToAutomaticVariable', 'sender',
        Justification = 'Standard .NET WinForms event delegate signature')]
    param($sender, $e)
    # Handler logic here
}

# 2. Wire it up via a thin scriptblock wrapper
$button.add_Click({ Handle-ButtonClick @args })
```

### Scope Rules

Handlers defined in **Theme-Extension.ps1** must use the `global:` scope
qualifier (`function global:Handle-*`) because they are called from
scriptblocks created inside `function global:Run-ThemeTakeover`,
`function global:Run-DropAnimation`, and `function global:Set-BrandTheme`.
Timer callbacks from those global functions fire in the global scope chain,
which cannot see script-scoped functions.

Handlers in other modules (Events.Diagnostics.ps1, UI.DiagTab.ps1, etc.) are
plain `function Handle-*` because their call sites are in the script scope,
and dot-sourcing places both the function and the scriptblock in the same scope
chain.

### Why not rename $sender?

`$sender` is the universal .NET convention for event handler parameters. Using
a different name (e.g., `$eventSender`) would:

- Diverge from every .NET and PowerShell WinForms example
- Require remembering a non-standard name
- Still not address the `$e` parameter warnings

The `[SuppressMessage]` approach preserves the standard convention while
explicitly documenting the intent.

## PSScriptAnalyzer Baseline

The project maintains a warning baseline tracked in
`Tests/CodeQuality.Tests.ps1`. As of the initial baseline:

| Metric | Count |
|---|---|
| Errors | 0 |
| Sender (`$sender`) warnings | 0 |
| Total warnings | 21 |

The 21 remaining warnings are:

- **17 PSReviewUnusedParameter** -- Required WinForms delegate parameters
  (`$e`) and adapter interface parameters not yet wired. These are structural
  and cannot be removed without breaking the delegate signature.
- **4 PSUseDeclaredVarsMoreThanAssignments** -- Audited and documented in the
  `$acceptedOrphans` list in `CodeQuality.Tests.ps1`. All are intentional
  (defensive code, documentation variables, or future-use captures).

## Test Suite

Tests live in `Tests/` and use [Pester v5](https://pester.dev/).

| Test File | Purpose |
|---|---|
| CodeQuality.Tests.ps1 | Handler resolution, lint regression guard |
| Config.Tests.ps1 | Config merge, schema validation |
| Diagnostics.Tests.ps1 | Blocker detection, scan logic |
| FailStates.Tests.ps1 | Error handling, fail-forward |
| Integration.Tests.ps1 | Cross-module integration, module loading |
| Logger.Tests.ps1 | Logging module |
| Logic.Tests.ps1 | Core engine logic |
| Setup.Tests.ps1 | Installation, profiles |
| UwpMedia.Tests.ps1 | SMTC media control |
| Validation.Tests.ps1 | Pre-flight validation checks |
| WizardSync.Tests.ps1 | First-run wizard, UI sync |
