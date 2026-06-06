# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).



---

## [Unreleased]

### Added
- **Install Pre-Flight Validation**: The Install and Uninstall buttons now run a comprehensive set of pre-flight checks before starting any operation. Checks include verifying that the install folder is writable, required XML task templates exist in the package, the background engine script is present, and the selected install mode has a valid template. If any check fails, a clear warning is displayed in the Status panel with actionable guidance, and the operation is halted before any files are modified.
- **Automatic Configuration Backup**: The background engine now creates a timestamped backup copy of `config.json` (e.g., `config.json.backup-20260605-143022`) before applying any automatic schema repairs or default migrations on startup. This provides a rollback safety net in case an auto-fix produces unexpected results.
- **Developer Architecture Guide**: Added `ARCHITECTURE.md` documenting the project layout, module loading order, path resolution strategies across different execution contexts (CLI, EXE, Scheduled Task), and scope boundaries for contributors.

### Improved
- **Forward Compatibility**: Replaced all deprecated `Get-WmiObject` calls with `Get-CimInstance` across the engine and setup modules. `Get-WmiObject` was removed in PowerShell 7 and flagged as deprecated in Windows PowerShell 5.1. This ensures SAMISH remains compatible with future Windows PowerShell updates.
- **CI Automation**: Added GitHub Actions workflows for automated linting (PSScriptAnalyzer) and Pester test execution on every push and pull request. Regressions in code quality are now caught before merge.
- **Startup Resilience**: The configuration schema validator now merges missing default keys (e.g., newly added settings from updates) into the existing config on every engine boot, preventing crashes when upgrading from older versions that lack newer configuration fields.
- **Event Log Diagnostics**: Added Windows Event Log entries for previously silent failure points including configuration load errors, power plan module initialization, tray icon asset loading, and PID file writes. These entries appear in Windows Event Viewer under the SAMISH source, improving troubleshooting when users share diagnostic reports.
- **App Start Reliability**: The application launch sequence (Direct, UWP Alias, Shell, Protocol Handler) now automatically retries once if the first full pass fails to detect a running process, with a brief delay between attempts. This reduces false failures caused by slow-starting applications or system load during wake.
- **Graceful Shutdown Reliability**: The graceful shutdown message sequence (WM_QUERYENDSESSION + WM_ENDSESSION) now retries once before falling back to a Classic force-close, reducing unnecessary force-kills on applications that are slow to respond to window messages.

---

## [1.3.3] - 2026-06-05

### Added
- **State-Aware Media Control**: SAMISH now checks the current SMTC playback status before sending any Play or Pause command to a monitored application. If the app is already in the requested state (e.g., already paused before sleep, or already playing after wake), the command is skipped. This prevents accidental toggling on media applications that implement Play and Pause as a single toggle action. The improvement automatically applies to Smart Restore, Keep App Open (Media Control), and Monitor & Auto-Relaunch crash recovery.
- **Independent Per-App Auto-Relaunch**: The Monitor & Auto-Relaunch feature for individual automated apps now works independently of the main mixer "Auto-restart mixer if it crashes" checkbox. Previously, disabling the global auto-restart also silently prevented all per-app crash recovery from functioning.
- **Smart Restore Enforced Pause**: When an automated app's On Wake Action is set to Smart Restore and the app was paused before sleep, SAMISH now sends an explicit Pause command on wake. This prevents applications that auto-resume playback on launch (such as Spotify) from overriding the saved pre-sleep state.
- **Engine Auto-Recovery Watchdog**: The SAMISH background engine now automatically restarts within 2 minutes if its process is killed externally (e.g., by Task Manager or system memory pressure). The engine also includes an internal self-healing wrapper that catches and recovers from unhandled exceptions with exponential backoff, without the process needing to restart.
- **Engine Heartbeat PID Logging**: The periodic engine heartbeat log entry now includes the process ID (PID) for easier identification when multiple PowerShell instances are running.

### Fixed
- **Engine Process Detection**: Fixed a bug where the Setup UI incorrectly reported "Installed but not currently running" even though the engine was running normally. Windows CIM cannot read the command line of processes launched by Task Scheduler with elevated privileges, causing the process detection to fail. SAMISH now writes a PID file on engine startup and falls back to it when CIM-based detection returns no results.
- **UI Label**: Corrected the "Monitor & Auto-Relaunch" checkbox label, which was rendering with an underscore character ("Monitor _Auto-Relaunch") due to a Windows Forms mnemonic shortcut character being incorrectly parsed.
- **Keep Closed Diagnostics Button**: The "Test Wake/Resume" button in the Diagnostics tab now respects the Keep Closed wake action. When an app is configured to Keep Closed, the button appears visually greyed out with a context-aware tooltip identifying the app by name and skips launching on click. The button styling now updates immediately when the On Wake Action dropdown is changed.
- **UWP App Background Process Detection**: Improved process detection for Spotify and other UWP/Store applications that keep background worker processes alive after the user closes the main window. SAMISH now checks for a visible window handle rather than just a matching process name. This fixes two issues: the Diagnostics tooltip incorrectly reporting the app as "running" when only background workers are present, and the Monitor & Auto-Relaunch feature failing to detect that the app's UI has been closed.
- **Operating Mode Test Accuracy**: The "Test Wake/Resume" and "Test Sleep/Hibernate" buttons now accurately mirror SAMISH's real automated behavior. The Test Sleep button captures the app's current playback state before pausing or closing, and the Test Wake button uses that captured state to dispatch the correct media action based on the configured On Wake Action (Smart Restore, Always Play, Always Pause, or Reopen Only). Previously, the test always assumed playback should resume regardless of settings.

