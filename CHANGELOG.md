# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.10] (Unreleased)

### Changed
- **Non-Blocking Tray/Hotkey Toggle**: Removed the strict 1-second rate limit on toggle actions, allowing state toggles, tray icon swaps, and context menu updates to occur instantly.
- **Debounced Notifications & Event Logs**: Deferred heavy blocking IPC operations (ShowBalloonTip notifications and Windows Event Log writes) to a debounced queue that only fires after 800ms of toggle inactivity, preventing thread locking.
- **Cached Hotkey Label**: Cached the tray context menu hotkey suffix at startup to avoid repeated assembly load overhead on toggle actions.

## [1.0.9] (2026-05-23)

### Added
- **Hotkey & Tray Action Debouncing**: Added a 1-second rate-limiting (debounce) check inside the helper toggle logic to prevent background thread hangs and tray icon freezes caused by rapid, repeated hotkey presses or menu clicks flooding the Windows Explorer and Event Log IPC channels.
- **Tray Menu Hotkey Display**: Added the active hotkey label (e.g., `ScrollLock` or custom key name like `F8`) next to the "Enable/Disable helper" option in the system tray context menu for better user visibility.

## [1.0.8] (2026-05-23)

### Added
- **Tray Settings Foreground Focus**: Added an "Open Settings" option to the system tray context menu. Implemented robust window handle retrieval and focus logic using Win32 API calls (`FindWindow`, `ShowWindow`, and a `SetWindowPos` topmost bypass) to automatically restore and bring the existing Setup window to the foreground, preventing multiple overlapping instances.
- **Uninstall Tooltip Clarity**: Updated the Uninstall button tooltip in the Setup UI to clearly communicate that user profiles and configuration settings can be preserved and automatically reapplied upon reinstalling.

## [1.0.7] (2026-05-22)

### Added
- **Active Sleep Blocker Verification**: Implemented active power request parsing (`powercfg /requests` and `powercfg /requestsoverride`) in the background engine to prevent mixer shutdown during web meetings (e.g. Google Meet, Zoom, Teams) when the system is kept awake by active display or system requests.
- **Reliable Media Playback Restoration**: Added a robust 15-second polling and confirmation loop (retrying every 250ms) to ensure media resumes successfully after wake, with early exit checks on process termination/crashes.
- **Smart Restore Diagnostics Info**: Added context-aware messages and double-line status spacing to warn users about the ad-hoc pre-sleep playback state assumption when running tests in the UI.

## [1.0.6] (2026-05-22)

### Added
- **Per-App Media Playback Control**: Replaced the global wake checkbox with per-app controls: Before Sleep (Graceful, Classic, Pause Media Only) and On Wake Action (Smart Restore, Always Play, Always Pause, Keep Closed, Reopen Only).
- **Smart Media App Discovery**: Enhanced background blocker scans to detect and list running browser and media apps in SAMIH Blue at the bottom of the active blocker list, even when they are not actively blocking sleep.
- **WinRT SMTC Integration**: Implemented reflection-based Windows System Media Transport Controls (SMTC) commands to pause playback before sleep and restore it upon waking based on configured preferences.
- **Multi-Threaded GUI Isolation**: Moved sleep diagnostics and file discovery scans off the main WinForms thread and into asynchronous background PowerShell Runspaces, resolving UI freeze/hang conditions.
- **Windows Event Log Integration**: Registered `SAMISH` as a Windows Application Event Log source and integrated structured Event IDs (100–201) to log service startup, shutdown, and process actions.
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
