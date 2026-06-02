# SAMISH Configuration Reference (`config.json`)

SAMISH stores its runtime configuration in `%APPDATA%\SAMISH\config.json`. This file is created automatically by the Setup UI and read by both the engine (`SAMISH.ps1`) and the Setup UI (`Setup.ps1`).

> **Atomic writes**: All config mutations use `Save-ContentAtomic` (write to `.tmp`, then swap) to prevent corruption during sudden power-offs.

---

## Core Engine Settings

| Key | Type | Default | Units | Description |
|-----|------|---------|-------|-------------|
| `EnableLogging` | bool | `false` | - | Master switch for file-based logging |
| `LogEverySeconds` | int | `30` | seconds | Minimum interval between heartbeat log entries. Set to `0` to log every loop iteration |
| `LogFile` | string | `%APPDATA%\SAMISH\samish_{DATE}.log` | - | Log file path template. `{DATE}` is replaced with `yyyyMMdd` |
| `EnableTrayIcon` | bool | `true` | - | Show the SAMISH system tray icon (requires Interactive install mode) |
| `EnableHotkey` | bool | `true` | - | Enable keyboard toggle hotkey |
| `HotkeyMode` | string | `"Custom"` | - | Hotkey binding. Valid: `ScrollLock`, `PauseBreak`, `F12`, `Custom` |
| `CustomHotkeyVirtualKey` | int | `0x76` (F7) | - | Win32 virtual key code when `HotkeyMode` is `Custom`. See [Virtual-Key Codes](https://learn.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes) |
| `OperatingMode` | string | `"Graceful"` | - | Engine shutdown mode. `Graceful` = close via window message. `Classic` = force-kill process |
| `EnableAutoRecovery` | bool | `true` | - | Automatically restart the mixer process if it exits unexpectedly while SAMISH is enabled |

## Profile Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `ActiveProfileId` | string | `"BEACN"` | Currently active device profile (matches a `Profiles/<id>.json` file) |
| `ProfilesEnabled` | string[] | `["BEACN"]` | Array of enabled profile IDs. Future: multi-device support |

## Monitored Applications

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `MonitoredApps` | object[] | `[]` | Array of application objects managed alongside the main mixer |

Each entry in `MonitoredApps`:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `ProcessName` | string | yes | Process name (without `.exe`) |
| `ExecutablePath` | string | yes | Full path to the executable |
| `RecoveryMode` | string | no | Per-app shutdown mode: `Graceful`, `Classic`, or `PauseMedia` |
| `OnWakeAction` | string | no | Wake behavior: `Smart` (restore if was playing), `Play` (always play), `Pause` (always pause), `KeepClosed` (don't restart) |
| `AutoRecover` | bool | no | If `true`, automatically restart this app if it exits unexpectedly |

## Game Mode 

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `GameModeEnabled` | bool | `false` | When `true`, SAMISH suppresses idle-based mixer shutdown while any listed game process is running |
| `GameModeList` | string[] | `[]` | Array of process names (without `.exe`) to watch. Example: `["destiny2", "baldursgate3", "csgo"]` |

> **Note**: Game mode only suppresses the idle timeout logic. Real sleep/wake events (WM_POWERBROADCAST) still trigger mixer stop/start normally.

## First-Run Wizard 

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `WizardCompleted` | bool | `false` | Set to `true` after the first-run wizard completes. When `false`, Setup launches the wizard on startup |

## UI Mode 

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `UI_Mode` | string | `"Full"` | Controls panel visibility in the Setup UI. Valid: `Simple`, `Full` |

- **Simple**: Dashboard-only view — minimal controls, Page 1 only, no diagnostics tab
- **Full**: Complete UI with all controls, diagnostics, and advanced tools

## Audio Endpoint

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `PreferredPlaybackDeviceGuid` | string | `""` | GUID of the preferred default playback audio device |
| `PreferredPlaybackDeviceName` | string | `""` | Display name of the preferred default playback device (for UI display) |
| `PreferredCommDeviceGuid` | string | `""` | GUID of the preferred default communications audio device |
| `PreferredCommDeviceName` | string | `""` | Display name of the preferred default communications device (for UI display) |

> When both GUID fields are empty, SAMISH does not attempt to restore audio endpoints on wake.

## Appearance

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `Theme` | string | `"Normal"` | UI color theme. Valid: `Normal`, `Neon` |

## Internal / System

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `SetupPath` | string | *(auto-set)* | Full path to the Setup executable. Used by the tray icon's "Open Settings" menu item |

---

## File Location

```
%APPDATA%\SAMISH\config.json
```

Typically resolves to: `C:\Users\<username>\AppData\Roaming\SAMISH\config.json`

## Backup Files

SAMISH also creates backup files in the same directory for restore operations:

| File | Purpose |
|------|---------|
| `device_wake_backup.json` | Devices whose wake capability was disabled |
| `task_wake_backup.json` | Scheduled tasks that were disabled |
| `service_wake_backup.json` | Windows services that were stopped/disabled |
| `powerplan_backup.json` | Power plan settings backup (display-off, sleep, hibernate timers, USB selective suspend) |
