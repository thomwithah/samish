# Suggested filename: SAMISH.ps1
# ==========================================
# SAMISH (Streaming Audio Mixer Interface Sleep Helper)
# Engine (current device profile: BEACN)
# Created by thomwithah
# ==========================================

# Temporarily bypass execution policy for the current process to ensure dot-sourced modules can load (crucial for PS2EXE compiled EXEs)
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue

# Ensure WinForms assembly is loaded for the power state form type definition
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

# ---------- PATH RESOLUTION ----------
$PackageDir = $PSScriptRoot
if (-not $PackageDir -and $PSCommandPath) { $PackageDir = Split-Path -Parent $PSCommandPath }
if (-not $PackageDir) { $PackageDir = [System.AppDomain]::CurrentDomain.BaseDirectory }
if ($PackageDir -and $PackageDir.EndsWith("\")) { $PackageDir = $PackageDir.TrimEnd("\") }
$global:PackageDir = $PackageDir

#region Native Methods and Core Modules
$NativeMethodsPath = Join-Path $PackageDir "Modules\NativeMethods.ps1"
if (Test-Path -LiteralPath $NativeMethodsPath) {
    . $NativeMethodsPath
}

$UwpMediaPath = Join-Path $PackageDir "Modules\UwpMedia.Module.ps1"
if (Test-Path -LiteralPath $UwpMediaPath) {
    . $UwpMediaPath
}
#endregion

# ---------- VERSION ----------
$ScriptName    = "SAMISH"
$ScriptVersion = "v1.3.4"
$ReleaseDate   = "2026-06-05"

# ---------- OPTIONAL CONFIG FILE (best practice) ----------
# The GUI will later write settings here. If the file is missing, defaults below are used.
$ConfigPath = Join-Path $env:APPDATA "SAMISH\config.json"

# Load modules needed for config validation and atomic saving
$ConfigBackupModulePath = Join-Path $PackageDir "Modules\ConfigBackup.Module.ps1"
if (Test-Path -LiteralPath $ConfigBackupModulePath) {
    . $ConfigBackupModulePath
}
$CommonModulePath = Join-Path $PackageDir "Modules\App.Control.Common.ps1"
if (Test-Path -LiteralPath $CommonModulePath) {
    . $CommonModulePath
}

function Apply-ConfigFromFile {
    if (-not (Test-Path -LiteralPath $ConfigPath)) { return }
    try {
        $raw = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return }

        $cfg = $null
        $jsonError = $false
        try {
            $cfg = $raw | ConvertFrom-Json -ErrorAction Stop
        } catch {
            $jsonError = $true
            $cfg = [pscustomobject]@{}
        }
        
        if (Get-Command Test-ConfigSchema -ErrorAction SilentlyContinue) {
            $cfg = Merge-ConfigDefaults -Config $cfg
            $schemaRes = Test-ConfigSchema -Config $cfg -AutoFix
            if ($jsonError -or $schemaRes.FixedKeys.Count -gt 0) {
                # Create a timestamped backup before overwriting the config
                try {
                    $ts = (Get-Date).ToString("yyyyMMdd-HHmmss")
                    $backupPath = $ConfigPath + ".backup-$ts"
                    Copy-Item -LiteralPath $ConfigPath -Destination $backupPath -Force -ErrorAction Stop

                    # Prune old backups: keep only the 5 most recent
                    $configDir = Split-Path -Parent $ConfigPath
                    $backups = Get-ChildItem -LiteralPath $configDir -Filter "config.json.backup-*" -File -ErrorAction SilentlyContinue |
                        Sort-Object LastWriteTime -Descending |
                        Select-Object -Skip 5
                    foreach ($old in $backups) {
                        Remove-Item -LiteralPath $old.FullName -Force -ErrorAction SilentlyContinue
                    }
                } catch {
                    # Fail-forward: if backup fails, still proceed with the fix
                }

                if (Get-Command Save-ContentAtomic -ErrorAction SilentlyContinue) {
                    $json = $cfg | ConvertTo-Json -Depth 3
                    Save-ContentAtomic -Path $ConfigPath -Content $json
                }

                # Log the auto-fix details (Log-Always may not be available this early)
                try {
                    if (Get-Command Log-Always -ErrorAction SilentlyContinue) {
                        if ($jsonError) {
                            Log-Always "Config: JSON parse error detected. Original backed up to $backupPath. Config rebuilt from defaults."
                        }
                        if ($schemaRes.FixedKeys.Count -gt 0) {
                            Log-Always "Config: Auto-fixed $($schemaRes.FixedKeys.Count) key(s): $($schemaRes.FixedKeys -join ', '). Original backed up to $backupPath."
                        }
                    }
                } catch {
                    # Fail-forward: logging is best-effort
                }
            }
        }

        foreach ($p in $cfg.PSObject.Properties) {
            $name = $p.Name
            $val  = $p.Value

            if (Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue) {
                Set-Variable -Name $name -Value $val -Scope Script -Force
            }
        }

        # Map OperatingMode -> OperatingMode (so engine behavior actually changes)
        if ($cfg.PSObject.Properties.Name -contains "OperatingMode") {
            if (Get-Variable -Name "OperatingMode" -Scope Script -ErrorAction SilentlyContinue) {
                $script:OperatingMode = [string]$cfg.OperatingMode
            }
        }

    } catch {
        # Best effort only -- but log to event log for troubleshooting
        try { Write-EventLogEntry -Message "Apply-ConfigFromFile failed: $($_.Exception.Message)" -EntryType "Warning" -EventId 300 } catch {}
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

# ---------- CONFIG DEFAULTS (legacy, still supported) ----------
# These will be overridden by config.json (if present) and later by Setup UI.
$TargetExePath     = "C:\Program Files\BEACN\BEACN App\BEACN.exe"
$TargetProcessName = "BEACN"
$OperatingMode = "Graceful"          # Classic | Graceful
$GracefulWindowWakeDelayMs = 800        # Delay after restoring UI window
$GracefulShutdownWaitMs = 800           # Wait for graceful exit before fallback
$MonitoredApps = @()
$script:PlayingAppsBeforeSleep = @()

$GameModeEnabled = $false
$GameModeList = @()
$script:GameModeActive = $false

$PreferredPlaybackDeviceGuid = ""
$PreferredPlaybackDeviceName = ""
$PreferredCommDeviceGuid = ""
$PreferredCommDeviceName = ""

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

$EnableAutoRecovery = $true
$script:LastAutoRecoveryCheckTime = $null
$script:MonitoredAppPlayStates = @{}
$script:MonitoredAppLastRelaunchTime = @{}
$script:MonitoredAppSeenRunning = @{}
$script:LastConfigWriteTime = $null

# Load optional config file overrides
Apply-ConfigFromFile
if (Test-Path -LiteralPath $ConfigPath) {
    $script:LastConfigWriteTime = (Get-Item -LiteralPath $ConfigPath).LastWriteTime
}

$script:HotkeySuffix = Get-HotkeySuffix

# ---------- POWER PLAN COMMON (shared read utilities) ----------
$PowerPlanCommonPath = Join-Path $PackageDir "Modules\PowerPlan.Read.Common.ps1"
if (Test-Path -LiteralPath $PowerPlanCommonPath) {
    try { . $PowerPlanCommonPath } catch {
        try { Write-EventLogEntry -Message "PowerPlan.Read.Common.ps1 dot-source failed: $($_.Exception.Message)" -EntryType "Warning" -EventId 300 } catch {}
    }
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

$GameModeGuardPsm1 = Join-Path $PackageDir "Modules\GameModeGuard.psm1"
$GameModeGuardPs1  = Join-Path $PackageDir "Modules\GameModeGuard.ps1"
if (Test-Path -LiteralPath $GameModeGuardPsm1) {
    Import-Module $GameModeGuardPsm1 -Force -ErrorAction SilentlyContinue
}
elseif (Test-Path -LiteralPath $GameModeGuardPs1) {
    . $GameModeGuardPs1
}

$AudioEndpointPsm1 = Join-Path $PackageDir "Modules\AudioEndpoint.psm1"
$AudioEndpointPs1  = Join-Path $PackageDir "Modules\AudioEndpoint.ps1"
if (Test-Path -LiteralPath $AudioEndpointPsm1) {
    Import-Module $AudioEndpointPsm1 -Force -ErrorAction SilentlyContinue
}
elseif (Test-Path -LiteralPath $AudioEndpointPs1) {
    . $AudioEndpointPs1
}

# ---------- LOGGING ----------
$LoggerModulePath = Join-Path $PackageDir "Modules\Logger.psm1"
if (Test-Path -LiteralPath $LoggerModulePath) {
    Import-Module $LoggerModulePath -Force -DisableNameChecking
}

$script:LastHeartbeat = Get-Date "2000-01-01"

# Write-EventLogEntry, Resolve-SamishLogPath, and Rotate-LogFileIfNeeded
# are now imported from Logger.psm1.



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
$script:PendingNotificationSource = $null
$script:PendingNotificationState = $null
$script:LastToggleTime = $null
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
    # (SamishIdleNative loaded via NativeMethods.ps1)

    function Get-IdleSeconds {
        if ($global:IdleNativeError) { return 0 }
        [math]::Floor([SamishIdleNative]::GetIdleMilliseconds() / 1000)
    }

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

    function Invoke-MixerStop {
        $stoppedAny = $false

        # 1. Stop Main Mixer via active adapter
        $adapterStopCmd = "Stop-$($script:ActiveProfileId)Adapter"
        if (Get-Command $adapterStopCmd -ErrorAction SilentlyContinue) {
            try {
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
            } catch {
                Write-EventLogEntry -Message "Adapter threw an exception stopping main mixer: $_" -EntryType "Error" -EventId 400
                Log-Always "Adapter Stop function failed: $_"
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

    function Start-MainMixer {
        $adapterStartCmd = "Start-$($script:ActiveProfileId)Adapter"
        if (Get-Command $adapterStartCmd -ErrorAction SilentlyContinue) {
            $r = & $adapterStartCmd -ProcessName $script:TargetProcessName -ConfiguredPath $script:TargetExePath
            if ($r) {
                return $true
            } else {
                Write-EventLogEntry -Message "Adapter failed to start main mixer: $script:TargetProcessName." -EntryType "Error" -EventId 400
            }
        } else {
            Log-Always "No adapter start function ($adapterStartCmd) found for $script:TargetProcessName. Falling back to generic start."
            Write-EventLogEntry -Message "No adapter start function ($adapterStartCmd) found for $script:TargetProcessName. Falling back to generic start." -EntryType "Warning" -EventId 300
            $lookup = Get-AppExecutablePath -ProcessName $script:TargetProcessName -ConfiguredPath $script:TargetExePath
            if ($lookup.IsValid) {
                $result = Invoke-AppStart -ProcessName $script:TargetProcessName -ExePath $lookup.Path
                if ($result.Started) {
                    return $true
                } else {
                    Write-EventLogEntry -Message "Failed to start main mixer process $script:TargetProcessName via generic start fallback." -EntryType "Error" -EventId 400
                }
            } else {
                Write-EventLogEntry -Message "Failed to locate executable path for main mixer process $script:TargetProcessName." -EntryType "Error" -EventId 400
            }
        }
        return $false
    }

    function Relaunch-MonitoredApp {
        param(
            $App,
            [bool]$RestorePlayState
        )

        $resolvedPath = $App.ExecutablePath
        $pathValid = $false
        if (Get-Command Get-AppExecutablePath -ErrorAction SilentlyContinue) {
            try {
                $lookup = Get-AppExecutablePath -ProcessName $App.ProcessName -ConfiguredPath $App.ExecutablePath
                if ($lookup.IsValid) {
                    $resolvedPath = $lookup.Path
                    $pathValid = $true
                }
            }
            catch {
                Log-Always "Error in dynamic lookup during recovery: $($_.Exception.Message)"
            }
        }
        
        if (-not $pathValid -and $App.ExecutablePath -and (Test-Path $App.ExecutablePath)) {
            $resolvedPath = $App.ExecutablePath
            $pathValid = $true
        }

        if ($pathValid) {
            Log-Always "Auto-recovering monitored app: $($App.ProcessName) ($resolvedPath)"
            Write-EventLogEntry -Message "Monitored app $($App.ProcessName) was not running. Automatically recovering process." -EntryType "Warning" -EventId 303
            $result = Invoke-AppStart -ProcessName $App.ProcessName -ExePath $resolvedPath
            if ($result.Started) {
                if ($RestorePlayState) {
                    Log-Always "Playback restoration requested for $($App.ProcessName) during recovery. Polling for SMTC session (up to 15 seconds)."
                    $sessionFound = $false
                    $playConfirmed = $false
                    $processCrashed = $false

                    for ($i = 0; $i -lt 60; $i++) {
                        $currentProc = Get-Process -Name $App.ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
                        if (-not $currentProc) {
                            $processCrashed = $true
                            break
                        }

                        $session = Get-SmtcSessionForProcess -ProcessName $App.ProcessName
                        if ($session) {
                            $sessionFound = $true
                            $played = Invoke-SmtcActionForProcess -ProcessName $App.ProcessName -Action "Play"
                            Start-Sleep -Milliseconds 250
                            
                            $statusVal = Get-SmtcPlaybackStatus -ProcessName $App.ProcessName
                            if ($statusVal -eq 4) {
                                $playConfirmed = $true
                                break
                            }
                        }
                        else {
                            Start-Sleep -Milliseconds 250
                        }
                    }

                    $loops = if ($i -ge 60) { 60 } else { $i + 1 }
                    $elapsedMs = $loops * 250
                    $timeString = if ($elapsedMs -lt 1000) { "$elapsedMs ms" } else { "$([math]::Round($elapsedMs / 1000, 2)) seconds" }

                    if ($processCrashed) {
                        Log-Always "Playback restoration failed because $($App.ProcessName) process exited or crashed during startup."
                    }
                    elseif ($playConfirmed) {
                        Log-Always "Media Control Confirmed via SMTC for $($App.ProcessName) after $loops loops ($timeString) during recovery."
                    }
                    elseif ($sessionFound) {
                        Log-Always "Play command sent to $($App.ProcessName) but playback state could not be confirmed within 15 seconds."
                    }
                    else {
                        Log-Always "No SMTC session found for $($App.ProcessName) within 15 seconds."
                    }
                }
                return $true
            } else {
                Write-EventLogEntry -Message "Failed to start monitored app $($App.ProcessName) at $resolvedPath during recovery." -EntryType "Error" -EventId 400
            }
        } else {
            Log-Always "Executable for $($App.ProcessName) not found at $($App.ExecutablePath) during recovery."
            Write-EventLogEntry -Message "Executable for custom monitored app $($App.ProcessName) not found at $($App.ExecutablePath) during recovery." -EntryType "Warning" -EventId 300
        }
        return $false
    }

    function Perform-AutoRecoveryCheck {
        # 1. Main Mixer Auto-Recovery
        if ($EnableAutoRecovery) {
            $mixerRunning = $null -ne (Get-Process -Name $script:TargetProcessName -ErrorAction SilentlyContinue)
            if (-not $mixerRunning) {
                Log-Always "Main mixer process '$script:TargetProcessName' is not running. Starting recovery..."
                Write-EventLogEntry -Message "Main mixer process '$script:TargetProcessName' was not running. Automatically recovering process." -EntryType "Warning" -EventId 302
                
                $started = Start-MainMixer
                if ($started) {
                    Log-Always "Main mixer process '$script:TargetProcessName' recovered successfully."
                } else {
                    Log-Always "Failed to recover main mixer process '$script:TargetProcessName'."
                }
            }
        }

        # 2. Monitored Apps Auto-Recovery
        if ($script:MonitoredApps) {
            foreach ($app in $script:MonitoredApps) {
                try {
                    $autoRecoverEnabled = $false
                    if ($app.PSObject.Properties.Match('AutoRecover').Count -gt 0) {
                        $autoRecoverEnabled = [bool]$app.AutoRecover
                    }

                    # Read OnWakeAction -- skip recovery entirely for KeepClosed
                    $onWake = "Smart"
                    if ($app.PSObject.Properties.Match('OnWakeAction').Count -gt 0) {
                        $onWake = $app.OnWakeAction
                    }
                    if ($onWake -eq "KeepClosed") { continue }

                    # UWP apps (Spotify, etc.) keep background workers alive after UI close;
                    # filter by MainWindowHandle to detect actual UI presence.
                    # Desktop/tray apps (BEACN, etc.) have no main window; check process only.
                    $isUwp = ($app.ProcessName -eq "Spotify") -or
                        ($app.PSObject.Properties.Match('ExecutablePath').Count -gt 0 -and
                         $app.ExecutablePath -like "*\WindowsApps\*")

                    if ($isUwp) {
                        $isRunning = $null -ne (Get-Process -Name $app.ProcessName -ErrorAction SilentlyContinue |
                            Where-Object { $_.MainWindowHandle -ne 0 } |
                            Select-Object -First 1)
                    }
                    else {
                        $isRunning = $null -ne (Get-Process -Name $app.ProcessName -ErrorAction SilentlyContinue |
                            Select-Object -First 1)
                    }

                    if ($isRunning) {
                        # Track that we've seen this app running during this engine session
                        $script:MonitoredAppSeenRunning[$app.ProcessName] = $true
                        # Track play state dynamically
                        $status = Get-SmtcPlaybackStatus -ProcessName $app.ProcessName
                        if ($status -eq 4) {
                            $script:MonitoredAppPlayStates[$app.ProcessName] = $true
                        } else {
                            $script:MonitoredAppPlayStates[$app.ProcessName] = $false
                        }
                    } else {
                        # Not running. Relaunch if monitoring is enabled.
                        if ($autoRecoverEnabled) {
                            # Only recover apps the engine has actually seen running during this session.
                            # This prevents auto-launching apps that weren't running when the engine started.
                            if (-not $script:MonitoredAppSeenRunning[$app.ProcessName]) {
                                continue
                            }

                            # Cooldown: skip if we already tried to relaunch this app within the last 30 seconds
                            # This prevents rapid-fire launches while UWP apps are still starting (MainWindowHandle = 0)
                            $lastRelaunch = $script:MonitoredAppLastRelaunchTime[$app.ProcessName]
                            if ($lastRelaunch -and ((Get-Date) - $lastRelaunch).TotalSeconds -lt 30) {
                                continue
                            }

                            # Determine media action based on OnWakeAction
                            $restorePlay = $false
                            switch ($onWake) {
                                "Smart" {
                                    $restorePlay = [bool]$script:MonitoredAppPlayStates[$app.ProcessName]
                                }
                                "Play" {
                                    $restorePlay = $true
                                }
                                "Pause" {
                                    $restorePlay = $false
                                }
                                "ReopenOnly" {
                                    $restorePlay = $false
                                }
                                default {
                                    $restorePlay = [bool]$script:MonitoredAppPlayStates[$app.ProcessName]
                                }
                            }

                            $script:MonitoredAppLastRelaunchTime[$app.ProcessName] = Get-Date
                            $recovered = Relaunch-MonitoredApp -App $app -RestorePlayState $restorePlay
                            # Only clear tracking state after successful recovery
                            if ($recovered) {
                                $script:MonitoredAppPlayStates[$app.ProcessName] = $false
                            }
                        }
                    }
                } catch {
                    Log-Always "Error in auto-recovery for $($app.ProcessName): $($_.Exception.Message)"
                }
            }
        }
    }

    function Invoke-MixerStart {
        $startedAny = $false
        
        # 1. Start Main Mixer via helper
        if (Start-MainMixer) {
            $startedAny = $true
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
                $isRunning = $null -ne (Get-Process -Name $app.ProcessName -ErrorAction SilentlyContinue)
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
                    elseif ($onWake -eq "Pause" -or ($onWake -eq "Smart" -and -not $shouldPlay)) {
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
        } catch {
            try { Write-EventLogEntry -Message "Tray icon asset load failed: $($_.Exception.Message)" -EntryType "Warning" -EventId 300 } catch {}
        }

        $script:icon.Icon = if ($script:IconActive) { $script:IconActive } else { [System.Drawing.SystemIcons]::Application }
        $script:icon.Visible = $true

        # Note: NotifyIcon.Text has a short length limit
        $script:icon.Text = "SAMISH v1.3.4"

        $menu = New-Object System.Windows.Forms.ContextMenuStrip
        
        $settingsItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $settingsItem.Text = "Open Settings"
        
        $toggleItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $toggleItem.Text = "Disable helper$script:HotkeySuffix"
        
        $exitItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $exitItem.Text = "Exit"
        
        [void]$menu.Items.Add($settingsItem)
        [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        [void]$menu.Items.Add($toggleItem)
        [void]$menu.Items.Add($exitItem)
        
        $script:icon.ContextMenuStrip = $menu

        $script:MenuToggleItem = $toggleItem

        $script:icon.add_DoubleClick({
            $settingsItem.PerformClick()
        })

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
                    # Already compiled in NativeMethods.ps1
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
                $setupPath = $null
                # Resolve config path: prefer captured $ConfigPath, then $global:PackageDir-based
                $resolvedConfigPath = $ConfigPath
                if ([string]::IsNullOrWhiteSpace($resolvedConfigPath)) {
                    $resolvedConfigPath = Join-Path $env:APPDATA "SAMISH\config.json"
                }
                Add-Content -LiteralPath $logPath -Value "ConfigPath resolved to: $resolvedConfigPath" -ErrorAction SilentlyContinue
                if (Test-Path -LiteralPath $resolvedConfigPath) {
                    $cfgRaw = Get-Content -LiteralPath $resolvedConfigPath -Raw
                    if (-not [string]::IsNullOrWhiteSpace($cfgRaw)) {
                        $cfg = $cfgRaw | ConvertFrom-Json
                        if ($cfg -and $cfg.PSObject.Properties.Name -contains "SetupPath") {
                            $setupPath = [string]$cfg.SetupPath
                        }
                    }
                }
                
                # Robust fallback to parent directory if SetupPath is missing or invalid
                if ([string]::IsNullOrWhiteSpace($setupPath) -or -not (Test-Path -LiteralPath $setupPath)) {
                    # Use $PackageDir if available in this scope, otherwise fall back to $global:PackageDir
                    $resolvedPackageDir = $PackageDir
                    if ([string]::IsNullOrWhiteSpace($resolvedPackageDir)) { $resolvedPackageDir = $global:PackageDir }
                    Add-Content -LiteralPath $logPath -Value "PackageDir resolved to: $resolvedPackageDir" -ErrorAction SilentlyContinue
                    if (-not [string]::IsNullOrWhiteSpace($resolvedPackageDir)) {
                        $parentDir = Split-Path -Parent $resolvedPackageDir
                        $candidateExe = Join-Path $parentDir "Setup.exe"
                        $candidateBat = Join-Path $parentDir "Setup.bat"
                        $candidatePs1 = Join-Path $parentDir "Setup.ps1"
                        Add-Content -LiteralPath $logPath -Value "Checking: $candidateExe, $candidateBat, $candidatePs1" -ErrorAction SilentlyContinue
                        if (Test-Path -LiteralPath $candidateExe) {
                            $setupPath = $candidateExe
                        } elseif (Test-Path -LiteralPath $candidateBat) {
                            $setupPath = $candidateBat
                        } elseif (Test-Path -LiteralPath $candidatePs1) {
                            $setupPath = $candidatePs1
                        }
                    }
                }
                
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

    function Set-HelperEnabled([bool]$enabledNow, [string]$source) {
        $script:TrayEnabled = $enabledNow
        $script:LastToggleTime = [DateTime]::UtcNow

        try {
            if ($null -ne $script:MenuToggleItem) {
                $script:MenuToggleItem.Text = if ($enabledNow) { "Disable helper$script:HotkeySuffix" } else { "Enable helper$script:HotkeySuffix" }
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

        $script:PendingNotificationSource = $source
        $script:PendingNotificationState = $enabledNow
    }

    function Check-PendingNotification {
        if ($null -ne $script:PendingNotificationSource) {
            $elapsedMs = ([DateTime]::UtcNow - $script:LastToggleTime).TotalMilliseconds
            if ($elapsedMs -ge 800) {
                $source = $script:PendingNotificationSource
                $state = $script:PendingNotificationState
                $script:PendingNotificationSource = $null # Clear first to prevent re-entry / duplicate checks

                $stateStr = if ($state) { "ENABLED" } else { "DISABLED" }
                Notify ("$source -> " + $stateStr)
                Write-EventLogEntry -Message "Helper state changed to $stateStr by $source." -EntryType "Information" -EventId 102
            }
        }
    }

    # HOTKEY (Polling-based)
    if ($EnableHotkey) {
        if (-not ([System.Management.Automation.PSTypeName]'SamishKeyState').Type) {
            Log-Always "ERROR: SamishKeyState helper not loaded. Disabling hotkey polling."
            Write-EventLogEntry -Message "SamishKeyState helper not loaded" -EntryType "Error" -EventId 400
            $EnableHotkey = $false
        }

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
    $script:mixerStopped = $false
    $script:mixerStoppedAt = $null
    $script:stopLatchedThisIdleStretch = $false
    $script:LastBlockerLogTime = $null

    # ---------- INITIALIZE POWER STATE INTERCEPTOR ----------
    try {
        if ($global:PowerTypeSigError) {
            Log-Always "ERROR: Power State Interceptor compilation failed. OS policies may block runtime C# compilation. Details: $global:PowerTypeSigError"
            Write-EventLogEntry -Message "Power State Interceptor compilation failed: $script:PowerTypeSigError" -EntryType "Error" -EventId 400
        }
        if ($script:IdleNativeError) {
            Log-Always "ERROR: IdleNative helper compilation failed. OS policies may block runtime C# compilation. Idle checks will be disabled. Details: $script:IdleNativeError"
            Write-EventLogEntry -Message "IdleNative helper compilation failed: $script:IdleNativeError" -EntryType "Error" -EventId 400
        }
        Log-Always "Initializing Power State Interceptor (WM_POWERBROADCAST)..."
        $script:PowerForm = New-Object PowerNotificationForm
        # Accessing the handle forces creation of the window and its handle
        $null = $script:PowerForm.Handle
        
        $script:PowerFormEventJob = Register-ObjectEvent -InputObject $script:PowerForm -EventName "PowerEventOccurred" -Action {
            $eventType = $EventArgs.EventType
            # $eventType: 4 = PBT_APMSUSPEND, 18 = PBT_APMRESUMEAUTOMATIC, 7 = PBT_APMRESUMESUSPEND
            if ($eventType -eq 4) {
                Log-Always "[Power Event] WM_POWERBROADCAST: PBT_APMSUSPEND detected. Preemptively shutting down mixer."
                Write-EventLogEntry -Message "System suspend detected via WM_POWERBROADCAST. Preemptively stopping mixer applications." -EntryType "Information" -EventId 202
                if (Invoke-MixerStop) {
                    $script:mixerStopped = $true
                    $script:mixerStoppedAt = Get-Date
                    $script:stopLatchedThisIdleStretch = $true
                }
            }
            elseif ($eventType -eq 18 -or $eventType -eq 7) {
                Log-Always "[Power Event] WM_POWERBROADCAST: System resume detected ($eventType). Instantly starting mixer."
                Write-EventLogEntry -Message "System resume detected via WM_POWERBROADCAST. Instantly starting mixer applications." -EntryType "Information" -EventId 203
                
                # Reset idle latch state and set mixerStopped to true so start guard resolves correctly
                $script:stopLatchedThisIdleStretch = $false
                $script:mixerStopped = $true
                $script:mixerStoppedAt = Get-Date "2000-01-01"
                
                if (Invoke-MixerStart) {
                    $script:mixerStopped = $false

                    # Restore preferred audio endpoints after mixer restart
                    if (Get-Command Set-DefaultAudioDevice -ErrorAction SilentlyContinue) {
                        if ($PreferredPlaybackDeviceGuid -or $PreferredCommDeviceGuid) {
                            try {
                                Set-DefaultAudioDevice -PlaybackDeviceId $PreferredPlaybackDeviceGuid -CommDeviceId $PreferredCommDeviceGuid
                            }
                            catch {
                                Log-Always "AudioEndpoint: Post-wake restore failed: $_"
                            }
                        }
                    }
                }
            }
        }
        Log-Always "Power State Interceptor successfully registered."
    } catch {
        Log-Always "WARN: Failed to initialize Power State Interceptor: $_"
    }

    $StartupMessage = "SAMISH engine starting.`nVersion: $ScriptVersion`nOperating Mode: $OperatingMode`nActive Profile: $script:ActiveProfileId`nHotkey Enabled: $EnableHotkey`nTray Enabled: $EnableTrayIcon`nGame Mode: $(if ($GameModeEnabled) { 'Enabled (' + ($GameModeList -join ', ') + ')' } else { 'Disabled' })"
    Write-EventLogEntry -Message $StartupMessage -EntryType "Information" -EventId 100

    # Write PID file so diagnostics can find us (CIM can't read CommandLine of elevated Task Scheduler processes)
    $script:PidFilePath = Join-Path $PSScriptRoot "samish.pid"
    try { Set-Content -LiteralPath $script:PidFilePath -Value $PID -Encoding UTF8 -Force } catch {
        try { Log-Always "PID file write failed: $($_.Exception.Message)" } catch {}
    }

    # SELF-HEALING ENGINE WRAPPER
    # If the main loop throws an unhandled exception, catch it and retry with exponential backoff.
    # Backoff caps at half the screen-off/idle threshold to ensure the engine is alive before idle fires.
    $script:engineBackoffSeconds = 10  # measured in sec -- initial retry delay
    $script:engineMaxBackoff = [Math]::Max(60, [Math]::Floor($killThresholdSeconds / 2))  # measured in sec
    $script:engineStableStart = Get-Date

    while ($true) {
        if ($script:ExitRequested) { break }
        try {

    # MAIN LOOP
    while ($true) {
        if ($script:ExitRequested) {
            break
        }

        # DISABLED SHORT-CIRCUIT
        # Process GUI messages (DoEvents), hotkey polling, and pending notifications even when disabled,
        # while bypassing main loop logic (idle and app checks).
        if ($script:TrayEnabled -eq $false) {
            if ($EnableTrayIcon) {
                try { [System.Windows.Forms.Application]::DoEvents() } catch {}
            }
            if ($EnableHotkey) {
                $isDown = ([SamishKeyState]::GetAsyncKeyState($vk) -band 0x8000) -ne 0
                if ($isDown -and -not $script:LastKeyDown) {
                    Set-HelperEnabled (-not $script:TrayEnabled) "HOTKEY"
                }
                $script:LastKeyDown = $isDown
            }
            Check-PendingNotification
            Start-Sleep -Milliseconds 100
            continue
        }

        # Auto-Recovery check (throttled to run every 10 seconds)
        # Run if either global auto-recovery is enabled OR any monitored app has per-app AutoRecover
        $hasAutoRecoverMonitoredApps = $false
        if ($script:MonitoredApps) {
            foreach ($monApp in $script:MonitoredApps) {
                if ($monApp.PSObject.Properties.Match('AutoRecover').Count -gt 0 -and [bool]$monApp.AutoRecover) {
                    $hasAutoRecoverMonitoredApps = $true
                    break
                }
            }
        }
        if (($EnableAutoRecovery -or $hasAutoRecoverMonitoredApps) -and $script:mixerStopped -eq $false) {
            $nowTime = Get-Date
            if ($null -eq $script:LastAutoRecoveryCheckTime) {
                $script:LastAutoRecoveryCheckTime = $nowTime.AddSeconds(-10)
            }
            if (($nowTime - $script:LastAutoRecoveryCheckTime).TotalSeconds -ge 10) {
                $script:LastAutoRecoveryCheckTime = $nowTime
                try {
                    # Dynamically reload configuration if config.json was updated
                    if (Test-Path -LiteralPath $ConfigPath) {
                        $writeTime = (Get-Item -LiteralPath $ConfigPath).LastWriteTime
                        if ($null -eq $script:LastConfigWriteTime -or $writeTime -gt $script:LastConfigWriteTime) {
                            $script:LastConfigWriteTime = $writeTime
                            Log-Always "Reloading updated configuration from config.json"
                            Apply-ConfigFromFile
                        }
                    }
                    Perform-AutoRecoveryCheck
                }
                catch {
                    Log-Always "Error during auto-recovery check: $($_.Exception.Message)"
                }
            }
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

        # Game-Mode Guard: update state at heartbeat frequency
        $script:GameModeActive = Invoke-GameModeCheck -Enabled $script:GameModeEnabled -GameList $script:GameModeList

        $idle = Get-IdleSeconds
        Log-Heartbeat "Loop: idle=$idle threshold=$killThresholdSeconds gameMode=$($script:GameModeActive) PID=$PID"

        # Reset self-healing backoff after 5 minutes of stable operation
        if ($script:engineBackoffSeconds -gt 10) {
            $stableMinutes = ((Get-Date) - $script:engineStableStart).TotalMinutes
            if ($stableMinutes -ge 5) {
                $script:engineBackoffSeconds = 10  # measured in sec -- reset to initial
            }
        } else {
            $script:engineStableStart = Get-Date
        }

        if ($idle -le 1) { $script:stopLatchedThisIdleStretch = $false }

        if (-not $killThresholdSeconds) {
            Start-Sleep -Milliseconds 100
            continue
        }

        $blockerActive = $false
        if (-not $script:stopLatchedThisIdleStretch -and $idle -ge ($killThresholdSeconds - $ToleranceSeconds)) {
            # Game-Mode Guard: skip idle-based mixer shutdown while a listed game is running.
            # WM_POWERBROADCAST suspend/resume events still fire normally (real sleep, not idle).
            if ($script:GameModeActive) {
                $blockerActive = $true
                $now = Get-Date
                if (-not $script:LastBlockerLogTime -or ($now - $script:LastBlockerLogTime).TotalSeconds -ge 30) {
                    Log-Always "Game mode active - deferring idle mixer shutdown."
                    $script:LastBlockerLogTime = $now
                }
            }
            else {
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
                        $script:mixerStopped = $true
                        $script:mixerStoppedAt = Get-Date
                        Write-EventLogEntry -Message "Mixer applications stopped successfully due to system idle." -EntryType "Information" -EventId 200
                    }
                    $script:stopLatchedThisIdleStretch = $true
                }
            }
        }

        if ($script:mixerStopped -and $idle -le $RestartWhenIdleLE) {
            $elapsed = if ($script:mixerStoppedAt) { ((Get-Date) - $script:mixerStoppedAt).TotalSeconds } else { 9999 }
            if ($elapsed -ge $RestartGuardSecondsAfterStop) {
                if (Invoke-MixerStart) {
                    $script:mixerStopped = $false
                    Write-EventLogEntry -Message "Mixer applications started successfully on system wake." -EntryType "Information" -EventId 201

                    # Restore preferred audio endpoints after mixer restart
                    if (Get-Command Set-DefaultAudioDevice -ErrorAction SilentlyContinue) {
                        if ($PreferredPlaybackDeviceGuid -or $PreferredCommDeviceGuid) {
                            try {
                                Set-DefaultAudioDevice -PlaybackDeviceId $PreferredPlaybackDeviceGuid -CommDeviceId $PreferredCommDeviceGuid
                            }
                            catch {
                                Log-Always "AudioEndpoint: Post-restart restore failed: $_"
                            }
                        }
                    }
                }
            }
        }

        # Dynamic sleep throttle calculation
        $sleepMs = 100
        if (-not $script:mixerStopped -and $killThresholdSeconds) {
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
            try { [System.Windows.Forms.Application]::DoEvents() } catch {}

            if ($script:ExitRequested -or $script:TrayEnabled -eq $false) {
                break
            }

            if ($EnableHotkey) {
                $isDown = ([SamishKeyState]::GetAsyncKeyState($vk) -band 0x8000) -ne 0
                if ($isDown -and -not $script:LastKeyDown) {
                    Set-HelperEnabled (-not $script:TrayEnabled) "HOTKEY"
                }
                $script:LastKeyDown = $isDown
            }
            Check-PendingNotification

            Start-Sleep -Milliseconds 100
            $sleptMs += 100
        }
    }
    # End of inner main loop -- clean exit via $ExitRequested
    break  # Exit the outer self-healing loop too

        } catch {
            # Self-healing: log the error and retry with exponential backoff
            $errMsg = "Engine loop error (will retry in $($script:engineBackoffSeconds)s): $($_.Exception.Message)"
            try { Log-Always $errMsg } catch {}
            try {
                Write-EventLogEntry -Message $errMsg -EntryType "Error" -EventId 500
            } catch {}

            Start-Sleep -Seconds $script:engineBackoffSeconds
            $script:engineBackoffSeconds = [Math]::Min($script:engineBackoffSeconds * 2, $script:engineMaxBackoff)
        }
    }  # End of outer self-healing loop
}
finally {
    Write-EventLogEntry -Message "SAMISH engine shutdown." -EntryType "Information" -EventId 101
    if ($null -ne $script:PowerFormEventJob) {
        try { Unregister-Event -SourceIdentifier $script:PowerFormEventJob.SourceIdentifier -ErrorAction SilentlyContinue } catch {}
    }
    if ($null -ne $script:PowerForm) {
        try {
            $script:PowerForm.Close()
            $script:PowerForm.Dispose()
        } catch {}
    }
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
    # Clean up PID file
    if ($script:PidFilePath -and (Test-Path -LiteralPath $script:PidFilePath)) {
        try { Remove-Item -LiteralPath $script:PidFilePath -Force -ErrorAction SilentlyContinue } catch {}
    }
}