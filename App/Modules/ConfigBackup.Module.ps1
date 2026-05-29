# =============================================================================
# SAMISH Telemetry Actions & Backups Helpers
# =============================================================================

# Developer Note: Registry modification commands for USB Selective Suspend keys 
# require Administrator privileges and targeting HKLM paths. Backup values 
# are stored in config.json under 'backups' key. Overrides must complete 
# execution in under 300 ms.

$script:DeviceWakeBackupPath = Join-Path $env:APPDATA "SAMISH\device_wake_backup.json"
$script:TaskWakeBackupPath = Join-Path $env:APPDATA "SAMISH\task_wake_backup.json"

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