---

## [1.3.2] - 2026-06-03

### Added
- **Logger Module**: Unified logging operations (`Rotate-LogFileIfNeeded`, `Resolve-SamishLogPath`, `Write-EventLogEntry`) into a shared `Logger.psm1` module, eliminating duplicate implementations across the Setup UI and background engine.
- **Theme-Aware Live Log Console**: The live log view now respects the active UI theme, using the correct palette colors instead of a fixed dark background regardless of theme state.
- **`Apply-SamishTheme` API**: New convenience function for applying the active theme to dynamically spawned modal dialogs (Audio Device picker, Game Mode settings) with a single call.
- **Pester Test Coverage Expansion**: Added `Logger.Tests.ps1` (7 tests) and `FailStates.Tests.ps1` (4 tests) covering log path resolution, file rotation, event log resilience, config corruption, and mixer stop failure states. Total test suite now at 48 tests, all passing.
- **Developer Documentation**: Relocated technical reference materials from the GUI to `USER_GUIDE.md` and added `docs/Create-An-Adapter.md` and `docs/Community_Response_Template.md` to support community contributions.
- **Configuration Auto-Repair**: Upgraded the background engine to detect and automatically repair corrupted `config.json` files (e.g. malformed JSON syntax, invalid data types). Repairs are written atomically to prevent mid-write power-loss corruption.

### Changed
- **Mixer Stop Resilience**: Strengthened the `Invoke-MixerStop` background routine with fail-forward error handling. If a third-party mixer adapter throws an exception or fails, the engine now logs the error and gracefully continues, guaranteeing the system sleep routine is never blocked.
- **Boot Trace Logger Reorder**: Moved the `Write-SamishSetupTrace` function definition to execute before its first call site, ensuring early boot errors (such as AppUserModelID registration failures) are properly logged instead of silently discarded.

## [1.3.1] - 2026-06-03

### Added
- **Diagnostic Report Zipper**: Added a "Submit Diagnostic Report" button in the Advanced Tools slide-out drawer (Full mode only) that compiles a troubleshooting package including settings (`config.json`), backup configuration (`powerplan_backup.json`), active log files (`samish_*.log`), and system power states (`powercfg` reports). The collected files are sanitized of sensitive personal information (such as local username, computer name, and IP addresses) and saved as a ZIP archive on the Desktop, while opening the default web browser to the GitHub issue page.
- **GitHub Diagnostic Issue Template**: Created a standard diagnostic report issue template (`.github/ISSUE_TEMPLATE/diagnostic_report.md`) to guide users submitting sleep/wake issues on GitHub.

## [1.3.0] - 2026-06-02

