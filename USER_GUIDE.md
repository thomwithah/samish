# SAMISH User & Developer Guide

Welcome to the comprehensive guide for **SAMISH (Streaming Audio Mixer Interface Sleep Helper)**. This document is split into two sections: a **User Guide** for installing and operating SAMISH, and a **Developer Guide** explaining the codebase architecture and internal variables.

---

## Part 1: User Guide

### 1. Installation & Setup Options
SAMISH offers multiple installation modes to suit different environments and user preferences:

#### Option A: The Guided First-Run Wizard (Recommended)
When you launch SAMISH for the first time without an existing `config.json` file, it will automatically open the **First-Run Wizard**.
* **Step 1:** Select whether you want SAMISH to manage your audio mixer (e.g., BEACN, GoXLR, Voicemeeter, Wave Link) or run in **Demo/UI Test mode** (choosing "No, do not manage mixer").
* **Step 2:** Select whether you want SAMISH to automatically pause and recover browser-based media players when sleeping.
* **Step 3 (Experience Level):** Select your UI mode:
  * **Simple Mode (Default):** A clean, single-column dashboard that hides advanced telemetry and diagnostics.
  * **Full Mode:** Accesses all telemetry tabs, custom tests, and slide-out advanced tools.
* **Step 4 (Launch & Recovery Settings):** Select how the background task should run:
  * **Hidden Mode (Recommended):** The engine runs silently as a scheduled task in the background without any tray icons or notifications.
  * **Interactive Mode:** The engine runs in your system tray, providing tray menus, bubble notifications, and quick actions.

#### Option B: Silent Command-Line (CLI) Setup
If you want to bypass the graphical interface entirely, you can run one of the included batch files as Administrator:
* **`Install-SAMISH-Hidden.bat`:** Installs SAMISH to run silently in the background (Hidden Mode).
* **`Install-SAMISH-Interactive.bat`:** Installs SAMISH with the system tray icon enabled (Interactive Mode).
* **`Uninstall-SAMISH.bat`:** Completely registers the scheduled tasks, cleans up the registry, and removes the installation directory.

---

### 2. Graphical Interface (GUI) Walkthrough

#### Simple Mode vs. Full Mode
You can toggle between layouts at any time using the **Full View Checkbox** in the footer:
* **Simple Mode:** Collapses the dashboard to a single-column layout, hiding the diagnostics tab, operating mode settings, extra logging/hotkey options, and installer status logs to keep the setup as clean and minimal as possible. Replaces the Advanced Tools drawer button with a direct button to restore settings from backups.
* **Full Mode:** Expands the dashboard into a two-column view, exposing the tab navigation (Setup & Install and Sleep Automation & Diagnostics), full configurations, and the live status log console.

#### Slide-out Advanced Panels
* **Advanced Tools Drawer (Page 1):** Expand this by clicking **Advanced Tools >>** to access a sliding utility panel containing two tabs:
  * **Tools Tab:** Access 8 system and service management options:
    - **Verify & Restore Settings:** Checks active system telemetry and offers to restore previously modified configurations (like wake devices, task wake-timers, background services, or USB selective suspend settings) back to their original defaults from SAMISH backups, followed by verifying your current Windows power plan compatibility.
    - **Open Windows Task Scheduler:** Instantly launches the Windows Task Scheduler to inspect or manage the background service tasks.
    - **Restart SAMISH Service:** Safely restarts the background helper loop while preserving your custom configurations.
    - **Read Setup & Status:** Queries and displays current installation status, configuration details, and active diagnostics status directly in the **Status / Activity** text box.
    - **Open Setup Log:** Opens the main setup text log in your default text editor.
    - **Submit Diagnostic Report:** Compiles, sanitizes, and packages configurations, logs, and powercfg reports into a ZIP archive on your Desktop, opening the GitHub issue page to submit it.
    - **Set Preferred Audio Device:** Capture and persist your default playback and communication endpoints so SAMISH can restore them after wake cycles.
    - **Game Mode Settings:** Configure automated exclusions so SAMISH skips telemetry scans while full-screen games or specific applications are running.
  * **Live Log Tab:** Stream real-time logs directly from the background engine (`samish.log`) to inspect sleep triggers.
