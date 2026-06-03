# =============================================================================
# SAMISH Telemetry Actions & Backups Helpers
# =============================================================================

# Developer Note: Registry modification commands for USB Selective Suspend keys 
# require Administrator privileges and targeting HKLM paths. Backup values 
# are stored in config.json under 'backups' key. Overrides must complete 
# execution in under 300 ms.

$script:DeviceWakeBackupPath = Join-Path $env:APPDATA "SAMISH\device_wake_backup.json"
$script:TaskWakeBackupPath = Join-Path $env:APPDATA "SAMISH\task_wake_backup.json"
$script:ServiceWakeBackupPath = Join-Path $env:APPDATA "SAMISH\service_wake_backup.json"

function Merge-ConfigDefaults {
    <#
    .SYNOPSIS
        Injects missing keys with default values into a config PSObject.

    .DESCRIPTION
        Called on config load to ensure forward-compatibility when users upgrade
        SAMISH and their config.json is missing keys added in newer versions.
        Returns the original object with any missing properties added.

    .PARAMETER Config
        The PSObject loaded from config.json (via ConvertFrom-Json).

    .OUTPUTS
        [PSObject] The same config object, with missing keys injected.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$Config
    )

    # Each entry: @( KeyName, DefaultValue, Comment )
    $defaults = @(
        # ---- Core engine ----
        @("EnableLogging",          $false,      "Master logging switch")
        @("LogEverySeconds",        30,          "Heartbeat log interval in seconds")
        @("EnableTrayIcon",         $true,       "Show system tray icon")
        @("EnableHotkey",           $true,       "Enable keyboard toggle hotkey")
        @("HotkeyMode",            "Custom",    "Hotkey binding: ScrollLock | PauseBreak | F12 | Custom")
        @("CustomHotkeyVirtualKey", 0x76,        "Virtual key code for Custom hotkey (default: F7 = 0x76)")
        @("OperatingMode",         "Graceful",  "Engine mode: Graceful | Classic")
        @("EnableAutoRecovery",    $true,        "Auto-restart mixer if it crashes")
        @("ActiveProfileId",       "BEACN",     "Currently active device profile")
        @("ProfilesEnabled",       @("BEACN"),  "Array of enabled profile IDs")
        @("MonitoredApps",         @(),          "Array of monitored app objects")
        @("Theme",                 "Normal",    "UI theme: Normal | Neon")

        # ---- Game Mode ----
        @("GameModeEnabled",       $false,      "Suppress idle shutdown while a listed game is running")
        @("GameModeList",          @(),          "Array of process names (without .exe) to watch")

        # ---- First-Run Wizard ----
        @("WizardCompleted",       $false,      "Set to true after the first-run wizard finishes")

        # ---- UI Mode ----
        @("UI_Mode",               "Full",      "Panel visibility: Simple | Full")

        # ---- Audio Endpoint ----
        @("PreferredPlaybackDeviceGuid", "",     "GUID of preferred default playback device")
        @("PreferredPlaybackDeviceName", "",     "Display name of preferred default playback device")
        @("PreferredCommDeviceGuid",     "",     "GUID of preferred default communications device")
        @("PreferredCommDeviceName",     "",     "Display name of preferred default communications device")
    )

    $changed = $false
    foreach ($entry in $defaults) {
        $key = $entry[0]
        $val = $entry[1]

        if (-not ($Config.PSObject.Properties.Name -contains $key)) {
            try {
                $Config | Add-Member -MemberType NoteProperty -Name $key -Value $val -Force
                $changed = $true
            }
            catch {
                # Fail-forward: skip this key if injection fails
            }
        }
    }

    return $Config
}