### Added
- **Game Mode Guard**: New module (`GameModeGuard.ps1`) detects when a user is running a full-screen game or any process in a configurable `GameModeList`. When active, the SAMISH engine skips non-essential diagnostics and sleep interventions to avoid performance impact during gameplay. Controlled by `GameModeEnabled` (bool) and `GameModeList` (array) config keys.
- **First-Run Wizard**: New guided first-launch wizard (`FirstRunWizard.ps1`) walks new users through 3 setup questions: detect and manage running mixer software, detect common browsers for media pause, and UI mode selection (Simple vs Full). Includes a "Skip Wizard" option that closes and opens in Full mode. Persists answers to `config.json` and sets `WizardCompleted = true`.
- **Audio Endpoint Management**: New module (`AudioEndpoint.ps1`) gets and sets the default Windows audio playback and communications devices using the MMDevice COM API (PolicyConfigClient). Enables the engine to restore preferred audio endpoints after a sleep/wake cycle. Config keys: `PreferredPlaybackDeviceGuid`, `PreferredPlaybackDeviceName`, `PreferredCommDeviceGuid`, `PreferredCommDeviceName`.
- **Audio Endpoint GUI**: Added a "Set Preferred Audio Device" button to the Advanced Tools slide-out panel (Full mode only) that opens a modal dialog. The dialog allows users to view current settings, capture active Windows default playback and communications devices with a single click, select endpoints from COM-enumerated dropdown lists, or clear configured preferred devices with confirmation. Fully supports custom high-contrast dark theme styling and DPI scaling.
- **Game Mode GUI**: Added a "Game Mode Settings" button to the Advanced Tools slide-out panel (Full mode only) that opens a modal dialog. The dialog allows users to toggle Game-Mode Guard, view the monitored process list, add processes (with automatic `.exe` extension stripping), remove processes, and automatically detect running games from a curated list of popular launchers and games. Fully styled with theme support and high-DPI scaling.
- **Configuration Documentation**: New `README_Config.md` documenting all config.json keys, their types, valid values, and defaults.
- **JSON Schema Validation**: Added `Test-ConfigSchema` function (215 lines) to `ConfigBackup.Module.ps1` covering 22 config keys with type, range, and enum validation. Includes `-AutoFix` switch for silent repair, loose type coercion (`0`/`1` to bool, `"true"`/`"false"` to bool), unknown key detection, and legacy `UI_Mode` migration (`Basic` to `Simple`, `Normal`/`Advanced` to `Full`). Wired into boot path: validate, auto-fix, merge defaults, persist if changed.
- **PowerShell Module Conversion**: Converted `GameModeGuard.ps1` and `AudioEndpoint.ps1` to proper `.psm1` modules with `Export-ModuleMember` for clean function boundaries. Engine updated to `Import-Module .psm1` with `.ps1` fallback for compatibility.
- **Engine Integration**: Wired Game Mode Guard check into the main SAMISH engine loop with explicit parameter passing. Audio endpoint restore integrated into the wake recovery sequence.
- **Simple / Full UI Mode Switcher**: Added a dropdown in the footer area to toggle between a streamlined single-column "Simple" mode (install-only controls) and the full two-column layout. Simple mode hides diagnostics, advanced tools, and secondary settings to reduce visual complexity for basic setup tasks.
- **Telemetry Tab Selection Persistence**: Switching between the System Telemetry and Hardware Telemetry sub-tabs now preserves the previously selected list item. The action button dynamically re-evaluates and reflects the correct action text for any persisted selection (e.g., "Disable Wake", "Toggle Suspend", "Disable Timer") instead of resetting.
- **Empty-Space Deselection**: Clicking empty space (below list items) in the SAMISH Automated Apps listbox now clears the selection, properly disabling the "Deactivate Automation" and "Open Installation Folder" buttons.
- **Custom Theme Configuration**: Added a dedicated `Configure-ColorTheme.ps1` utility script and `Launch-ColorThemeConfigurator.bat` shortcut to allow users to easily customize the UI color palette, reset to original defaults, or restore a previously saved custom theme from backup.