* **Diagnostics Drawer (Page 2):** Expand this by clicking **Diagnostics >>** to access real-time system/hardware telemetry, control options, and dry-run tests:
  - **Operating Mode Tests:** Dry-run simulate sleep, wake, graceful close, and force close routines. This allows developers and users to verify that audio mixer software and other target applications close and relaunch correctly, and test how SAMISH will interact with the mixer software or other SAMISH Automated Apps, without needing to put the entire PC to sleep.
  - **System Telemetry Tab:** View your sleep/wake history (last 5 standby cycles) and inspect active wake timers to trace exactly what scheduled tasks, apps, or services are waking or keeping the system awake. If a rogue wake timer is detected, you can take direct action from the UI (such as disabling the timer for scheduled tasks, disabling the service, or stopping the process).
  - **Hardware Telemetry Tab:** Review Windows Kernel data on armed wake-capable devices (like network adapters or input devices) and scan active USB & PCIe power management configurations to diagnose accidental hardware-triggered wake-ups. This tab allows direct corrective control from the UI, letting you disable wake support on specific devices or toggle USB selective suspend settings.

#### Color Theme Configurator
SAMISH includes a standalone color theme utility. You can customize the dashboard palette to match your streaming setup:
1. Run `Launch-ColorThemeConfigurator.bat` from the root directory.
2. Select standard themes (Dark Slate, Deep Purple, Amber Neon) or create your own custom theme by typing in hexadecimal colors.
3. Save changes; the main GUI and modal dialogs will dynamically update to reflect your custom colors. *(Note: Active theme default persistence behavior is subject to modification pending discussion of theme management implementation plans).*

---

## Part 2: Developer Guide

### 1. Codebase Architecture

The codebase is split into modular components to ensure portability and high testability:

```
c:\Scripts\GOOGLE-ANTI-GRAVITY\SAMISH\
├── Setup.ps1 (UI Main Launcher & Entry Point)
├── USER_GUIDE.md (User & Developer Documentation)
├── ARCHITECTURE.md (Architecture & Engineering Conventions)
├── CHANGELOG.md (Release History)
└── App/
    ├── SAMISH.ps1 (Background service loop)
    └── Modules/
        ├── UI.ps1 (Main WinForms window framework)
        ├── UI.SetupTab.ps1 (First-tab controls & drawings)
        ├── UI.DiagTab.ps1 (Second-tab controls & diagnostics layout)
        ├── Logger.psm1 (Shared logging API)
        ├── Install.Engine.ps1 (Task scheduler & setup actions)
        ├── Theme-Extension.ps1 (Color palette & custom theme manager)
        ├── ConfigBackup.Module.ps1 (Config schema validation & auto-fix)
        ├── Validation.Module.ps1 (Pre-flight install/uninstall checks)
        ├── Setup.Helpers.ps1 (Core helpers extracted from Setup.ps1)
        ├── Task.Helpers.ps1 (Shortcuts, schtasks, process control)
        ├── Diagnostics.Display.ps1 (Diagnostics header & display)
        ├── Config.Helpers.ps1 (Config write, log selection, profiles)
        ├── LiveLog.Module.ps1 (Live log streaming to Status box)
        └── Adapters/
            └── Adapter.*.ps1 (Per-device profile adapters)
```

#### Core Components
* **[Setup.ps1](file:///c:/Scripts/GOOGLE-ANTI-GRAVITY/SAMISH/Setup.ps1):** The primary entry point. Initializes the WinForms thread, loads configuration variables, and displays the installation dashboard.
* **[SAMISH.ps1](file:///c:/Scripts/GOOGLE-ANTI-GRAVITY/SAMISH/App/SAMISH.ps1):** The background service loop. It uses a low-overhead timer to monitor system power broadcasts, parses idle states, and runs the custom adapter triggers.
* **[Logger.psm1](file:///c:/Scripts/GOOGLE-ANTI-GRAVITY/SAMISH/App/Modules/Logger.psm1):** Unified logging utility shared between the frontend installer and background runner. Handles daily log file rotation and writes to the Windows Application Event Log.
* **[ConfigBackup.Module.ps1](file:///c:/Scripts/GOOGLE-ANTI-GRAVITY/SAMISH/App/Modules/ConfigBackup.Module.ps1):** Contains `Test-ConfigSchema` which provides automatic schema checking, type coercion, and auto-fix capabilities. Creates timestamped backups before applying repairs.

---

### 2. Core Variables & State Indicators

* **`$global:IsWizardJustCompleted`:** A global boolean flag set to `$true` when the First-Run Wizard successfully completes. Tells the UI loader to override local task-exists checks and immediately render the user's fresh setup options.
* **`$global:SamishScreenshotMode`:** A global flag that disables background polling and forces the form topmost during automated screenshots.
* **`$global:ThemeCustomActive`:** Instructs the drawing functions to ignore default brand colors and apply custom hex arrays from the Theme Configurator.