function Test-ConfigSchema {
    <#
    .SYNOPSIS
        Validates a config PSObject against the expected schema.

    .DESCRIPTION
        Checks every known config key for correct type, valid range, and
        allowed enum values. Returns a result object containing:
          - IsValid        : $true if no errors found
          - Errors         : Array of human-readable error strings
          - Warnings       : Array of non-fatal warnings (unknown keys, etc.)
          - FixedKeys      : Array of keys that were auto-repaired

        When -AutoFix is set, invalid values are silently replaced with
        their defaults. The caller can then persist the fixed config.

    .PARAMETER Config
        The PSObject loaded from config.json (via ConvertFrom-Json).

    .PARAMETER AutoFix
        If set, invalid values are replaced with defaults and logged in FixedKeys.

    .OUTPUTS
        [PSCustomObject] with IsValid, Errors, Warnings, FixedKeys properties.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$Config,

        [switch]$AutoFix
    )

    $errors   = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    $fixed    = [System.Collections.Generic.List[string]]::new()

    # Schema definition: Key, ExpectedType, Default, Validator
    # Validator is a scriptblock that receives $value and returns $true if valid
    $schema = @(
        # ---- Core engine ----
        @{ Key = "EnableLogging";           Type = "bool";    Default = $false;      Validator = $null }
        @{ Key = "LogEverySeconds";         Type = "int";     Default = 30;          Validator = { param($v) $v -ge 0 -and $v -le 86400 } }
        @{ Key = "EnableTrayIcon";           Type = "bool";    Default = $true;       Validator = $null }
        @{ Key = "EnableHotkey";             Type = "bool";    Default = $true;       Validator = $null }
        @{ Key = "HotkeyMode";              Type = "string";  Default = "Custom";    Validator = { param($v) $v -in @("ScrollLock","PauseBreak","F12","Custom") } }
        @{ Key = "CustomHotkeyVirtualKey";   Type = "int";     Default = 0x76;        Validator = { param($v) $v -ge 0x01 -and $v -le 0xFE } }
        @{ Key = "OperatingMode";            Type = "string";  Default = "Graceful";  Validator = { param($v) $v -in @("Graceful","Classic") } }
        @{ Key = "EnableAutoRecovery";       Type = "bool";    Default = $true;       Validator = $null }
        @{ Key = "ActiveProfileId";          Type = "string";  Default = "BEACN";     Validator = { param($v) $v.Length -gt 0 -and $v.Length -le 100 } }
        @{ Key = "Theme";                    Type = "string";  Default = "Normal";    Validator = { param($v) $v -in @("Normal","Neon") } }

        # ---- Profiles ----
        @{ Key = "ProfilesEnabled";          Type = "array";   Default = @("BEACN");  Validator = $null }

        # ---- Monitored Apps ----
        @{ Key = "MonitoredApps";            Type = "array";   Default = @();         Validator = $null }

        # ---- Game Mode ----
        @{ Key = "GameModeEnabled";          Type = "bool";    Default = $false;      Validator = $null }
        @{ Key = "GameModeList";             Type = "array";   Default = @();         Validator = $null }

        # ---- First-Run Wizard ----
        @{ Key = "WizardCompleted";          Type = "bool";    Default = $false;      Validator = $null }

        # ---- UI Mode ----
        @{ Key = "UI_Mode";                  Type = "string";  Default = "Full";      Validator = { param($v) $v -in @("Simple","Full") } }

        # ---- Audio Endpoint ----
        @{ Key = "PreferredPlaybackDeviceGuid"; Type = "string"; Default = "";        Validator = $null }
        @{ Key = "PreferredPlaybackDeviceName"; Type = "string"; Default = "";        Validator = $null }
        @{ Key = "PreferredCommDeviceGuid";     Type = "string"; Default = "";        Validator = $null }
        @{ Key = "PreferredCommDeviceName";     Type = "string"; Default = "";        Validator = $null }
    )

    # Known keys for unknown-key detection
    $knownKeys = @($schema | ForEach-Object { $_.Key })
    # Also allow these internal/system keys without flagging them
    $knownKeys += @("LogFile", "SetupPath", "backups")

    foreach ($rule in $schema) {
        $key     = $rule.Key
        $exType  = $rule.Type
        $default = $rule.Default
        $valid   = $rule.Validator

        # Skip if key doesn't exist (Merge-ConfigDefaults handles missing keys)
        if (-not ($Config.PSObject.Properties.Name -contains $key)) {
            continue
        }

        $value = $Config.$key

        # --- Type check ---
        $typeOk = $true
        try {
            switch ($exType) {
                "bool" {
                    if ($value -isnot [bool]) {
                        # Accept 0/1 and "true"/"false" as loose bools
                        if ($value -is [int] -and ($value -eq 0 -or $value -eq 1)) {
                            $value = [bool]$value
                            $Config.$key = $value
                        }
                        elseif ($value -is [string] -and $value -in @("true","false","True","False")) {
                            $value = [bool]::Parse($value)
                            $Config.$key = $value
                        }
                        else {
                            $typeOk = $false
                        }
                    }
                }
                "int" {
                    if ($value -isnot [int] -and $value -isnot [long]) {
                        # Try coercion from string
                        $parsed = 0
                        if ($value -is [string] -and [int]::TryParse($value, [ref]$parsed)) {
                            $value = $parsed
                            $Config.$key = $value
                        }
                        elseif ($value -is [double] -and $value -eq [Math]::Floor($value)) {
                            $value = [int]$value
                            $Config.$key = $value
                        }
                        else {
                            $typeOk = $false
                        }
                    }
                }
                "string" {
                    if ($null -eq $value) {
                        # Null + empty string (acceptable)
                        $value = ""
                        $Config.$key = $value
                    }
                    elseif ($value -isnot [string]) {
                        $typeOk = $false
                    }
                }
                "array" {
                    if ($null -eq $value) {
                        $value = @()
                        $Config.$key = $value
                    }
                    elseif ($value -isnot [array] -and $value -isnot [System.Collections.IEnumerable]) {
                        $typeOk = $false
                    }
                }
            }
        }
        catch {
            $typeOk = $false
        }

        if (-not $typeOk) {
            $msg = "Config key '$key': expected type '$exType' but got '$($value.GetType().Name)' with value '$value'"
            $errors.Add($msg)
            if ($AutoFix) {
                try {
                    $Config.$key = $default
                    $fixed.Add($key)
                } catch {}
            }
            continue
        }

        # --- Range/enum validation ---
        if ($null -ne $valid) {
            try {
                $isValid = & $valid $value
                if (-not $isValid) {
                    $msg = "Config key '$key': value '$value' is out of range or not a valid option"
                    $errors.Add($msg)
                    if ($AutoFix) {
                        try {
                            $Config.$key = $default
                            $fixed.Add($key)
                        } catch {}
                    }
                }
            }
            catch {
                $warnings.Add("Config key '$key': validator threw an exception -- $($_.Exception.Message)")
            }
        }
    }

    # --- Detect unknown keys ---
    foreach ($prop in $Config.PSObject.Properties.Name) {
        if ($prop -notin $knownKeys) {
            $warnings.Add("Unknown config key '$prop' -- may be from a newer version or a typo")
        }
    }

    # --- Migrate legacy UI_Mode values ---
    if ($Config.PSObject.Properties.Name -contains "UI_Mode") {
        $uiVal = $Config.UI_Mode
        if ($uiVal -in @("Basic")) {
            $Config.UI_Mode = "Simple"
            $fixed.Add("UI_Mode (Basic->Simple)")
        }
        elseif ($uiVal -in @("Normal", "Advanced")) {
            $Config.UI_Mode = "Full"
            $fixed.Add("UI_Mode ($uiVal->Full)")
        }
    }

    return [pscustomobject]@{
        IsValid   = ($errors.Count -eq 0)
        Errors    = @($errors)
        Warnings  = @($warnings)
        FixedKeys = @($fixed)
    }
}

