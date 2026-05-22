# Suggested filename: SAMISH.ps1
# ==========================================
# SAMISH (Streaming Audio Mixer Interface Sleep Helper)
# Engine (current device profile: BEACN)
# Created by thomwithah
# ==========================================

# Temporarily bypass execution policy for the current process to ensure dot-sourced modules can load (crucial for PS2EXE compiled EXEs)
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue

# ---------- VERSION ----------
$ScriptName    = "SAMISH"
$ScriptVersion = "v1.0.5"
$ReleaseDate   = "2026-05-22"

# ---------- PATH RESOLUTION ----------
$PackageDir = $PSScriptRoot
if (-not $PackageDir -and $PSCommandPath) { $PackageDir = Split-Path -Parent $PSCommandPath }
if (-not $PackageDir) { $PackageDir = [System.AppDomain]::CurrentDomain.BaseDirectory }
if ($PackageDir -and $PackageDir.EndsWith("\")) { $PackageDir = $PackageDir.TrimEnd("\") }

# ---------- OPTIONAL CONFIG FILE (best practice) ----------
# The GUI will later write settings here. If the file is missing, defaults below are used.
$ConfigPath = Join-Path $env:APPDATA "SAMISH\config.json"

function Apply-ConfigFromFile {
    if (-not (Test-Path -LiteralPath $ConfigPath)) { return }
    try {
        $raw = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return }
        $cfg = $raw | ConvertFrom-Json -ErrorAction Stop

        foreach ($p in $cfg.PSObject.Properties) {
            $name = $p.Name
            $val  = $p.Value

            if (Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue) {
                Set-Variable -Name $name -Value $val -Scope Script -Force
            }
        }

        # ✅ Map OperatingMode -> OperatingMode (so engine behavior actually changes)
        if ($cfg.PSObject.Properties.Name -contains "OperatingMode") {
            if (Get-Variable -Name "OperatingMode" -Scope Script -ErrorAction SilentlyContinue) {
                $script:OperatingMode = [string]$cfg.OperatingMode
            }
        }

    } catch {
        # Best effort only. If config is malformed, continue with defaults.
    }
}

function Get-ProfileSelectionFromConfig {
    $cfgPath = Join-Path $env:APPDATA "SAMISH\config.json"
    if (-not (Test-Path -LiteralPath $cfgPath)) {
        return @{ Active = "BEACN"; Enabled = @("BEACN") }
    }

    try {
        $raw = Get-Content -LiteralPath $cfgPath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return @{ Active = "BEACN"; Enabled = @("BEACN") }
        }

        $cfg = $raw | ConvertFrom-Json -ErrorAction Stop

        $enabled = @()
        if ($cfg.PSObject.Properties.Name -contains "ProfilesEnabled") {
            foreach ($x in $cfg.ProfilesEnabled) {
                if ($x) { $enabled += [string]$x }
            }
        }

        $active = $null
        if ($cfg.PSObject.Properties.Name -contains "ActiveProfileId") {
            $active = [string]$cfg.ActiveProfileId
        }

        if (-not $enabled -or $enabled.Count -eq 0) { $enabled = @("BEACN") }
        if ([string]::IsNullOrWhiteSpace($active)) { $active = $enabled[0] }

        return @{ Active = $active; Enabled = $enabled }
    } catch {
        return @{ Active = "BEACN"; Enabled = @("BEACN") }
    }
}

# ---------- CONFIG DEFAULTS (legacy, still supported) ----------
# These will be overridden by config.json (if present) and later by Setup UI.
$TargetExePath     = "C:\Program Files\BEACN\BEACN App\BEACN.exe"
$TargetProcessName = "BEACN"
$OperatingMode = "Graceful"          # Classic | Graceful
$GracefulWindowWakeDelayMs = 800        # Delay after restoring UI window
$GracefulShutdownWaitMs = 800           # Wait for graceful exit before fallback
$MonitoredApps = @()