### Changed
- **Workspace Cleanup**: Moved internal development scripts and tools into `build-tools\agent-scripts\` to keep the root directory clean for end users.
- **Documentation Images**: Updated README screenshots to prominently feature the new Simple Mode layout alongside the Full Mode interface.
- **Footer Layout**: Moved the "View:" label before the Simple/Full dropdown (previously appeared after). The dropdown and label now maintain the same position in both Simple and Full modes. In Simple mode, the version number and creator credit are stacked on two lines (right-aligned) instead of a single line.
- **App Override Settings Disabled Title**: The "App Override Settings" GroupBox title now uses a visually distinct dimmed color when disabled, instead of the same bright color used when enabled.
- **Config Defaults**: Updated `UI_Mode` default from `"Normal"` to `"Full"` and `Merge-ConfigDefaults` to match the 2-mode system.

## [1.2.5] - 2026-05-29

### Added
- **Application Auto-Recovery**: Implemented background crash monitoring and automatic recovery for both the main mixer software and targeted automated applications.
- **Opt-in Recovery Controls**: Added settings to enable recovery globally (General Settings) and per-application (App Override Settings).
- **Direct Event Log Diagnostics**: Integrated direct querying and XML parsing of Windows System Event Logs. SAMISH now retrieves traditional S3 sleep/wake states (Event IDs 42 and 1) alongside modern S0 standby cycles (Event IDs 506 and 507).
- **Modern Standby Wake Source Decoding**: Automatically maps Modern Standby exit codes (`ExitReason`) to human-readable text and extracts scheduled wake tasks or owner details for rich sleep/wake telemetry.
- **Dynamic Context-Aware Tooltips**: Added reactive, context-sensitive tooltips for the telemetry action button. The tooltip text dynamically adjusts based on the selected target (Disable Wake, Toggle Suspend, or Disable Timer) and details the creation of a restorable configuration backup.

### Changed
- **UI Button Text Update**: Renamed the "Remove from Automation" button in the Automated Apps panel to "Deactivate Automation" to prevent text clipping.
- **Background Active Blocker Monitoring**: Increased active blocker background polling frequency from 30 seconds to 10 seconds. Refactored the update cycle to run completely silently and check for list item array differences before updating listboxes, eliminating screen flickering and performance overhead.

### Fixed
- **Responsiveness on Tests**: Resolved UI freezes during sleep/wake test actions by adopting non-blocking event loops instead of synchronous sleeps.
- **Immediate Config Sync**: Configured the background recovery loop to dynamically reload changes in the application configuration.
- **UI Drawing & Color Exceptions**: Fixed an unhandled drawing exception where the panel border and combobox dropdowns crashed on startup under specific configuration environments.
- **UI Formatting Warning**: Removed a minor warning caused by an undefined formatting variable in the GroupBox layout loop.
- **Stray Startup Index Output**: Fixed a bug where dynamic font and image objects appended to the GDI resource garbage collection list (`ArrayList.Add()`) leaked array index integers to the pipeline. These integers were inadvertently captured by `ps2exe` and displayed as an empty `0` MessageBox before the Setup GUI launched.
- **Event Log Query Fail-Forward Grace**: Wrapped all WinEvent log queries, list updates, and tooltip UI updates in try/catch blocks. The app handles the errors gracefully to ensure setup loads without interruption.

## [1.2.4] - 2026-05-27

### Added
- **Try/Catch Block C# Compiler Logging**: Wrapped the inline `Add-Type` compilations in `Setup.ps1` and `SAMISH.ps1` in try/catch blocks. If a strict Windows environment or security policy blocks dynamic compilation, the setup hider, AppUserModelID, Power Interceptor, and hotkey systems fail gracefully and output full diagnostic details to `samish.log` and the Windows Application Event Log rather than failing silently or causing script crashes.

### Changed
- **Dynamic Sleep Delay Polling**: Optimized graceful stop sequences by replacing the static `Start-Sleep` delay with a dynamic, low-impact 50ms polling loop that queries `MainWindowHandle` and process exit state. Graceful closures now complete immediately once the process UI handles disappear, accelerating sleep transitions.

### Fixed
- **UI Configuration Sync and State Lock**: Fixed a bug where checking/unchecking the "Enable Logging" or "Enable Hotkey Toggle" checkboxes did not dynamically enable/disable their respective configuration dropdowns and textboxes. Added event listeners and startup synchronization so that the active state of logging and hotkey parameters always accurately reflects the saved `config.json` values and interactive toggles.
- **Stray Startup Output '0' Box**: Cast `SetCurrentProcessExplicitAppUserModelID` API call to `[void]` in `Setup.ps1` to prevent outputting `0` to the stdout pipeline, resolving the empty message box shown by `ps2exe` on startup.
- **SFX Configuration Corruption**: Relocated `rcedit` branding operations in `build.ps1` to run on a temporary copy of the SFX stub prior to file concatenation. This preserves the 7-Zip configuration and archive overlay payload at the end of the executable, resolving the `Could not read SFX configuration` crash.

## [1.2.3] - 2026-05-26

### Added
- **Drawer State Persistence on Tab Switch**: Automatically opens the corresponding slide-out drawer when switching between the Setup and Sleep Automation tabs if a drawer was already expanded on the previous tab.
- **Flat Dropdown Simulated-Disabled Borders**: Configured both the "On Wake/Resume" (`ddOnWakeAction`) and "Operating Mode Tests" (`ddTestTarget`) dropdowns to remain physically `Enabled = $true` to prevent the OS from altering their flat border thickness when inactive. They now utilize a custom simulated-disabled state with color styling and user-input interception (restoring index to 0 when inactive).
- **Wake Dropdown State Reset**: Configured the "On Wake/Resume" dropdown to automatically clear its option items and reset back to a single `"- Select App -"` placeholder when no app is selected in the automated list.
- **Ignored Blockers Selection Sync**: Added explicit list state reset (`Set-OperatingModeBoxState -Enabled $false`) when selecting an item in the Ignored Blockers list (`listOverrides`), clearing the App Override Settings panel.
- **Popularity-Based Profile Ordering**: Added dynamic profile list sorting prioritizing BEACN at the top, then custom user-defined profiles, followed by major brands in order of popularity (Voicemeeter, GoXLR, WaveLink), and the developer test profiles at the bottom.

### Fixed
- **Wake Dropdown Active Enablement**: Fixed a bug where the "On Wake/Resume" dropdown remained physically disabled after selecting an automated app.
- **Themed Test Box Title Color**: Fixed the "Operating Mode Tests" GroupBox title color resetting to system default dark text (ControlText) after finishing its flash sequence or when disabled. It now resolves correctly to the themed color.
- **High-DPI Profile Details Coordinate Lock**: Wrapped the dynamic positioning of the profile details labels in a startup-only check (`$script:ProfileDetailsInitialized`). This preserves the perfectly scaled layout coordinates at startup, resolving overlapping text and clipping on selecting a profile.
- **Device Settings Checkbox Clipping**: Widened `$profilesPanel` to height `79` to prevent the third bubble checkbox (`Demo Device`) from being clipped, and moved `$detailsPanel` to `Y=96` with height `86` to maintain clean, proportional layout bounds.

## [1.2.2] - 2026-05-24

### Added
- **Tab Underline Navigation**: Implemented a unified borderless tab navigation system across all tab controls (main navigation, nested telemetry details, and advanced tools sub-tabs) using sliding/resizing 2px `$BrandPurple` underline indicators.
- **Action Button Outline Style & Hovers**: Redesigned primary action buttons (like `$btnInstall` with bold text) and secondary buttons to use an outline-only flat style. Added a custom border hover hook that transitions button borders to `$BrandCyan` (Brandblue) and applies a soft gray background fill (`FromArgb(230, 230, 230)`) while keeping text color static to avoid flashing.
- **Unified Read-Only lavender-gray background**: Styled all read-only display controls (`statusBox`, `listBlockers`, `listOverrides`, `listAutomated`, `txtLastWake`, `txtWakeTimers`, and `listArmedDevices`) with a soft lavender-gray background (`FromArgb(245, 245, 250)`) to cleanly separate editable inputs from informational outputs.
- **Context-Aware Diagnostics Test Tooltips**: Implemented dynamic, state-aware tooltips for the four test buttons in the **Operating Mode Tests** panel (`Test Sleep/Hibernate`, `Test Wake/Resume`, `Test Graceful Close`, and `Test Force Close`) on Page 2 (Diagnostics). Tooltips now prepend the current target's status (e.g., `[Available - Target is running]`, `[Unavailable - Target is not running]`) and append context-specific warnings or launch instructions (e.g., warning the user about unsaved work before closing, or displaying the executable path that will be used for launch).
- **Persistent Enablement for Tooltip Access**: Configured the four test buttons to remain enabled at all times instead of using WinForms `.Enabled = $false` (which completely disables hover events and hides tooltips in Windows). The click handlers now perform runtime state verification and alert the user via the Status box if an action cannot be run (e.g., trying to stop a process that is not running).
- **Scan Label Color Persistence Exclusion**: Excluded the `lblDiagDetail` status label at the bottom of Page 2 (Diagnostics) from the recursive form styling reset function `Reset-MainFormChildControls`. Previously, the reset loop overwrote the label's `ForeColor` from `DimGray` (light gray) to the default `ControlText` (black) on startup. Setting the control's `.Name = "lblDiagDetail"` and adding it to the exclusion check ensures it maintains its light gray resting color.
- **Dedicated Textbox Name Identifiers**: Added explicit `.Name` assignments for the main setup status box (`statusBox`), telemetry wake source textbox (`txtLastWake`), and wake timers textbox (`txtWakeTimers`) so they are correctly identified and skipped during child control layout resets.
- **Tri-List Selection Sync**: Added synchronized selection behavior across the Active Blockers, Ignored Blockers, and Automated Apps lists. Selecting an item in one list clears selections in the others, ensuring context-specific actions (like "Remove from Automation" and "Open Installation Folder") are only enabled when appropriate.
- **Blocker Discovery Tip & Tooltip**: Updated the blocker hint label text to `"Tip: To discover and automate..."` and added a comprehensive step-by-step hover tooltip explaining how to open media apps, play audio to register wake-locks, scan, and automate them.
- **Device Profile Tooltips**: Added detailed hover tooltips for BEACN and Demo Device profiles in the Device Settings panel. The BEACN tooltip guides users through the recommended configuration path, and the Demo Device tooltip outlines its use as a simulated test bed and developer template for custom modules.

### Changed
- **General Settings Grid Alignment**: Shifted custom logging (`tbLogCustom`) and custom hotkey (`tbCustomKey`) textboxes to X=230 and widened them to 75px, removed the redundant `Custom:` label (`lblCustomKey`), and moved the logging seconds label (`lblLogCustom`) to X=310.
- **GroupBox Renaming**: Renamed the bottom-middle Operating Mode GroupBox on Page 2 to `"App Override Settings"` to clarify its function.
- **Live Log Dark Accent Color**: Shifted the real-time background console color of the live log console (`txtLiveLog`) to a modern, slate-gray dark background (`FromArgb(40, 44, 52)`) with a cyan text foreground.
- **System Sleep & Wake Analysis & Grid Layout Alignment**:
  - **Grid Alignment (Horizontal & Vertical)**: Enforced a completely unified grid system across both pages. Both columns now use a width of **`370px`** separated by a **`15px` gutter gap** (Left Column: `X = 10..380`; Right/Middle Column: `X = 395..765`). This stabilizes the interface and prevents horizontal layout jump when toggling between tabs.
  - **Bottom Action Button & Spacing Unification**: Resolved sizing and spacing inconsistencies of bottom button rows. Expanded Page 1's `$btnInstall` and `$btnUninstall` and Page 2's `$btnDiagScan` and `$btnDiagIgnore` to span the full width of the left/diagnostics column (`X = 10..380`), unified the horizontal gap between adjacent buttons on both pages to exactly **`10px`**, and widened Page 1's `$btnToolsAdvanced` to `370px` (shifting its location to `X = 395`) to align perfectly with the Status box and Page 2's diagnostics button.
  - **Pop-out Drawer Gutter Alignment**: Aligned the visual boundaries of the pop-out drawers on both pages. Shifted the Page 2 drawer child GroupBoxes (`grpTest` and `grpTelemetry`) from relative `X=10` to relative `X=0` (absolute `X=790`) and expanded their widths to `360px` (absolute `X=1150`). This makes the drawer borders line up perfectly with Page 1's `$grpAdvancedTools` drawer border.
  - **Symmetric Vertical Separator Lines**: Extended the bottom of the brand color vertical separator lines (`toolsDrawerSep` on Page 1, `diagDrawerSep` on Page 2) from ending flush with the bottom of the main content column to ending at `Y=453` (7px below the bottom edge of the bottom action buttons). This matches the visual overhang of the lines at the top (`Y=10`, which is 7px above the top border of the GroupBoxes) for perfect top/bottom visual symmetry.
  - **Page 1 (Setup)**: Shrunk `$deviceGroup` height to 180px and shifted `$detailsPanel` up to Y=90, aligning the bottom boundary with `$opGroup` at Y=190. Shifted `$statusGroup` up to Y=200 and expanded `$statusBox` to 160px in height, allowing 2 additional lines of setup activity logs to be visible and establishing a clean horizontal grid split at Y=190/200.
  - **Page 2 (Diagnostics)**: Expanded `$grpAutomated` height to 200px to enlarge the automated apps list box to 130px (displaying more apps without scrolling), and aligned its bottom boundary with `$grpBlockers` at Y=210. Shifted `$grpOperatingMode` to Y=220, shrinking its height to 175px, and compressed its wake options (Y=118 and Y=138) to fit perfectly. Widened Left column panels to `370px` (making list boxes and buttons `350px`) and shifted Middle column panels to `370px` wide.
  - **Telemetry Box & Control Refinements**: Shrunk `$grpTest` to 150px (shifting test buttons to Y=60 and Y=105), shifted `$grpTelemetry` up to Y=160, and expanded its height to 225px. Shifted child controls to match the new 360px width: dropdown and textbox widths increased to 330px, test button widths increased to 158px (shifting right-hand buttons to relative X=187), and tab page contents widened to 312px. Centered the bottom telemetry refresh button at relative X=15 and shrunk it to 330px to align visually with the inputs inside the GroupBoxes above.
- **Scan Status Wording**: Changed the scan completion status line text from `"Scan complete - HH:mm:ss."` to `"Last scan completed at HH:mm:ss."` for a more descriptive and professional user interface presentation.
- **DPI-Safe Tooltip Wrapping Sync**: Verified and ensured that the newly added dynamic status descriptions fully integrate with the tooltip word-wrapping proxy to prevent truncation or overflow on high-DPI scaling configurations.

### Fixed
- **Diagnostics Selection State Bug**: Fixed a bug where buttons (e.g. "Remove from Automation") and description labels remained enabled when shifting selections between list boxes. The selection mutex now only wraps the list clearing operations, allowing state and layout updates to run unconditionally on selection change.
- **System Overrides Parsing Bug**: Fixed a parsing bug where power request overrides containing spaces (e.g., `"BECAN Mic"`, `"Legacy Kernel Caller"`, `"USB Audio 2.0"`) had their names truncated to the first word and requests corrupted. Refactored the parser to use a right-to-left scanning strategy, ensuring name tokens and request keywords are correctly separated.
- **Active Blockers Filtering**: Filtered out already-automated idle apps from the discovered Active Blockers list to prevent visual clutter and redundant UI prompts.

## [1.2.1] - 2026-05-23

### Added
- **Dynamic Tooltip Word-Wrapping (DPI & Resolution Safety)**: Added a helper function (`Format-WrappedText`) and wrapped the global `$tooltip` control with a dynamic proxy that automatically wraps all tooltips to a maximum of 70 characters per line. This prevents text truncation and layout overflow on high-DPI scaling configurations and lower resolution screens.
- **Completed missing tooltips**:
  - Added descriptive tooltips to the Setup and Diagnostics main tab buttons.
  - Added tooltips to the Advanced Tools & Utilities group box, the Tools sub-tab, and the Live Log sub-tab.
  - Restored the detailed Uninstall button tooltip to clarify configuration preservation.
  - Added group box tooltips for all group boxes currently missing them (Active Blockers, Ignored Blockers, Automated Apps, Operating Mode, Operating Mode Tests, and System Sleep & Wake Analysis).
  - Added tooltips for internal telemetry diagnostics (Supported Sleep States, Last Wake Source, Active Wake Timers, and Armed Devices).
  - Added tooltips for the version metadata label, "Remove System Override" button, and "Refresh Telemetry" button.
- **Interactive Version Footer**: Configured the version footer label in the lower-right corner to open `CHANGELOG.md` on double-click. Removed the Notepad fallback option and added robust PowerShell log events to track if the file is successfully located and launched.
- **Live Log Visual Accent**: Added a SAMISH purple accent line under the Tools and Live Log tab buttons when the Live Log view is active to underline the log terminal.

### Changed
- **Symmetric Layout Alignments**:
  - Re-aligned the bottom edge of the Live Log control buttons (Pause, Copy, Clear) with the bottom edge of the status text box.
  - Symmetrized Page 2 layout panels, increasing the height of the automated apps list box to 105 and aligning the Y-coordinates of automated action buttons and test control buttons to 134.
  - Lowered the On Wake dropdown label to Y=141 and dropdown to Y=166, aligning all bottom boundaries perfectly on relative Y=190.
- **PS2EXE Compatibility Path Resolution**: Fixed a path resolution bug in `Setup.ps1` where `$MyInvocation.MyCommand.Definition` was used to resolve the script root directory. This property returns the raw script body when running inside a PS2EXE wrapper, throwing a fatal path exception and causing compiled EXEs to hang or fail on start. Replaced it with robust fallbacks (`$PSScriptRoot`, `$PSCommandPath`, and AppDomain base directory).
- **Cleaned Misplaced Tray Logic in Setup UI**: Removed an incorrectly merged tray icon setup block and premature `$btnCleanReset.Enabled` assignments from the body of the `Get-HighQualityScaledImage` helper function in [Modules/UI.ps1](file:///c:/Scripts/GOOGLE-ANTI-GRAVITY/SAMISH/Modules/UI.ps1). The premature assignment threw a property-on-null exception on startup (since the button was not yet defined), which aborted UI initialization and caused compiled EXEs to hang without showing their window. The clean reset button initialization has been relocated to execute safely at the end of the file.

## [1.1.0] - 2026-05-23

### Added
- **Unified Two-Tabbed Dashboard Layout**: Replaced the separate installer and diagnostics windows with a single, borderless TabControl. Redesigned both pages into efficient 2-column configurations, reducing vertical height to 640px to resolve the vertical cut-off bug on 1080p scaled screens.
- **Symmetric Slide-Out Drawers**: Added expandable slide-out panels (expanding window from 800px to 1180px) containing Advanced Tools on Page 1 and Sleep/Wake Telemetry diagnostics on Page 2.
- **Drawer-Based Live Log Console**: Relocated the real-time Live Log streaming monitor to a dedicated tall console in the Page 1 drawer (featuring Pause, Copy, Clear, and Exit controls), resolving word-wrapping issues.
- **Advanced System Sleep Telemetry**: Gathers and displays system-wide sleep configurations, parsed last wake source (`powercfg /lastwake`), active wake timers (`powercfg /waketimers`), and armed devices (`powercfg /devicequery wake_armed`) asynchronously.
- **Unified Terminology & User-Friendly Button Labels**: Renamed legacy buttons to clearer actions (e.g. "Restart SAMISH Service", "Verify Power Plan", "Test Sleep/Hibernate", "Remove System Override").
- **Resource Management Improvements**: Automatically closes active timers and background runspaces on tab switches, drawer collapse, or app exit.

## [1.0.10] - 2026-05-23

### Changed
- **Non-Blocking Tray/Hotkey Toggle**: Removed the strict 1-second rate limit on toggle actions, allowing state toggles, tray icon swaps, and context menu updates to occur instantly.
- **Debounced Notifications & Event Logs**: Deferred heavy blocking IPC operations (ShowBalloonTip notifications and Windows Event Log writes) to a debounced queue that only fires after 800ms of toggle inactivity, preventing thread locking.
- **Cached Hotkey Label**: Cached the tray context menu hotkey suffix at startup to avoid repeated assembly load overhead on toggle actions.
- **Real-Time UI Operating Mode Sync**: Linked event handlers to the main screen's Operating Mode radio buttons to immediately update the in-memory `$script:OperatingMode` state when changed.
- **Dynamic App Mode Tags**: Configured the automated apps list box to display active/inherited mode tags in a clean, hyphenated `[Before Sleep - On Wake]` format (e.g. `[Keep App Open - Smart]`), dynamically recalculating and updating the list items in real-time when any global or app-specific operating mode options are toggled.
- **Renamed Media Mode Display Label**: Replaced `"Pause Media"` or `"PauseMedia"` display strings with `"Keep App Open"` inside the automated apps list box and diagnostics detail label to match the text on the corresponding radio buttons.
- **Immediate Test Target Resolution**: Updated the test target resolution routine to query the active UI operating mode selection directly, ensuring "Stop Test" and "Start Test" run behavior matches the current on-screen radio states immediately without needing to save to disk or reinstall first.

## [1.0.9] - 2026-05-23

### Added
- **Hotkey & Tray Action Debouncing**: Added a 1-second rate-limiting (debounce) check inside the helper toggle logic to prevent background thread hangs and tray icon freezes caused by rapid, repeated hotkey presses or menu clicks flooding the Windows Explorer and Event Log IPC channels.
- **Tray Menu Hotkey Display**: Added the active hotkey label (e.g., `ScrollLock` or custom key name like `F8`) next to the "Enable/Disable helper" option in the system tray context menu for better user visibility.

## [1.0.8] - 2026-05-23

### Added
- **Hotkey & Tray Settings Foreground Focus**: Added an "Open Settings" option to the system tray context menu. Implemented robust window handle retrieval and focus logic using Win32 API calls (`FindWindow`, `ShowWindow`, and a `SetWindowPos` topmost bypass) to automatically restore and bring the existing Setup window to the foreground, preventing multiple overlapping instances.
- **Uninstall Tooltip Clarity**: Updated the Uninstall button tooltip in the Setup UI to clearly communicate that user profiles and configuration settings can be preserved and automatically reapplied upon reinstalling.

## [1.0.7] - 2026-05-22

### Added
- **Active Sleep Blocker Verification**: Implemented active power request parsing (`powercfg /requests` and `powercfg /requestsoverride`) in the background engine to prevent mixer shutdown during web meetings (e.g. Google Meet, Zoom, Teams) when the system is kept awake by active display or system requests.
- **Reliable Media Playback Restoration**: Added a robust 15-second polling and confirmation loop (retrying every 250ms) to ensure media resumes successfully after wake, with early exit checks on process termination/crashes.
- **Smart Restore Diagnostics Info**: Added context-aware messages and double-line status spacing to warn users about the ad-hoc pre-sleep playback state assumption when running tests in the UI.

## [1.0.6] - 2026-05-22

### Added
- **Per-App Media Playback Control**: Replaced the global wake checkbox with per-app controls: Before Sleep (Graceful, Classic, Pause Media Only) and On Wake Action (Smart Restore, Always Play, Always Pause, Keep Closed, Reopen Only).
- **Smart Media App Discovery**: Enhanced background blocker scans to detect and list running browser and media apps in SAMISH Blue at the bottom of the active blocker list, even when they are not actively blocking sleep.
- **WinRT SMTC Integration**: Implemented reflection-based Windows System Media Transport Controls (SMTC) commands to pause playback before sleep and restore it upon waking based on configured preferences.
- **Multi-Threaded GUI Isolation**: Moved sleep diagnostics and file discovery scans off the main WinForms thread and into asynchronous background PowerShell Runspaces, resolving UI freeze/hang conditions.
- **Windows Event Log Integration**: Registered `SAMISH` as a Windows Application Event Log source and integrated structured Event IDs (100-201) to log service startup, shutdown, and process actions.
- **GDI Resource Leak Protection**: Implemented tracking and disposal routines for GDI fonts, icons, and brushes used in the UI modules, preventing handles and memory exhaustion.
- **Automatic Log Rotation**: Configured setup and background logs to automatically rotate and archive when file size exceeds 5MB.
- **Atomic Configuration Writes**: Added a safe write-and-swap utility (`Save-ContentAtomic`) to prevent corruption of `config.json` in the event of sudden power-offs or crashes.
- **Dynamic UWP Path Resolution**: Implemented dynamic path lookup via local UWP execution aliases (`%LOCALAPPDATA%\Microsoft\WindowsApps`) to prevent startup failures when Windows Store updates change versioned app folders.
- **Type-Safe Result Schemas**: Standardised internal APIs with strict PowerShell classes (`AppStartResult`, `AppStopResult`, `AppExecutablePathResult`) to eliminate runtime parsing errors.

## [1.0.5] - 2026-05-22

### Added
- **Operating Mode Tests**: Added an "Operating Mode Tests" group box to the Setup UI, placed directly below the Install Mode and Operating Mode configuration boxes. Users can now manually trigger a Graceful stop, Classic stop, or Start against their selected device software or any app configured in Sleep and Hibernate Diagnostics, without waiting for sleep to trigger automatically. The box is greyed out (with tooltip visible) until SAMISH is installed, the device software is running, or automated apps are configured. Results are reported to the Status box with full detail.
- **Robust App Startup and Tracing**: Redesigned the application startup mechanism (`Invoke-AppStart`) to support a multi-stage launch fallback chain. It now aligns the working directory, executes local UWP aliases, uses shell execution, and falls back to protocol handlers. Added active process verification (polling the process list for up to 3 seconds) and detailed diagnostic trace reporting in the Status Box on success and failure.

## [1.0.4] - 2026-05-22

### Added
- **Per-App Wake Control**: Added a "Do not restart this app on wake" checkbox in the Sleep Diagnostics Operating Mode settings. This allows users to configure specific automated apps (like a web browser streaming media) to close before sleep but remain closed upon waking, without affecting critical mixer software.

## [1.0.3] - 2026-05-03

### Changed
- Stabilized SAMISH setup and engine operations.
- Resolved GUI initialization issues and character encoding artifacts.
- Optimized engine polling loop to maintain hotkey responsiveness.
- Improved adapter discovery system.