function Backup-DeviceWakeState {
    param([string]$DeviceName)

    Ensure-InstallFolder

    $backupList = @()
    if (Test-Path -LiteralPath $script:DeviceWakeBackupPath) {
        try {
            $raw = Get-Content -LiteralPath $script:DeviceWakeBackupPath -Raw
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $backupList = $raw | ConvertFrom-Json
            }
        }
        catch {}
    }

    if ($backupList -notcontains $DeviceName) {
        $backupList += $DeviceName
    }

    $json = $backupList | ConvertTo-Json -Depth 3
    Set-Content -LiteralPath $script:DeviceWakeBackupPath -Value $json -Encoding UTF8
}

function Restore-DeviceWakeFromBackup {
    if (-not (Test-Path -LiteralPath $script:DeviceWakeBackupPath)) {
        return @{ StatusMessage = "No device wake backup found." }
    }

    try {
        $raw = Get-Content -LiteralPath $script:DeviceWakeBackupPath -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            Remove-Item -LiteralPath $script:DeviceWakeBackupPath -Force -ErrorAction SilentlyContinue
            return @{ StatusMessage = "Backup file was empty." }
        }

        $backupList = $raw | ConvertFrom-Json
        $restoredDevices = @()
        $failedDevices = @()
        foreach ($device in $backupList) {
            $null = powercfg /deviceenablewake $device 2>&1
            if ($LASTEXITCODE -ne 0) {
                $failedDevices += $device
            }
            else {
                $restoredDevices += $device
            }
        }

        if ($failedDevices.Count -gt 0) {
            $json = $failedDevices | ConvertTo-Json -Depth 3
            Set-Content -LiteralPath $script:DeviceWakeBackupPath -Value $json -Encoding UTF8
            
            $msg = "Failed to restore: $($failedDevices -join ', ')"
            if ($restoredDevices.Count -gt 0) {
                $msg = "Restored: $($restoredDevices -join ', '). " + $msg
            }
            Write-SetupLog "Device wake settings partially restored. Failed: $($failedDevices -join ', ')."
            return @{ StatusMessage = $msg; Failed = $true }
        }
        else {
            Remove-Item -LiteralPath $script:DeviceWakeBackupPath -Force -ErrorAction SilentlyContinue
            Write-SetupLog "Device wake settings restored from backup."
            return @{ StatusMessage = "Restored wake capabilities for: $($restoredDevices -join ', ')" }
        }
    }
    catch {
        Write-SetupLog "Failed to restore device wake settings: $($_.Exception.Message)"
        return @{ StatusMessage = "Failed to restore: $($_.Exception.Message)"; Failed = $true }
    }
}

