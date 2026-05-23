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
$ScriptVersion = "v1.0.9"
$ReleaseDate   = "2026-05-23"

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
$script:PlayingAppsBeforeSleep = @()

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

function Write-EventLogEntry {
    param(
        [string]$Message,
        [System.Diagnostics.EventLogEntryType]$EntryType = "Information",
        [int]$EventId = 100
    )

    try {
        if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\SAMISH") {
            [System.Diagnostics.EventLog]::WriteEntry("SAMISH", $Message, $EntryType, $EventId)
        }
    }
    catch {
        # Fail-safe silently to standard file logs
    }
}

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

function Rotate-LogFileIfNeeded {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        if (-not (Test-Path -LiteralPath $Path)) { return }

        $fileItem = Get-Item -LiteralPath $Path
        # 5MB = 5 * 1024 * 1024 = 5242880 bytes
        if ($fileItem.Length -le 5242880) { return }

        $dir = Split-Path -Parent $Path
        $name = Split-Path -Leaf $Path
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($name)
        $ext = [System.IO.Path]::GetExtension($name)

        $rotatedPath = $null
        for ($i = 1; $i -le 100; $i++) {
            $testName = "$baseName.$i$ext"
            $testPath = Join-Path $dir $testName
            if (-not (Test-Path -LiteralPath $testPath)) {
                $rotatedPath = $testPath
                break
            }
        }

        if (-not $rotatedPath) {
            $rotatedPath = Join-Path $dir "$baseName.100$ext"
            if (Test-Path -LiteralPath $rotatedPath) {
                Remove-Item -LiteralPath $rotatedPath -Force -ErrorAction SilentlyContinue
            }
        }

        if ($rotatedPath) {
            [System.IO.File]::Move($Path, $rotatedPath)
        }
    }
    catch {
        # Fail silently
    }
}

function Log-Always([string]$msg) {
    if (-not $EnableLogging) { return }

    $path = Resolve-SamishLogPath $LogFile
    if (-not $path) { return }

    try {
        Rotate-LogFileIfNeeded -Path $path
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
        Write-EventLogEntry -Message ("Profile file not found: " + $profilePath + " (falling back to defaults)") -EntryType "Warning" -EventId 300
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
            Write-EventLogEntry -Message ("No adapter found for " + $ProfileId + " at " + $adapterPath) -EntryType "Warning" -EventId 300
            Log-Always ("Active profile loaded: " + $ProfileId + " (target=" + $script:TargetProcessName + ") WITHOUT adapter.")
        }

        return $true
    } catch {
        Log-Always ("Failed to load profile " + $ProfileId + ": " + $_.Exception.Message)
        Write-EventLogEntry -Message ("Failed to load profile " + $ProfileId + ": " + $_.Exception.Message) -EntryType "Error" -EventId 400
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
$script:ExitRequested = $false
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
    # Preferred path: Mutex + explicit security (most robust across admin/non-admin contexts)
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
    # Fallback path: Simple named mutex without custom ACL
    _SamishTryLog ("WARNING: MutexSecurity path failed; falling back to simple mutex. Details: " + $_.Exception.Message)
    Write-EventLogEntry -Message ("MutexSecurity path failed; falling back to simple mutex. Details: " + $_.Exception.Message) -EntryType "Warning" -EventId 300

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
        Write-EventLogEntry -Message ("Failed to create singleton mutex (no guard active). Duplicates may be possible. Details: " + $_.Exception.Message) -EntryType "Error" -EventId 400
    }
}