$RefreshPowerPlanEverySeconds = 59
$DefaultPostDisplayDelaySeconds = 8
$ToleranceSeconds = 3
$RestartWhenIdleLE = 10
$RestartGuardSecondsAfterStop = 25

$EnableLogging = $false
$LogEverySeconds = 30
# Default log file template (resolved per-day). Setup writes the same template into config.json.
$LogFile = Join-Path $env:APPDATA "SAMISH\samish_{DATE}.log"

$EnableTrayIcon = $true
$EnableHotkey = $true
$HotkeyMode = "Custom"
$CustomHotkeyVirtualKey = 0x76

# Load optional config file overrides
Apply-ConfigFromFile

# ---------- POWER PLAN COMMON (shared read utilities) ----------
$PowerPlanCommonPath = Join-Path $PackageDir "Modules\PowerPlan.Read.Common.ps1"
if (Test-Path -LiteralPath $PowerPlanCommonPath) {
    try { . $PowerPlanCommonPath } catch { }
}

$CommonModulePath = Join-Path $PackageDir "Modules\App.Control.Common.ps1"
if (Test-Path -LiteralPath $CommonModulePath) {
    . $CommonModulePath
}

$ClassicModulePath = Join-Path $PackageDir "Modules\App.Control.Classic.ps1"
if (Test-Path -LiteralPath $ClassicModulePath) {
    . $ClassicModulePath
}

$GracefulModulePath = Join-Path $PackageDir "Modules\App.Control.Graceful.ps1"
if (Test-Path -LiteralPath $GracefulModulePath) {
    . $GracefulModulePath
}

# ---------- LOGGING ----------
$script:LastHeartbeat = Get-Date "2000-01-01"

function Resolve-SamishLogPath {
    param([string]$TemplatePath)

    if ([string]::IsNullOrWhiteSpace($TemplatePath)) { return $null }

    $today = (Get-Date -Format "yyyyMMdd")
    $resolved = $TemplatePath.Replace("{DATE}", $today)

    # Ensure directory exists
    try {
        $dir = Split-Path -Parent $resolved
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    } catch {}

    return $resolved
}

function Log-Always([string]$msg) {
    if (-not $EnableLogging) { return }

    $path = Resolve-SamishLogPath $LogFile
    if (-not $path) { return }

    try {
        Add-Content -Path $path -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $msg"
    } catch {
        # Best effort logging only
    }
}

function Log-Heartbeat([string]$msg) {
    if (-not $EnableLogging) { return }

    if ($LogEverySeconds -eq 0) {
        Log-Always $msg
        return
    }

    $now = Get-Date
    if (($now - $script:LastHeartbeat).TotalSeconds -ge $LogEverySeconds) {
        Log-Always $msg
        $script:LastHeartbeat = $now
    }
}

