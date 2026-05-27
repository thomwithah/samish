# SAMISH - Technical Plans & Growth Roadmap

This document consolidates all active engineering tasks, architectural roadmaps, code improvement plans, and growth strategies for the SAMISH project.

---

## Part 1: Immediate Technical Implementation Plan (v1.2.4)

These changes target reliability, diagnostic logging, and faster execution loops.

### 1. Robust C# Compilation & Add-Type Error Logging
- **Goal**: Prevent silent failures in strict Windows environments where security policies block the built-in C# compiler (`csc.exe`).
- **Actions**:
  * Wrap all C# compilation blocks (`Add-Type`) in `try/catch` blocks.
  * Write any compilation failures explicitly to the SAMISH log file (`samish.log`) and event log with clear troubleshooting instructions (e.g., advising the user about strict execution policies).
- **Files to Modify**:
  * [SAMISH.ps1](file:///c:/Scripts/GOOGLE-ANTI-GRAVITY/SAMISH/SAMISH.ps1) (compiling `$PowerTypeSig` and `KeyState`).
  * [Setup.ps1](file:///c:/Scripts/GOOGLE-ANTI-GRAVITY/SAMISH/Setup.ps1) (compiling `$AppIDCode`).

### 2. Snappier Wake/Shutdown Delays
- **Goal**: Replace hardcoded delays with dynamic window detection to accelerate execution.
- **Actions**:
  * Refactor `Invoke-AppStopGraceful` in [App.Control.Graceful.ps1](file:///c:/Scripts/GOOGLE-ANTI-GRAVITY/SAMISH/Modules/App.Control.Graceful.ps1).
  * Replace the static `Start-Sleep -Milliseconds $WindowWakeDelayMs` wait block with a dynamic polling loop that queries `MainWindowHandle` at 50ms intervals, proceeding immediately once the window is detected.

### 3. Modularization Strategy
- **Goal**: Keep the codebase maintainable as we scale.
- **Actions**:
  * Group core sub-systems (like hotkey polling, tray icon handling, and logging rotation) into isolated helper modules in the `Modules/` directory.

---

## Part 2: Long-Term Improvement Roadmap (Target 92+)

This section outlines the architectural, layout, and automation enhancements required to elevate SAMISH to a 92+ rating across all core categories.

### 1. Phase 5: Automated Testing with Pester
To establish solid testing, we will build a formal test framework:
- **Directory Structure**: Create a `Tests/` root folder.
- **Unit Tests**:
  * Test configuration serialization and type safety (`config.json`).
  * Verify power plan parsing logic under mocked inputs.
  * Validate UI element constraints and bounds.
- **Integration Tests**:
  * Mock `powercfg` and `schtasks` CLI executions to test adapter behavior.
  * Assert task registration/uninstallation states.
- **Convenience Runner**: Implement `Run-Tests.ps1` to bootstrap Pester, execute all test files, and output standard JUnit reports.

### 2. Category Improvement Plans (Target 92+)

#### Category 1: User Interface & Aesthetics
- **Dynamic Styling**: Replace standard WinForms styles with custom-drawn flat controls and borderless styling.
- **Micro-Transitions**: Implement double-buffering and smooth hover-fade animations for tab transitions.
- **Scale-to-Fit Layouts**: Shift from static layout coordinates to relative flow layout panels.

#### Category 2: Code Robustness & Architecture
- **Module-Based Architecture**: Convert script dot-sourcing into formal PowerShell Script Modules (`.psm1`) with defined exports.
- **MVP Pattern**: Refactor UI event handling to follow the Model-View-Presenter pattern.
- **Schema Validation**: Add JSON schema validation at startup to reject corrupted configs immediately.

#### Category 3: Diagnostics & Telemetry Depth
- **Direct Event Log Parsing**: Parse Event ID 1 (Sleep) and Event ID 42 (Wake) from Windows System logs to read wake history directly.
- **Active Blocking Monitors**: Replace manual blocker scanning with a low-impact background loop that updates active blockers dynamically.
- **Deep Hardware Queries**: Read USB suspension and PCIe link power states via WMI.

#### Category 4: Reliability & Integration Safety
- **Auto-Recovery**: Build crash detection for targeted applications to automatically relaunch them if terminated.
- **Power State Interceptors**: Listen for Windows `WM_POWERBROADCAST` messages directly to preempt sleep transitions.

#### Category 5: DPI & Multi-Resolution Adaptability
- **Dynamic DPI Scaling**: Read monitor DPI scaling via Win32 API (`GetDpiForWindow`) and scale layouts, margins, and fonts proportionally.
- **Custom Tooltip Class**: Replace WinForms ToolTip with custom floating windows to avoid high-DPI scaling clipping.
- **Resolution Auto-Layout**: Auto-collapse drawers when resolution falls below 1080p width.

#### Category 6: Installation, Distribution & AV Avoidance
- **Custom C# Native Launcher**: Replace `ps2exe` with a custom-compiled C# bootstrapper to eliminate the persistent Microsoft Defender false-positive heuristic detections.
- **Automated WDSI Submission**: Finalize and integrate the `submit_wdsi.js` script to automatically submit release binaries to Microsoft for malware analysis/clearance on build.
- **MSI Wrapper**: Wrap distribution folders inside a signed MSI installer with rollback support.
- **Remote Crash Telemetry**: Build opt-in automated log uploads for system errors.

---

## Part 3: Growth & Visibility Strategy

This roadmap details the strategy for driving repository discovery and scaling the user base.

### 1. GitHub Discoverability (SEO)
- **Goal**: Target the symptoms users search for instead of technical tool names.
- **Actions**:
  * [ ] Add GitHub repository topics: `beacn`, `voicemeeter`, `goxlr`, `elgato-wave-link`, `windows-sleep-fix`, `audio-routing`, `sleep-helper`.
  * [ ] Incorporate search query phrases at the top of the README (e.g., *"PC won't sleep with BEACN/Voicemeeter open"*).

### 2. Community Engagement
- **Goal**: Help users troubleshoot sleep lockups in audio communities.
- **Subreddits to Monitor**: `r/beacn`, `r/VoiceMeeter`, `r/Twitch`, `r/obs`, `r/techsupport`.
- **Engagement Strategy**: Focus on educational responses explaining Windows audio wake-locks (`powercfg /requests`), using SAMISH as the open-source solution.

### 3. Visual Demonstration
- **Goal**: Build trust and show the value in three seconds.
- **Actions**:
  * [ ] Create an animated GIF showing the SAMISH interface recovering the audio mixer state in real-time during a sleep test.
  * [ ] Embed the GIF at the very top of the README.

### 4. Adapter Graduation Pipeline (Beta to Stable)
- **Goal**: Graduate profiles to Stable to expand the addressable user base.
- **Graduation Targets**:
  * [ ] **Voicemeeter**: Verify zero routing loss on wake across Standard, Banana, and Potato configurations.
  * [ ] **GoXLR**: Confirm hardware profiles and USB bus reset cycles execute cleanly.
  * [ ] **Wave Link**: Ensure background service restarts reliably on non-admin user accounts.