try {
    # IDLE DETECTION
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

    # POWERCFG
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

    function Test-ActiveSleepBlockerExists {
        $overrides = @{}
        try {
            $overrideOutput = powercfg /requestsoverride 2>$null
            $section = ""
            $knownCats = @('DISPLAY', 'SYSTEM', 'AWAYMODE', 'EXECUTION', 'PERFBOOST')
            
            foreach ($line in $overrideOutput) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $trimmed = $line.Trim()
                if ($trimmed -match '^\[(SERVICE|PROCESS|DRIVER)\]$') {
                    $section = $Matches[1].ToUpper()
                    continue
                }
                
                $tokens = $trimmed.Split([char[]]@(' ', "`t"), [System.StringSplitOptions]::RemoveEmptyEntries)
                if ($tokens.Length -gt 1) {
                    $cats = @()
                    $nameTokens = @()
                    
                    $i = $tokens.Length - 1
                    while ($i -ge 0) {
                        $tokenUpper = $tokens[$i].ToUpper()
                        if ($knownCats -contains $tokenUpper) {
                            $cats += $tokenUpper
                            $i--
                        } else {
                            break
                        }
                    }
                    
                    if ($i -ge 0) {
                        for ($j = 0; $j -le $i; $j++) {
                            $nameTokens += $tokens[$j]
                        }
                        $rawName = $nameTokens -join ' '
                        $cleanName = $rawName
                        if ($cleanName -match '([^\\]+)\.exe$') {
                            $cleanName = $Matches[1]
                        } else {
                            if ($cleanName -match '[^\\]+$') {
                                $cleanName = $Matches[0]
                            }
                        }
                        $cleanName = $cleanName.Trim().ToLower()
                        
                        if (-not $overrides.ContainsKey($cleanName)) {
                            $overrides[$cleanName] = @()
                        }
                        foreach ($c in $cats) {
                            $overrides[$cleanName] += $c.ToLower()
                        }
                    }
                }
            }
        } catch {
            # Best effort
        }
        
        $TestIsRequestOverridden = {
            param(
                [string]$name,
                [string]$path,
                [string]$category
            )
            $catLower = $category.ToLower()
            foreach ($key in $overrides.Keys) {
                if ($key -eq $name.ToLower() -or $key -eq $path.ToLower()) {
                    if ($overrides[$key] -contains $catLower) {
                        return $true
                    }
                }
            }
            return $false
        }

        try {
            $requestsOutput = powercfg /requests 2>$null
            $currentCategory = ""
            $blockers = @()
            
            foreach ($line in $requestsOutput) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $trimmed = $line.Trim()
                
                if ($trimmed -match '^(DISPLAY|SYSTEM|EXECUTION|AWAYMODE|PERFBOOST):') {
                    $currentCategory = $Matches[1].ToUpper()
                    continue
                }
                
                if ($currentCategory -ne "DISPLAY" -and $currentCategory -ne "SYSTEM" -and $currentCategory -ne "EXECUTION") {
                    continue
                }
                
                if ($trimmed -match '^\[(PROCESS|DRIVER|SERVICE)\]\s+(.+)$') {
                    $reqType = $Matches[1].ToUpper()
                    $rawPathOrName = $Matches[2].Trim()
                    
                    $cleanName = $rawPathOrName
                    if ($cleanName -match '([^\\]+)\.exe$') {
                        $cleanName = $Matches[1]
                    } else {
                        if ($cleanName -match '[^\\]+$') {
                            $cleanName = $Matches[0]
                        }
                    }
                    $cleanName = $cleanName.Trim()
                    
                    if ($script:TargetProcessName -and $cleanName.ToLower() -eq $script:TargetProcessName.ToLower()) {
                        continue
                    }
                    
                    if (& $TestIsRequestOverridden $cleanName $rawPathOrName $currentCategory) {
                        continue
                    }
                    
                    if ($currentCategory -eq "SYSTEM" -or $currentCategory -eq "EXECUTION") {
                        if ($reqType -ne "PROCESS") {
                            continue
                        }
                        
                        $isMonitored = $false
                        if ($script:MonitoredApps) {
                            foreach ($app in $script:MonitoredApps) {
                                if ($app.ProcessName -and $app.ProcessName.ToLower() -eq $cleanName.ToLower()) {
                                    $isMonitored = $true
                                    break
                                }
                            }
                        }
                        if ($isMonitored) {
                            continue
                        }
                    }
                    
                    $blockers += [pscustomobject]@{
                        Category = $currentCategory
                        Type     = $reqType
                        Name     = $cleanName
                        Raw      = $rawPathOrName
                    }
                }
            }
            
            if ($blockers.Count -gt 0) {
                return $blockers
            }
        } catch {
            # Best effort
        }
        
        return $null
    }

    # MIXER CONTROL

    function Wait-UwpAsync {
        param(
            [Parameter(Mandatory = $true)]
            $AsyncOp,
            [Parameter(Mandatory = $true)]
            [Type]$ResultType
        )
        try {
            [void][System.Reflection.Assembly]::LoadWithPartialName("System.Runtime.WindowsRuntime")
            $asTaskMethods = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq "AsTask" }
            $asTaskMethod = $asTaskMethods | Where-Object {
                $params = $_.GetParameters()
                $params.Count -eq 1 -and $params[0].ParameterType.Name -eq 'IAsyncOperation`1'
            }
            if (-not $asTaskMethod) { return $null }
            $genericMethod = $asTaskMethod.MakeGenericMethod($ResultType)
            $task = $genericMethod.Invoke($null, @($AsyncOp))
            $task.Wait()
            return $task.Result
        }
        catch {
            return $null
        }
    }

    function Get-SmtcSessionForProcess {
        param([string]$ProcessName)
        if ([string]::IsNullOrWhiteSpace($ProcessName)) { return $null }
        try {
            [void][System.Reflection.Assembly]::LoadWithPartialName("System.Runtime.WindowsRuntime")
            $smtcType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType=WindowsRuntime]
            $asyncOp = $smtcType::RequestAsync()
            $manager = Wait-UwpAsync -AsyncOp $asyncOp -ResultType ($smtcType)
            if (-not $manager) { return $null }
            $sessions = $manager.GetSessions()
            foreach ($session in $sessions) {
                $sourceApp = $session.SourceAppUserModelId
                if (-not $sourceApp) { continue }
                $cleanName = $sourceApp
                if ($cleanName -match "([^\\]+)\.exe$") {
                    $cleanName = $Matches[1]
                }
                elseif ($cleanName -match "^([^\!]+)\!") {
                    $cleanName = $Matches[1]
                }
                if ($cleanName -match "^Spotify") { $cleanName = "spotify" }
                elseif ($cleanName -match "Chrome") { $cleanName = "chrome" }
                elseif ($cleanName -match "Edge") { $cleanName = "msedge" }
                elseif ($cleanName -match "Firefox") { $cleanName = "firefox" }

                if ($cleanName.ToLower() -eq $ProcessName.ToLower()) {
                    return $session
                }
            }
        }
        catch {}
        return $null
    }

    function Get-SmtcPlaybackStatus {
        param([string]$ProcessName)
        $session = Get-SmtcSessionForProcess -ProcessName $ProcessName
        if (-not $session) { return 0 }
        try {
            $playbackInfo = $session.GetPlaybackInfo()
            if ($playbackInfo) {
                return [int]$playbackInfo.PlaybackStatus
            }
        }
        catch {}
        return 0
    }

    function Invoke-SmtcActionForProcess {
        param(
            [string]$ProcessName,
            [string]$Action
        )
        $session = Get-SmtcSessionForProcess -ProcessName $ProcessName
        if (-not $session) { return $false }
        try {
            if ($Action -eq "Pause") {
                $asyncOp = $session.TryPauseAsync()
                return Wait-UwpAsync -AsyncOp $asyncOp -ResultType ([bool])
            }
            elseif ($Action -eq "Play") {
                $asyncOp = $session.TryPlayAsync()
                return Wait-UwpAsync -AsyncOp $asyncOp -ResultType ([bool])
            }
        }
        catch {}
        return $false
    }

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
            
            if ($r) {
                $stoppedAny = $true
            } else {
                Write-EventLogEntry -Message "Adapter failed to stop main mixer: $script:TargetProcessName." -EntryType "Warning" -EventId 300
            }
        } else {
            # Fallback to generic force stop if adapter is missing or has no stop func
            if (Get-Process -Name $script:TargetProcessName -ErrorAction SilentlyContinue) {
                 Log-Always "No adapter stop function ($adapterStopCmd) found for $script:TargetProcessName. Falling back to generic classic stop."
                 Write-EventLogEntry -Message "No adapter stop function ($adapterStopCmd) found for $script:TargetProcessName. Falling back to generic classic stop." -EntryType "Warning" -EventId 300
                 $r2 = Invoke-AppStop -ProcessName $script:TargetProcessName
                 if ($r2 -and $r2.Stopped) {
                     $stoppedAny = $true
                 } else {
                     Write-EventLogEntry -Message "Failed to stop main mixer process $script:TargetProcessName via classic stop fallback." -EntryType "Error" -EventId 400
                 }
            }
        }
        
        # 2. Stop all custom monitored apps if running
        if ($script:MonitoredApps) {
            $script:PlayingAppsBeforeSleep = @()
            foreach ($app in $script:MonitoredApps) {
                if (Get-Process -Name $app.ProcessName -ErrorAction SilentlyContinue) {
                    $status = Get-SmtcPlaybackStatus -ProcessName $app.ProcessName
                    if ($status -eq 4) {
                        if ($script:PlayingAppsBeforeSleep -notcontains $app.ProcessName) {
                            $script:PlayingAppsBeforeSleep += $app.ProcessName
                        }
                        Log-Always "$($app.ProcessName) was playing before sleep."
                    }

                    # Per-app RecoveryMode overrides the global OperatingMode
                    $appMode = if ($app.RecoveryMode) { $app.RecoveryMode } else { $script:OperatingMode }

                    if ($appMode -eq "PauseMedia") {
                        Log-Always "Pausing $($app.ProcessName) (PauseMedia mode)"
                        $paused = Invoke-SmtcActionForProcess -ProcessName $app.ProcessName -Action "Pause"
                        if ($paused) {
                            Log-Always "Paused $($app.ProcessName) media playback."
                            $stoppedAny = $true
                        } else {
                            Log-Always "Failed to pause $($app.ProcessName) media playback."
                        }
                    }
                    elseif ($appMode -eq "Graceful" -and (Get-Command Invoke-AppStopGraceful -ErrorAction SilentlyContinue)) {
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
                            # Graceful failed, fall back to Classic
                            Log-Always "Graceful stop failed for $($app.ProcessName), falling back to Classic"
                            Write-EventLogEntry -Message "Graceful stop failed for $($app.ProcessName), falling back to Classic." -EntryType "Warning" -EventId 300
                            $r2 = Invoke-AppStop -ProcessName $app.ProcessName
                            if ($r2 -and $r2.Stopped) {
                                Log-Always "Stopped $($app.ProcessName) (Classic fallback)"
                                $stoppedAny = $true
                            } else {
                                Write-EventLogEntry -Message "Failed to stop $($app.ProcessName) using both graceful and classic methods." -EntryType "Error" -EventId 400
                            }
                        }
                    } else {
                        Log-Always "Stopping $($app.ProcessName) (Classic mode)"
                        $r2 = Invoke-AppStop -ProcessName $app.ProcessName
                        if ($r2 -and $r2.Stopped) {
                            Log-Always "Stopped $($app.ProcessName) (Classic)"
                            $stoppedAny = $true
                        } else {
                            Write-EventLogEntry -Message "Failed to stop $($app.ProcessName) using classic method." -EntryType "Error" -EventId 400
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
            if ($r) {
                $startedAny = $true
            } else {
                Write-EventLogEntry -Message "Adapter failed to start main mixer: $script:TargetProcessName." -EntryType "Error" -EventId 400
            }
        } else {
            # Fallback to generic start if adapter is missing or has no start func
            Log-Always "No adapter start function ($adapterStartCmd) found for $script:TargetProcessName. Falling back to generic start."
            Write-EventLogEntry -Message "No adapter start function ($adapterStartCmd) found for $script:TargetProcessName. Falling back to generic start." -EntryType "Warning" -EventId 300
            $lookup = Get-AppExecutablePath -ProcessName $script:TargetProcessName -ConfiguredPath $script:TargetExePath
            if ($lookup.IsValid) {
                $result = Invoke-AppStart -ProcessName $script:TargetProcessName -ExePath $lookup.Path
                if ($result.Started) {
                    $startedAny = $true
                } else {
                    Write-EventLogEntry -Message "Failed to start main mixer process $script:TargetProcessName via generic start fallback." -EntryType "Error" -EventId 400
                }
            } else {
                Write-EventLogEntry -Message "Failed to locate executable path for main mixer process $script:TargetProcessName." -EntryType "Error" -EventId 400
            }
        }
        
        # 2. Start all custom monitored apps
        if ($script:MonitoredApps) {
            foreach ($app in $script:MonitoredApps) {
                # Determine OnWakeAction and support legacy fields if needed
                $onWake = "Smart"
                if ($app.PSObject.Properties['OnWakeAction']) {
                    $onWake = $app.OnWakeAction
                }
                elseif ($app.NoRestartOnWake -eq $true) {
                    $onWake = "KeepClosed"
                }
                elseif ($app.ForcePlayOnWake -eq $true) {
                    $onWake = "Play"
                }

                $appMode = if ($app.RecoveryMode) { $app.RecoveryMode } else { $script:OperatingMode }

                if ($onWake -eq "KeepClosed") {
                    Log-Always "Skipping restart of $($app.ProcessName) (OnWakeAction = KeepClosed)"
                    continue
                }

                # Check if already running
                $isRunning = (Get-Process -Name $app.ProcessName -ErrorAction SilentlyContinue) -ne $null
                $startedNow = $false

                if (-not $isRunning -and $appMode -ne "PauseMedia") {
                    # Resolve path using Get-AppExecutablePath helper
                    $resolvedPath = $app.ExecutablePath
                    $pathValid = $false
                    if (Get-Command Get-AppExecutablePath -ErrorAction SilentlyContinue) {
                        try {
                            $lookup = Get-AppExecutablePath -ProcessName $app.ProcessName -ConfiguredPath $app.ExecutablePath
                            if ($lookup.IsValid) {
                                $resolvedPath = $lookup.Path
                                $pathValid = $true
                            }
                        }
                        catch {
                            Log-Always "Error in dynamic lookup: $($_.Exception.Message)"
                        }
                    }
                    
                    if (-not $pathValid -and $app.ExecutablePath -and (Test-Path $app.ExecutablePath)) {
                        $resolvedPath = $app.ExecutablePath
                        $pathValid = $true
                    }

                    if ($pathValid) {
                        Log-Always "Starting $($app.ProcessName) ($resolvedPath)"
                        $result = Invoke-AppStart -ProcessName $app.ProcessName -ExePath $resolvedPath
                        if ($result.Started) {
                            $startedAny = $true
                            $isRunning = $true
                            $startedNow = $true
                        } else {
                            Write-EventLogEntry -Message "Failed to start custom monitored app $($app.ProcessName) at $resolvedPath." -EntryType "Error" -EventId 400
                        }
                    } else {
                        Log-Always "Executable for $($app.ProcessName) not found at $($app.ExecutablePath)."
                        Write-EventLogEntry -Message "Executable for custom monitored app $($app.ProcessName) not found at $($app.ExecutablePath)." -EntryType "Warning" -EventId 300
                    }
                } else {
                    if ($isRunning) {
                        Log-Always "Custom app $($app.ProcessName) is already running."
                        $startedAny = $true
                    }
                }

                # Restore playback status if app is running
                if ($isRunning) {
                    $shouldPlay = $false
                    if ($onWake -eq "Play") {
                        $shouldPlay = $true
                    }
                    elseif ($onWake -eq "Smart") {
                        if ($script:PlayingAppsBeforeSleep -contains $app.ProcessName) {
                            $shouldPlay = $true
                        }
                    }

                    if ($shouldPlay) {
                        Log-Always "Playback restoration requested for $($app.ProcessName). Polling for SMTC session (up to 15 seconds, retrying every 250 ms)."
                        $sessionFound = $false
                        $playConfirmed = $false
                        $processCrashed = $false

                        for ($i = 0; $i -lt 60; $i++) {
                            # Early Exit: Check if process is still running
                            $currentProc = Get-Process -Name $app.ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
                            if (-not $currentProc) {
                                $processCrashed = $true
                                break
                            }

                            $session = Get-SmtcSessionForProcess -ProcessName $app.ProcessName
                            if ($session) {
                                $sessionFound = $true
                                
                                # Send Play command
                                $played = Invoke-SmtcActionForProcess -ProcessName $app.ProcessName -Action "Play"
                                
                                # Sleep for 250 ms to allow playback state to transition
                                Start-Sleep -Milliseconds 250
                                
                                # Verify playback state
                                $statusVal = Get-SmtcPlaybackStatus -ProcessName $app.ProcessName
                                if ($statusVal -eq 4) {
                                    $playConfirmed = $true
                                    break
                                }
                            }
                            else {
                                # Wait 250 ms before checking again
                                Start-Sleep -Milliseconds 250
                            }
                        }

                        $loops = if ($i -ge 60) { 60 } else { $i + 1 }
                        $elapsedMs = $loops * 250
                        $timeString = if ($elapsedMs -lt 1000) { "$elapsedMs ms" } else { "$([math]::Round($elapsedMs / 1000, 2)) seconds" }

                        if ($processCrashed) {
                            Log-Always "Playback restoration failed because $($app.ProcessName) process exited or crashed during startup."
                            Write-EventLogEntry -Message "Playback restoration failed for $($app.ProcessName) because the process exited or crashed during startup." -EntryType "Error" -EventId 400
                        }
                        elseif ($playConfirmed) {
                            Log-Always "Media Control Confirmed via SMTC for $($app.ProcessName) after $loops loops ($timeString)."
                        }
                        elseif ($sessionFound) {
                            Log-Always "Play command sent to $($app.ProcessName) but playback state could not be confirmed within 15 seconds ($loops loops tried)."
                            Write-EventLogEntry -Message "Playback state could not be confirmed for $($app.ProcessName) within 15 seconds of sending Play command ($loops loops tried)." -EntryType "Warning" -EventId 300
                        }
                        else {
                            Log-Always "SMTC session not found for $($app.ProcessName) within 15 seconds ($loops loops tried). Resumption skipped."
                            Write-EventLogEntry -Message "SMTC session not found for $($app.ProcessName) within 15 seconds on wake ($loops loops tried). Playback resumption skipped." -EntryType "Warning" -EventId 300
                        }
                    }
                    elseif ($onWake -eq "Pause") {
                        Log-Always "Ensuring $($app.ProcessName) media playback is paused."
                        $paused = Invoke-SmtcActionForProcess -ProcessName $app.ProcessName -Action "Pause"
                    }
                }
            }
        }
        
        return $startedAny
    }

    # TRAY ICON
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
        $script:icon.Text = "SAMISH v1.0.9"

        $menu = New-Object System.Windows.Forms.ContextMenuStrip
        
        $settingsItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $settingsItem.Text = "Open Settings"
        
        $suffix = Get-HotkeySuffix
        $toggleItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $toggleItem.Text = "Disable helper$suffix"
        
        $exitItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $exitItem.Text = "Exit"
        
        [void]$menu.Items.Add($settingsItem)
        [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        [void]$menu.Items.Add($toggleItem)
        [void]$menu.Items.Add($exitItem)
        
        $script:icon.ContextMenuStrip = $menu

        $script:MenuToggleItem = $toggleItem

        $settingsItem.add_Click({
            $logPath = Join-Path $env:TEMP "SAMISH_tray_click.log"
            try {
                Add-Content -LiteralPath $logPath -Value "=== Clicked Open Settings at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" -ErrorAction SilentlyContinue
                
                $isSetupRunning = $false
                try {
                    $mutex = [System.Threading.Mutex]::OpenExisting("Global\SAMISH_Setup_UI")
                    if ($mutex) {
                        $isSetupRunning = $true
                        $mutex.Dispose()
                        Add-Content -LiteralPath $logPath -Value "Mutex Global\SAMISH_Setup_UI exists." -ErrorAction SilentlyContinue
                    }
                } catch [System.Threading.WaitHandleCannotBeOpenedException] {
                    Add-Content -LiteralPath $logPath -Value "Mutex does not exist." -ErrorAction SilentlyContinue
                } catch {
                    Add-Content -LiteralPath $logPath -Value "Mutex exception: $($_.Exception.GetType().FullName) - $($_.Exception.Message)" -ErrorAction SilentlyContinue
                }

                if (-not ("SamishWin32" -as [type])) {
                    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class SamishWin32 {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr FindWindow(IntPtr lpClassName, string lpWindowName);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
}
'@
                }

                # Direct window check fallback
                $hwnd = [SamishWin32]::FindWindow([IntPtr]::Zero, "SAMISH - Setup")
                Add-Content -LiteralPath $logPath -Value "FindWindow('SAMISH - Setup') returned: $hwnd" -ErrorAction SilentlyContinue
                if ($hwnd -eq [IntPtr]::Zero) {
                    $hwnd = [SamishWin32]::FindWindow([IntPtr]::Zero, "SAMISH Setup")
                    Add-Content -LiteralPath $logPath -Value "Fallback FindWindow('SAMISH Setup') returned: $hwnd" -ErrorAction SilentlyContinue
                }

                if ($hwnd -ne [IntPtr]::Zero) {
                    $isSetupRunning = $true
                }

                Add-Content -LiteralPath $logPath -Value "Effective isSetupRunning: $isSetupRunning" -ErrorAction SilentlyContinue

                if ($isSetupRunning) {
                    if ($hwnd -ne [IntPtr]::Zero) {
                        Add-Content -LiteralPath $logPath -Value "Attempting window restore & focus (SW_RESTORE=9)..." -ErrorAction SilentlyContinue
                        $showRes = [SamishWin32]::ShowWindow($hwnd, 9)
                        $foreRes = [SamishWin32]::SetForegroundWindow($hwnd)
                        Add-Content -LiteralPath $logPath -Value "ShowWindow result: $showRes, SetForegroundWindow result: $foreRes" -ErrorAction SilentlyContinue
                        
                        # Fallback for OS foreground lock: toggle topmost to force focus
                        if (-not $foreRes) {
                            Add-Content -LiteralPath $logPath -Value "SetForegroundWindow returned false. Triggering SetWindowPos topmost bypass..." -ErrorAction SilentlyContinue
                            [void][SamishWin32]::ShowWindow($hwnd, 5) # SW_SHOW
                            [void][SamishWin32]::SetWindowPos($hwnd, [IntPtr]-1, 0, 0, 0, 0, 0x0001 -bor 0x0002 -bor 0x0040) # HWND_TOPMOST, SWP_NOSIZE, SWP_NOMOVE, SWP_SHOWWINDOW
                            [void][SamishWin32]::SetWindowPos($hwnd, [IntPtr]-2, 0, 0, 0, 0, 0x0001 -bor 0x0002 -bor 0x0040) # HWND_NOTOPMOST
                            $foreRes2 = [SamishWin32]::SetForegroundWindow($hwnd)
                            Add-Content -LiteralPath $logPath -Value "Bypass completed. SetForegroundWindow retry result: $foreRes2" -ErrorAction SilentlyContinue
                        }
                    } else {
                        Add-Content -LiteralPath $logPath -Value "isSetupRunning is true, but Hwnd is Zero. Showing balloon tip." -ErrorAction SilentlyContinue
                        if ($null -ne $script:icon) {
                            $script:icon.ShowBalloonTip(3000, "SAMISH Settings", "The SAMISH settings window is already open.", [System.Windows.Forms.ToolTipIcon]::Info)
                        }
                    }
                    return
                }

                Add-Content -LiteralPath $logPath -Value "Setup is not running. Launching new instance..." -ErrorAction SilentlyContinue
                if (Test-Path -LiteralPath $ConfigPath) {
                    $cfgRaw = Get-Content -LiteralPath $ConfigPath -Raw
                    if (-not [string]::IsNullOrWhiteSpace($cfgRaw)) {
                        $cfg = $cfgRaw | ConvertFrom-Json
                        if ($cfg -and $cfg.PSObject.Properties.Name -contains "SetupPath") {
                            $setupPath = [string]$cfg.SetupPath
                            if (-not [string]::IsNullOrWhiteSpace($setupPath) -and (Test-Path -LiteralPath $setupPath)) {
                                $psi = New-Object System.Diagnostics.ProcessStartInfo
                                if ($setupPath.EndsWith(".ps1", [System.StringComparison]::OrdinalIgnoreCase)) {
                                    $psi.FileName = "powershell.exe"
                                    $psi.Arguments = "-ExecutionPolicy Bypass -NoProfile -File `"$setupPath`""
                                } else {
                                    $psi.FileName = $setupPath
                                    $psi.Arguments = ""
                                }
                                $psi.UseShellExecute = $true
                                [System.Diagnostics.Process]::Start($psi) | Out-Null
                                Add-Content -LiteralPath $logPath -Value "Started Setup process: $setupPath" -ErrorAction SilentlyContinue
                                return
                            }
                        }
                    }
                }
                
                [System.Windows.Forms.MessageBox]::Show(
                    "Settings application not found. Please run Setup.exe manually.",
                    "SAMISH Settings",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                ) | Out-Null
            }
            catch {
                Add-Content -LiteralPath $logPath -Value "Outer catch error: $_" -ErrorAction SilentlyContinue
                Log-Always "Failed to open settings: $($_.Exception.Message)"
            }
        })

        $toggleItem.add_Click({
            Set-HelperEnabled (-not $script:TrayEnabled) "TRAY MENU"
        })

        $exitItem.add_Click({
            $script:ExitRequested = $true
        })
    }

    function Notify([string]$text) {
        if ($EnableTrayIcon -and $null -ne $script:icon) {
            try { $script:icon.ShowBalloonTip(1200,"SAMISH",$text,[System.Windows.Forms.ToolTipIcon]::Info) } catch {}
        }
        Log-Always $text
    }

    function Get-HotkeySuffix {
        if (-not $EnableHotkey) { return "" }
        $keyName = $HotkeyMode
        if ($HotkeyMode -eq "Custom" -and $CustomHotkeyVirtualKey) {
            try {
                Add-Type -AssemblyName System.Windows.Forms
                $keyName = [string][System.Windows.Forms.Keys]$CustomHotkeyVirtualKey
            } catch {
                $keyName = "Custom"
            }
        }
        return " ($keyName)"
    }

    function Set-HelperEnabled([bool]$enabledNow, [string]$source) {
        # Debounce/throttle check to prevent freezing when hotkey or tray menu is clicked rapidly
        $now = Get-Date
        if ($script:LastToggleTime -and ($now - $script:LastToggleTime).TotalMilliseconds -lt 1000) {
            return
        }
        $script:LastToggleTime = $now

        $script:TrayEnabled = $enabledNow

        try {
            if ($null -ne $script:MenuToggleItem) {
                $suffix = Get-HotkeySuffix
                $script:MenuToggleItem.Text = if ($enabledNow) { "Disable helper$suffix" } else { "Enable helper$suffix" }
            }
            if ($null -ne $script:icon) {
                if ($enabledNow) {
                    $script:icon.Icon = if ($script:IconActive) { $script:IconActive } else { [System.Drawing.SystemIcons]::Application }
                } else {
                    $script:icon.Icon = if ($script:IconDisabled) { $script:IconDisabled } else { [System.Drawing.SystemIcons]::Application }
                }
            }
        } catch {}

        $stateStr = if ($enabledNow) { "ENABLED" } else { "DISABLED" }
        Log-Always ("STATE CHANGED -> " + $stateStr)
        Notify ("$source -> " + $stateStr)
        Write-EventLogEntry -Message "Helper state changed to $stateStr by $source." -EntryType "Information" -EventId 102
    }

    # HOTKEY (Polling-based)
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

    # STATE
    $lastRefresh = Get-Date "2000-01-01"
    $activeScheme = $null
    $killThresholdSeconds = $null
    $mixerStopped = $false
    $mixerStoppedAt = $null
    $stopLatchedThisIdleStretch = $false
    $script:LastBlockerLogTime = $null

    $StartupMessage = "SAMISH engine starting.`nVersion: $ScriptVersion`nOperating Mode: $OperatingMode`nActive Profile: $script:ActiveProfileId`nHotkey Enabled: $EnableHotkey`nTray Enabled: $EnableTrayIcon"
    Write-EventLogEntry -Message $StartupMessage -EntryType "Information" -EventId 100

    # MAIN LOOP
    while ($true) {
        if ($script:ExitRequested) {
            break
        }

        # DISABLED SHORT-CIRCUIT
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

        $blockerActive = $false
        if (-not $stopLatchedThisIdleStretch -and $idle -ge ($killThresholdSeconds - $ToleranceSeconds)) {
            $blockers = Test-ActiveSleepBlockerExists
            if ($blockers) {
                $blockerActive = $true
                $now = Get-Date
                if (-not $script:LastBlockerLogTime -or ($now - $script:LastBlockerLogTime).TotalSeconds -ge 30) {
                    $blockerDesc = @()
                    foreach ($b in $blockers) {
                        $blockerDesc += "$($b.Category) request by $($b.Type) $($b.Name)"
                    }
                    $blockerListString = $blockerDesc -join ", "
                    Log-Always "Active sleep blocker detected: $blockerListString. Deferring mixer shutdown."
                    $script:LastBlockerLogTime = $now
                }
            } else {
                if (Invoke-MixerStop) {
                    $mixerStopped = $true
                    $mixerStoppedAt = Get-Date
                    Write-EventLogEntry -Message "Mixer applications stopped successfully due to system idle." -EntryType "Information" -EventId 200
                }
                $stopLatchedThisIdleStretch = $true
            }
        }

        if ($mixerStopped -and $idle -le $RestartWhenIdleLE) {
            $elapsed = if ($mixerStoppedAt) { ((Get-Date) - $mixerStoppedAt).TotalSeconds } else { 9999 }
            if ($elapsed -ge $RestartGuardSecondsAfterStop) {
                if (Invoke-MixerStart) {
                    $mixerStopped = $false
                    Write-EventLogEntry -Message "Mixer applications started successfully on system wake." -EntryType "Information" -EventId 201
                }
            }
        }

        # Dynamic sleep throttle calculation
        $sleepMs = 100
        if (-not $mixerStopped -and $killThresholdSeconds) {
            $threshold = $killThresholdSeconds - $ToleranceSeconds
            $timeToThreshold = $threshold - $idle

            if ($blockerActive) {
                $sleepMs = 5000
            }
            elseif ($timeToThreshold -gt 30) {
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

            if ($script:ExitRequested) {
                break
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
}
finally {
    Write-EventLogEntry -Message "SAMISH engine shutdown." -EntryType "Information" -EventId 101
    if ($null -ne $script:icon) {
        try {
            $script:icon.Visible = $false
            $script:icon.Dispose()
        } catch {}
    }
    if ($null -ne $script:mutex) {
        try {
            $script:mutex.ReleaseMutex()
            $script:mutex.Dispose()
        } catch {}
    }
}