function Apply-ActiveProfile {
    param([string]$ProfileId)

    if ([string]::IsNullOrWhiteSpace($ProfileId)) { return $false }

    $profilesDir = Join-Path $env:APPDATA "SAMISH\Profiles"
    $profilePath = Join-Path $profilesDir ($ProfileId + ".json")

    if (-not (Test-Path -LiteralPath $profilePath)) {
        Log-Always ("Profile file not found: " + $profilePath + " (falling back to defaults)")
        return $false
    }

    try {
        $raw = Get-Content -LiteralPath $profilePath -Raw -ErrorAction Stop
        $p = $raw | ConvertFrom-Json -ErrorAction Stop

        if (-not $p.targets -or $p.targets.Count -lt 1) {
            Log-Always ("Profile has no targets: " + $ProfileId)
            return $false
        }

        # NOTE: Current engine is single-target. We take the first target for now.
        # Future multi-device support: iterate p.targets and maintain per-target state.
        $t = $p.targets[0]

        if ($t.processName)     { $script:TargetProcessName = [string]$t.processName }
        if ($t.defaultExePath)  { $script:TargetExePath = [string]$t.defaultExePath }

        if ($p.defaults) {
            if ($p.defaults.GracefulWindowWakeDelayMs) { $script:GracefulWindowWakeDelayMs = [int]$p.defaults.GracefulWindowWakeDelayMs }
            if ($p.defaults.GracefulShutdownWaitMs)    { $script:GracefulShutdownWaitMs = [int]$p.defaults.GracefulShutdownWaitMs }
        }

        # Load active adapter script dynamically
        $script:ActiveProfileId = $ProfileId
        $adapterPath = Join-Path $PackageDir "Modules\Adapters\Adapter.$ProfileId.ps1"
        if (Test-Path -LiteralPath $adapterPath) {
            . $adapterPath
            Log-Always ("Active profile loaded: " + $ProfileId + " (target=" + $script:TargetProcessName + ") with adapter.")
        } else {
            Log-Always ("WARNING: No adapter found for " + $ProfileId + " at " + $adapterPath)
            Log-Always ("Active profile loaded: " + $ProfileId + " (target=" + $script:TargetProcessName + ") WITHOUT adapter.")
        }

        return $true
    } catch {
        Log-Always ("Failed to load profile " + $ProfileId + ": " + $_.Exception.Message)
        return $false
    }
}

# ---------- PROFILE SELECTION (after logging is available) ----------
try {
    $sel = Get-ProfileSelectionFromConfig
    if ($sel.Enabled.Count -gt 1) {
        Log-Always ("Multiple profiles enabled in config, but engine is currently single-target. Active=" + $sel.Active)
    }
    $null = Apply-ActiveProfile -ProfileId $sel.Active
} catch {
    # Best effort only; engine can continue with defaults if profiles fail
    try { Log-Always ("Profile load failed: " + $_.Exception.Message) } catch {}
}

# ---------- SINGLE INSTANCE GUARD ----------
# Prevent multiple tray icons / multiple helper instances.
# Strategy:
#   1) Try creating a Global mutex with explicit security (WorldSid FullControl) so it works across elevation contexts.
#   2) If that fails (some environments/policies), fall back to a simple mutex constructor (no custom ACL).
#   3) If BOTH fail, log a warning and continue (best effort) rather than crashing SAMISH.

$script:mutex = $null
$createdNew = $false

# Choose scope:
#   - "Global\" prevents duplicates across sessions (RDP / fast-user-switch).
#   - If permission issues with Global, switching to "Local\" is a safe alternative.
$MutexName = "Global\SAMISH_Engine_Instance_Mutex"

# Local helper for safe logging (avoids throwing if Log-Always isn't ready for any reason)
function _SamishTryLog([string]$Message) {
    try {
        if (Get-Command Log-Always -ErrorAction SilentlyContinue) {
            Log-Always $Message
        }
    } catch { }
}

try {
    # --- Preferred path: Mutex + explicit security (most robust across admin/non-admin contexts) ---
    $MutexSecurity = New-Object System.Security.AccessControl.MutexSecurity

    # Allow all users to fully control the mutex (so Standard + Admin share the same lock)
    $AllUsersSid  = [System.Security.Principal.SecurityIdentifier]::new(
        [System.Security.Principal.WellKnownSidType]::WorldSid, $null
    )

    $AllUsersRule = New-Object System.Security.AccessControl.MutexAccessRule(
        $AllUsersSid,
        [System.Security.AccessControl.MutexRights]::FullControl,
        [System.Security.AccessControl.AccessControlType]::Allow
    )

    $MutexSecurity.AddAccessRule($AllUsersRule) | Out-Null

    # Correct constructor signature: (initiallyOwned, name, ref createdNew, mutexSecurity)
    $script:mutex = [System.Threading.Mutex]::new($true, $MutexName, [ref]$createdNew, $MutexSecurity)

    if (-not $createdNew) {
        _SamishTryLog "Existing helper detected (mutex already held) - exiting duplicate instance."
        exit
    }
}
catch {
    # --- Fallback path: Simple named mutex without custom ACL ---
    _SamishTryLog ("WARNING: MutexSecurity path failed; falling back to simple mutex. Details: " + $_.Exception.Message)

    try {
        $createdNew = $false
        $script:mutex = New-Object System.Threading.Mutex($true, $MutexName, [ref]$createdNew)

        if (-not $createdNew) {
            _SamishTryLog "Existing helper detected (simple mutex already held) - exiting duplicate instance."
            exit
        }
    }
    catch {
        # Last-resort: singleton enforcement unavailable.
        # DO NOT exit here, because a hard failure could prevent SAMISH from running at all in locked-down environments.
        _SamishTryLog ("ERROR: Failed to create singleton mutex (no guard active). Duplicates may be possible. Details: " + $_.Exception.Message)
    }
}