function Backup-ScheduledTaskState {
    param(
        [string]$TaskPath,
        [string]$TaskName
    )

    Ensure-InstallFolder

    $backupList = @()
    if (Test-Path -LiteralPath $script:TaskWakeBackupPath) {
        try {
            $raw = Get-Content -LiteralPath $script:TaskWakeBackupPath -Raw
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $backupList = $raw | ConvertFrom-Json
            }
        }
        catch {}
    }

    $alreadyExists = $false
    foreach ($entry in $backupList) {
        if ($entry.TaskPath -eq $TaskPath -and $entry.TaskName -eq $TaskName) {
            $alreadyExists = $true
            break
        }
    }

    if (-not $alreadyExists) {
        $backupList += [pscustomobject]@{
            TaskPath = $TaskPath
            TaskName = $TaskName
        }
    }

    $json = $backupList | ConvertTo-Json -Depth 3
    Set-Content -LiteralPath $script:TaskWakeBackupPath -Value $json -Encoding UTF8
}

function Restore-ScheduledTasksFromBackup {
    if (-not (Test-Path -LiteralPath $script:TaskWakeBackupPath)) {
        return @{ StatusMessage = "No task wake backup found." }
    }

    try {
        $raw = Get-Content -LiteralPath $script:TaskWakeBackupPath -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            Remove-Item -LiteralPath $script:TaskWakeBackupPath -Force -ErrorAction SilentlyContinue
            return @{ StatusMessage = "Backup file was empty." }
        }

        $backupList = $raw | ConvertFrom-Json
        $restoredTasks = @()
        $failedTasks = @()
        foreach ($task in $backupList) {
            try {
                Enable-ScheduledTask -TaskPath $task.TaskPath -TaskName $task.TaskName -ErrorAction Stop | Out-Null
                $restoredTasks += "$($task.TaskPath)$($task.TaskName)"
            }
            catch {
                $failedTasks += $task
            }
        }

        if ($failedTasks.Count -gt 0) {
            $json = $failedTasks | ConvertTo-Json -Depth 3
            Set-Content -LiteralPath $script:TaskWakeBackupPath -Value $json -Encoding UTF8
            
            $failedNames = @(foreach ($t in $failedTasks) { "$($t.TaskPath)$($t.TaskName)" })
            $msg = "Failed to enable: $($failedNames -join ', ')"
            if ($restoredTasks.Count -gt 0) {
                $msg = "Enabled: $($restoredTasks -join ', '). " + $msg
            }
            Write-SetupLog "Task wake settings partially restored. Failed: $($failedNames -join ', ')."
            return @{ StatusMessage = $msg; Failed = $true }
        }
        else {
            Remove-Item -LiteralPath $script:TaskWakeBackupPath -Force -ErrorAction SilentlyContinue
            Write-SetupLog "Task wake settings restored from backup."
            return @{ StatusMessage = "Enabled scheduled tasks: $($restoredTasks -join ', ')" }
        }
    }
    catch {
        Write-SetupLog "Failed to restore task wake settings: $($_.Exception.Message)"
        return @{ StatusMessage = "Failed to restore: $($_.Exception.Message)"; Failed = $true }
    }
}

