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
    - **Verify & Restore Settings:** Scans your active power plans, USB selective suspend states, disabled wake devices, and active wake timers, automatically repairing or optimizing them.
    - **Open Windows Task Scheduler:** Instantly launches the Windows Task Scheduler to inspect or manage the background service tasks.
    - **Restart SAMISH Service:** Safely restarts the background helper loop while preserving your custom configurations.
    - **Read Setup & Status:** Queries and displays current installation status, configuration details, and active status.
    - **Open Setup Log:** Opens the main setup text log in your default text editor.
    - **Submit Diagnostic Report:** Compiles, sanitizes, and packages configurations, logs, and powercfg reports into a ZIP archive on your Desktop, opening the GitHub issue page to submit it.
    - **Set Preferred Audio Device:** Capture and persist your default playback and communication endpoints so SAMISH can restore them after wake cycles.
    - **Game Mode Settings:** Configure automated exclusions so SAMISH skips telemetry scans while full-screen games or specific applications are running.
  * **Live Log Tab:** Stream real-time logs directly from the background engine (`samish.log`) to inspect sleep triggers.
* **Diagnostics Drawer (Page 2):** Expand this by clicking **Diagnostics >>** to inspect active wake timers, USB controllers, and Modern Standby exit telemetry directly from your Windows Kernel.

#### Color Theme Configurator
SAMISH includes a standalone color theme utility. You can customize the dashboard palette to match your streaming setup:
1. Run `Launch-ColorThemeConfigurator.bat` from the root directory.
2. Select standard themes (Dark Slate, Deep Purple, Amber Neon) or create your own custom theme by typing in hexadecimal colors.
3. Save changes; the main GUI and modal dialogs will dynamically update to reflect your custom colors. Custom configurations are applied immediately as your default theme.

---

## Part 2: Developer Guide

### 1. Codebase Architecture

The codebase is split into modular components to ensure portability and high testability:

```
c:\Scripts\GOOGLE-ANTI-GRAVITY\SAMISH\
├── Setup.ps1 (UI Main Launcher & Entry Point)
├── USER_GUIDE.md (User & Developer Documentation)
└── App/
    ├── SAMISH.ps1 (Background service loop)
    └── Modules/
        ├── UI.ps1 (Main WinForms window framework)
        ├── UI.SetupTab.ps1 (First-tab controls & drawings)
        ├── UI.DiagTab.ps1 (Second-tab controls & diagnostics layout)
        ├── Logger.psm1 (Shared logging API)
        ├── Install.Engine.ps1 (Task scheduler & setup actions)
        └── Theme-Extension.ps1 (Color palette & custom theme manager)
```

#### Core Components
* **[Setup.ps1](file:///c:/Scripts/GOOGLE-ANTI-GRAVITY/SAMISH/Setup.ps1):** The primary entry point. Initializes the WinForms thread, loads configuration variables, and displays the installation dashboard.
* **[SAMISH.ps1](file:///c:/Scripts/GOOGLE-ANTI-GRAVITY/SAMISH/App/SAMISH.ps1):** The background service loop. It uses a low-overhead timer to monitor system power broadcasts, parses idle states, and runs the custom adapter triggers.
* **[Logger.psm1](file:///c:/Scripts/GOOGLE-ANTI-GRAVITY/SAMISH/App/Modules/Logger.psm1):** Unified logging utility shared between the frontend installer and background runner. Handles daily log file rotation and writes to the Windows Application Event Log.
* **[ConfigBackup.Module.ps1](file:///c:/Scripts/GOOGLE-ANTI-GRAVITY/SAMISH/App/Modules/ConfigBackup.Module.ps1):** Contains `Test-ConfigSchema` which provides automatic schema checking, type coercion, and auto-fix capabilities.

---

### 2. Core Variables & State Indicators

* **`$global:IsWizardJustCompleted`:** A global boolean flag set to `$true` when the First-Run Wizard successfully completes. Tells the UI loader to override local task-exists checks and immediately render the user's fresh setup options.
* **`$global:SamishScreenshotMode`:** A global flag that disables background polling and forces the form topmost during automated screenshots.
* **`$global:ThemeCustomActive`:** Instructs the drawing functions to ignore default brand colors and apply custom hex arrays from the Theme Configurator.