# ---------- IDLE DETECTION ----------
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class IdleNative {
  [StructLayout(LayoutKind.Sequential)]
  public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
  [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
  public static uint GetIdleMilliseconds() {
    LASTINPUTINFO li = new LASTINPUTINFO();
    li.cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf(li);
    GetLastInputInfo(ref li);
    return (uint)Environment.TickCount - li.dwTime;
  }
}
"@

function Get-IdleSeconds { [math]::Floor([IdleNative]::GetIdleMilliseconds() / 1000) }

# ---------- POWERCFG ----------
$SUB_VIDEO = "7516b95f-f776-4464-8c53-06167f40cc99"
$VIDEOIDLE = "3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e"

if (-not (Get-Command Get-ActiveSchemeGuid -ErrorAction SilentlyContinue)) {
    function Get-ActiveSchemeGuid {
        $out = powercfg /getactivescheme 2>$null
        if ($out -match '([0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})') {
            return $matches[1].ToLower()
        }
        return $null
    }
}

function Get-ACSettingSeconds([string]$schemeGuid,[string]$subGuid,[string]$setGuid) {
    # Prefer shared common implementation if available:
    # Common provides Get-PowerSettingSecondsAC(SchemeGuid, SubGuid, SettingGuid)
    if (Get-Command Get-PowerSettingSecondsAC -ErrorAction SilentlyContinue) {
        try {
            return Get-PowerSettingSecondsAC -SchemeGuid $schemeGuid -SubGuid $subGuid -SettingGuid $setGuid
        } catch {
            # fall through to local parsing
        }
    }

    # Local fallback parsing (legacy, still supported)
    $out = powercfg /query $schemeGuid $subGuid $setGuid 2>$null
    $m = ($out |
        Select-String -Pattern 'Current AC Power Setting Index:\s+0x([0-9a-fA-F]+)' |
        Select-Object -First 1)

    if ($m -and $m.Matches.Count -gt 0) {
        try { return [Convert]::ToInt32($m.Matches[0].Groups[1].Value, 16) } catch { return $null }
    }
    return $null
}

# ---------- MIXER CONTROL ----------
function Invoke-MixerStop {
    $stoppedAny = $false

    # 1. Stop Main Mixer via active adapter
    $adapterStopCmd = "Stop-$($script:ActiveProfileId)Adapter"
    if (Get-Command $adapterStopCmd -ErrorAction SilentlyContinue) {
        $r = & $adapterStopCmd `
            -ProcessName $script:TargetProcessName `
            -ConfiguredPath $script:TargetExePath `
            -OperatingMode $script:OperatingMode `
            -WindowWakeDelayMs $script:GracefulWindowWakeDelayMs `
            -ShutdownWaitMs $script:GracefulShutdownWaitMs
        
        if ($r) { $stoppedAny = $true }
    } else {
        # Fallback to generic force stop if adapter is missing or has no stop func
        if (Get-Process -Name $script:TargetProcessName -ErrorAction SilentlyContinue) {
             Log-Always "No adapter stop function ($adapterStopCmd) found for $script:TargetProcessName. Falling back to generic classic stop."
             $r2 = Invoke-AppStop -ProcessName $script:TargetProcessName
             if ($r2 -and $r2.Stopped) { $stoppedAny = $true }
        }
    }
    
    # 2. Stop all custom monitored apps if running
    if ($script:MonitoredApps) {
        foreach ($app in $script:MonitoredApps) {
            if (Get-Process -Name $app.ProcessName -ErrorAction SilentlyContinue) {
                # Per-app RecoveryMode overrides the global OperatingMode
                $appMode = if ($app.RecoveryMode) { $app.RecoveryMode } else { $script:OperatingMode }

                if ($appMode -eq "Graceful" -and (Get-Command Invoke-AppStopGraceful -ErrorAction SilentlyContinue)) {
                    Log-Always "Stopping $($app.ProcessName) (Graceful mode)"
                    $r = Invoke-AppStopGraceful `
                        -ProcessName $app.ProcessName `
                        -ConfiguredPath $app.ExecutablePath `
                        -WindowWakeDelayMs $script:GracefulWindowWakeDelayMs `
                        -ShutdownWaitMs $script:GracefulShutdownWaitMs

                    if ($r -and $r.Stopped) {
                        Log-Always "Stopped $($app.ProcessName) (Graceful)"
                        $stoppedAny = $true
                    } else {
                        # Graceful failed - fall back to Classic
                        Log-Always "Graceful stop failed for $($app.ProcessName), falling back to Classic"
                        $r2 = Invoke-AppStop -ProcessName $app.ProcessName
                        if ($r2 -and $r2.Stopped) {
                            Log-Always "Stopped $($app.ProcessName) (Classic fallback)"
                            $stoppedAny = $true
                        }
                    }
                } else {
                    Log-Always "Stopping $($app.ProcessName) (Classic mode)"
                    $r2 = Invoke-AppStop -ProcessName $app.ProcessName
                    if ($r2 -and $r2.Stopped) {
                        Log-Always "Stopped $($app.ProcessName) (Classic)"
                        $stoppedAny = $true
                    }
                }
            }
        }
    }

    return $stoppedAny
}

function Invoke-MixerStart {
    $startedAny = $false
    
    # 1. Start Main Mixer via active adapter
    $adapterStartCmd = "Start-$($script:ActiveProfileId)Adapter"
    if (Get-Command $adapterStartCmd -ErrorAction SilentlyContinue) {
        $r = & $adapterStartCmd -ProcessName $script:TargetProcessName -ConfiguredPath $script:TargetExePath
        if ($r) { $startedAny = $true }
    } else {
        # Fallback to generic start if adapter is missing or has no start func
        Log-Always "No adapter start function ($adapterStartCmd) found for $script:TargetProcessName. Falling back to generic start."
        $lookup = Get-AppExecutablePath -ProcessName $script:TargetProcessName -ConfiguredPath $script:TargetExePath
        if ($lookup.IsValid) {
            $result = Invoke-AppStart -ProcessName $script:TargetProcessName -ExePath $lookup.Path
            if ($result.Started) { $startedAny = $true }
        }
    }
    
    # 2. Start all custom monitored apps
    if ($script:MonitoredApps) {
        foreach ($app in $script:MonitoredApps) {
            # Honour per-app NoRestartOnWake flag - skip restart if user opted out
            if ($app.NoRestartOnWake -eq $true) {
                Log-Always "Skipping restart of $($app.ProcessName) (NoRestartOnWake = true)"
                continue
            }

            # Check if already running
            if (Get-Process -Name $app.ProcessName -ErrorAction SilentlyContinue) {
                Log-Always "Custom app $($app.ProcessName) is already running."
                $startedAny = $true
                continue
            }
            if ($app.ExecutablePath -and (Test-Path $app.ExecutablePath)) {
                $result = Invoke-AppStart -ProcessName $app.ProcessName -ExePath $app.ExecutablePath
                if ($result.Started) {
                    Log-Always "Starting $($app.ProcessName) ($($app.ExecutablePath))"
                    $startedAny = $true
                }
            } else {
                Log-Always "Executable for $($app.ProcessName) not found at $($app.ExecutablePath)."
            }
        }
    }
    
    return $startedAny
}

# ---------- TRAY ICON ----------
if ($EnableTrayIcon) {
    Start-Sleep -Seconds 3
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $script:TrayEnabled = $true
    $script:icon = New-Object System.Windows.Forms.NotifyIcon

    $script:IconActive = $null
    $script:IconDisabled = $null

    try {
        $activePath = Join-Path $PackageDir "Assets\SAMISH.ico"
        $disabledPath = Join-Path $PackageDir "Assets\SAMISH-GREYSCALE.ico"

        if (Test-Path -LiteralPath $activePath) { $script:IconActive = New-Object System.Drawing.Icon($activePath) }
        if (Test-Path -LiteralPath $disabledPath) { $script:IconDisabled = New-Object System.Drawing.Icon($disabledPath) }
    } catch {}

    $script:icon.Icon = if ($script:IconActive) { $script:IconActive } else { [System.Drawing.SystemIcons]::Application }
    $script:icon.Visible = $true

    # Note: NotifyIcon.Text has a short length limit
    $script:icon.Text = "SAMISH v1.0.5"

    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $toggleItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $toggleItem.Text = "Disable helper"
    $exitItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $exitItem.Text = "Exit"
    [void]$menu.Items.Add($toggleItem)
    [void]$menu.Items.Add($exitItem)
    $script:icon.ContextMenuStrip = $menu

    $script:MenuToggleItem = $toggleItem

    $toggleItem.add_Click({
        Set-HelperEnabled (-not $script:TrayEnabled) "TRAY MENU"
    })

    $exitItem.add_Click({
        try { $script:icon.Visible = $false; $script:icon.Dispose() } catch {}
        try { [System.Windows.Forms.Application]::Exit() } catch {}
    })
}

function Notify([string]$text) {
    if ($EnableTrayIcon -and $null -ne $script:icon) {
        try { $script:icon.ShowBalloonTip(1200,"SAMISH",$text,[System.Windows.Forms.ToolTipIcon]::Info) } catch {}
    }
    Log-Always $text
}

function Set-HelperEnabled([bool]$enabledNow, [string]$source) {
    $script:TrayEnabled = $enabledNow

    try {
        if ($null -ne $script:MenuToggleItem) {
            $script:MenuToggleItem.Text = if ($enabledNow) { "Disable helper" } else { "Enable helper" }
        }
        if ($null -ne $script:icon) {
            if ($enabledNow) {
                $script:icon.Icon = if ($script:IconActive) { $script:IconActive } else { [System.Drawing.SystemIcons]::Application }
            } else {
                $script:icon.Icon = if ($script:IconDisabled) { $script:IconDisabled } else { [System.Drawing.SystemIcons]::Application }
            }
        }
    } catch {}

    Log-Always ("STATE CHANGED -> " + ($(if($enabledNow){"ENABLED"}else{"DISABLED"})))
    Notify ("$source -> " + ($(if($enabledNow){"ENABLED"}else{"DISABLED"})))
}

# ---------- HOTKEY (Polling-based) ----------
if ($EnableHotkey) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class KeyState {
  [DllImport("user32.dll")]
  public static extern short GetAsyncKeyState(int vKey);
}
"@

    switch ($HotkeyMode) {
        "ScrollLock" { $vk = 0x91 }
        "PauseBreak" { $vk = 0x13 }
        "F12"        { $vk = 0x7B }
        "Custom"     { $vk = $CustomHotkeyVirtualKey }
        default      { $vk = 0x91 }
    }

    $script:LastKeyDown = $false
    Log-Always "Hotkey system active (polling mode)"
}

# ---------- STATE ----------
$lastRefresh = Get-Date "2000-01-01"
$activeScheme = $null
$killThresholdSeconds = $null
$mixerStopped = $false
$mixerStoppedAt = $null
$stopLatchedThisIdleStretch = $false

# ---------- MAIN LOOP ----------
while ($true) {

    # ---------- DISABLED SHORT-CIRCUIT ----------
    # Hotkey + tray DoEvents are now handled every 100ms inside the chunked sleep below.
    # When tray is disabled and helper is off, burn through the remaining interval quickly.
    if ($EnableTrayIcon -and ($script:TrayEnabled -eq $false)) {
        Start-Sleep -Milliseconds 100
        continue
    }

    if (((Get-Date) - $lastRefresh).TotalSeconds -ge $RefreshPowerPlanEverySeconds -or -not $activeScheme) {
        $activeScheme = Get-ActiveSchemeGuid
        if ($activeScheme) {
            $displayOffSeconds = Get-ACSettingSeconds $activeScheme $SUB_VIDEO $VIDEOIDLE
            if ($displayOffSeconds -and $displayOffSeconds -gt 0) {
                $killThresholdSeconds = $displayOffSeconds + $DefaultPostDisplayDelaySeconds
            } else {
                $killThresholdSeconds = $null
            }
        }
        $lastRefresh = Get-Date
    }

    $idle = Get-IdleSeconds
    Log-Heartbeat "Loop: idle=$idle threshold=$killThresholdSeconds"

    if ($idle -le 1) { $stopLatchedThisIdleStretch = $false }

    if (-not $killThresholdSeconds) {
        Start-Sleep -Milliseconds 100
        continue
    }

    if (-not $stopLatchedThisIdleStretch -and $idle -ge ($killThresholdSeconds - $ToleranceSeconds)) {
        if (Invoke-MixerStop) { $mixerStopped = $true; $mixerStoppedAt = Get-Date }
        $stopLatchedThisIdleStretch = $true
    }

    if ($mixerStopped -and $idle -le $RestartWhenIdleLE) {
        $elapsed = if ($mixerStoppedAt) { ((Get-Date) - $mixerStoppedAt).TotalSeconds } else { 9999 }
        if ($elapsed -ge $RestartGuardSecondsAfterStop) {
            if (Invoke-MixerStart) { $mixerStopped = $false }
        }
    }

    # Dynamic sleep throttle calculation
    $sleepMs = 100
    if (-not $mixerStopped -and $killThresholdSeconds) {
        $threshold = $killThresholdSeconds - $ToleranceSeconds
        $timeToThreshold = $threshold - $idle

        if ($timeToThreshold -gt 30) {
            $sleepMs = 10000
        }
        elseif ($timeToThreshold -gt 15) {
            $sleepMs = 5000
        }
        elseif ($timeToThreshold -gt 5) {
            $sleepMs = 2000
        }
        elseif ($timeToThreshold -gt 2) {
            $sleepMs = 500
        }
    }

    # Chunked sleep: check hotkey (and tray) every 100ms so toggle is always responsive,
    # even when the main loop interval is several seconds.
    $sleptMs = 0
    while ($sleptMs -lt $sleepMs) {
        Start-Sleep -Milliseconds 100
        $sleptMs += 100

        if ($EnableTrayIcon) {
            try { [System.Windows.Forms.Application]::DoEvents() } catch {}
        }

        if ($EnableHotkey) {
            $isDown = ([KeyState]::GetAsyncKeyState($vk) -band 0x8000) -ne 0
            if ($isDown -and -not $script:LastKeyDown) {
                Set-HelperEnabled (-not $script:TrayEnabled) "HOTKEY"
            }
            $script:LastKeyDown = $isDown
        }
    }
}