function Backup-ServiceState {
    param(
        [string]$ServiceName,
        [string]$StartupType,
        [string]$State
    )

    Ensure-InstallFolder

    $backupList = @()
    if (Test-Path -LiteralPath $script:ServiceWakeBackupPath) {
        try {
            $raw = Get-Content -LiteralPath $script:ServiceWakeBackupPath -Raw
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $backupList = $raw | ConvertFrom-Json
            }
        }
        catch {}
    }

    $alreadyExists = $false
    foreach ($entry in $backupList) {
        if ($entry.ServiceName -eq $ServiceName) {
            $alreadyExists = $true
            break
        }
    }

    if (-not $alreadyExists) {
        $backupList += [pscustomobject]@{
            ServiceName = $ServiceName
            StartupType = $StartupType
            State       = $State
        }
    }

    $json = $backupList | ConvertTo-Json -Depth 3
    Set-Content -LiteralPath $script:ServiceWakeBackupPath -Value $json -Encoding UTF8
}

function Restore-ServicesFromBackup {
    if (-not (Test-Path -LiteralPath $script:ServiceWakeBackupPath)) {
        return @{ StatusMessage = "No service wake backup found." }
    }

    try {
        $raw = Get-Content -LiteralPath $script:ServiceWakeBackupPath -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            Remove-Item -LiteralPath $script:ServiceWakeBackupPath -Force -ErrorAction SilentlyContinue
            return @{ StatusMessage = "Backup file was empty." }
        }

        $backupList = $raw | ConvertFrom-Json
        $restoredServices = @()
        $failedServices = @()
        foreach ($svc in $backupList) {
            try {
                Set-Service -Name $svc.ServiceName -StartupType $svc.StartupType -ErrorAction Stop
                if ($svc.State -eq "Running") {
                    Start-Service -Name $svc.ServiceName -ErrorAction Stop
                }
                $restoredServices += $svc.ServiceName
            }
            catch {
                $failedServices += $svc
            }
        }

        if ($failedServices.Count -gt 0) {
            $json = $failedServices | ConvertTo-Json -Depth 3
            Set-Content -LiteralPath $script:ServiceWakeBackupPath -Value $json -Encoding UTF8
            
            $failedNames = @(foreach ($s in $failedServices) { $s.ServiceName })
            $msg = "Failed to restore service(s): $($failedNames -join ', ')"
            if ($restoredServices.Count -gt 0) {
                $msg = "Restored: $($restoredServices -join ', '). " + $msg
            }
            Write-SetupLog "Service wake settings partially restored. Failed: $($failedNames -join ', ')."
            return @{ StatusMessage = $msg; Failed = $true }
        }
        else {
            Remove-Item -LiteralPath $script:ServiceWakeBackupPath -Force -ErrorAction SilentlyContinue
            Write-SetupLog "Service wake settings restored from backup."
            return @{ StatusMessage = "Restored Windows Services: $($restoredServices -join ', ')" }
        }
    }
    catch {
        Write-SetupLog "Failed to restore service wake settings: $($_.Exception.Message)"
        return @{ StatusMessage = "Failed to restore services: $($_.Exception.Message)"; Failed = $true }
    }
}

function Get-UsbSelectiveSuspend {
    $scheme = Get-ActiveSchemeGuid
    if ($scheme) {
        $out = powercfg /query $scheme 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 2>$null
        $m = ($out | Select-String -Pattern 'Current AC Power Setting Index:\s+0x([0-9a-fA-F]+)' | Select-Object -First 1)
        if ($m -and $m.Matches.Count -gt 0) {
            try { return [Convert]::ToInt32($m.Matches[0].Groups[1].Value, 16) } catch {}
        }
    }
    return $null
}

function Backup-UsbSuspendState {
    Ensure-InstallFolder
    
    $displayOff = 0
    $sleepIdle = 0
    $hibIdle = 0
    $schemeGuid = Get-ActiveSchemeGuid
    if ($schemeGuid) {
        $displayOff = Get-PowerSettingSecondsAC -SchemeGuid $schemeGuid -SubGuid $SUB_VIDEO -SettingGuid $VIDEOIDLE
        $sleepIdle = Get-PowerSettingSecondsAC -SchemeGuid $schemeGuid -SubGuid $SUB_SLEEP -SettingGuid $STANDBYIDLE
        # Note: Using $hibIdle here instead of $hibernateIdle to prevent a case-insensitive conflict with the global $HIBERNATEIDLE GUID.
        $hibIdle = Get-PowerSettingSecondsAC -SchemeGuid $schemeGuid -SubGuid $SUB_SLEEP -SettingGuid $HIBERNATEIDLE
    }
    
    $backup = $null
    if (Test-Path -LiteralPath $script:PowerPlanBackupPath) {
        try {
            $raw = Get-Content -LiteralPath $script:PowerPlanBackupPath -Raw
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $backup = $raw | ConvertFrom-Json
            }
        } catch {}
    }
    if ($null -eq $backup) {
        $backup = [pscustomobject][ordered]@{
            SchemeGuid = $schemeGuid
            DisplayOffSeconds = $displayOff
            SleepIdleSeconds = $sleepIdle
            HibernateIdleSeconds = $hibIdle
            Timestamp = (Get-Date).ToString("s")
        }
    }
    
    $currentVal = Get-UsbSelectiveSuspend
    if ($null -ne $currentVal) {
        if ($null -eq $backup.UsbSelectiveSuspendSettingIndex) {
            $backup | Add-Member -MemberType NoteProperty -Name "UsbSelectiveSuspendSettingIndex" -Value $currentVal -Force
        }
    }
    
    $json = $backup | ConvertTo-Json -Depth 3
    Set-Content -LiteralPath $script:PowerPlanBackupPath -Value $json -Encoding UTF8
}

function Restore-UsbSuspendFromBackup {
    if (-not (Test-Path -LiteralPath $script:PowerPlanBackupPath)) {
        return @{ StatusMessage = "No USB suspend backup found." }
    }

    try {
        $raw = Get-Content -LiteralPath $script:PowerPlanBackupPath -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return @{ StatusMessage = "USB suspend backup file was empty." }
        }

        $backup = $raw | ConvertFrom-Json
        if ($null -eq $backup -or -not $backup.PSObject.Properties.Match('UsbSelectiveSuspendSettingIndex')) {
            return @{ StatusMessage = "No USB selective suspend entry found in backup." }
        }

        $savedVal = [int]$backup.UsbSelectiveSuspendSettingIndex
        $label = if ($savedVal -eq 1) { "Enabled" } else { "Disabled" }

        powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 $savedVal 2>$null | Out-Null
        powercfg /setactive SCHEME_CURRENT 2>$null | Out-Null

        # Remove UsbSelectiveSuspendSettingIndex from the backup JSON
        $backup.PSObject.Properties.Remove('UsbSelectiveSuspendSettingIndex')

        # If no meaningful keys remain (only metadata like Timestamp), delete the file; otherwise update it
        $remainingKeys = $backup.PSObject.Properties.Name | Where-Object { $_ -notin @('Timestamp') }
        if ($remainingKeys.Count -eq 0) {
            Remove-Item -LiteralPath $script:PowerPlanBackupPath -Force -ErrorAction SilentlyContinue
        } else {
            $json = $backup | ConvertTo-Json -Depth 3
            Set-Content -LiteralPath $script:PowerPlanBackupPath -Value $json -Encoding UTF8
        }

        Write-SetupLog "USB Selective Suspend restored to $label from backup."
        return @{ StatusMessage = "USB Selective Suspend restored to: $label" }
    }
    catch {
        Write-SetupLog "Failed to restore USB Selective Suspend: $($_.Exception.Message)"
        return @{ StatusMessage = "Failed to restore USB Selective Suspend: $($_.Exception.Message)"; Failed = $true }
    }
}
