# ---------- Events.Setup.ps1 ----------
# --- Mode toggles ---
$rbHidden.add_CheckedChanged({
        if ($script:IsApplyingConfig) { return }

        if ($rbHidden.Checked) {
            $cbTray.Checked = $false
            $cbTray.Enabled = $false
        }
        else {
            $cbTray.Enabled = $true
        }
    })

# --- Logging UI ---
$ddLogInterval.add_SelectedIndexChanged({
        if ($script:IsApplyingConfig) { return }

        if ($ddLogInterval.SelectedItem.ToString() -eq "Custom seconds...") {
            $tbLogCustom.Enabled = $true
            $tbLogCustom.Focus()
            return
        }

        $tbLogCustom.Enabled = $false
        switch ($ddLogInterval.SelectedItem.ToString()) {
            "Verbose (every loop)" { $tbLogCustom.Text = "0" }
            "Every 30 seconds" { $tbLogCustom.Text = "30" }
            "Every 60 seconds" { $tbLogCustom.Text = "60" }
        }
    })

# --- Hotkey UI ---
$ddHotkey.add_SelectedIndexChanged({
        if ($script:IsApplyingConfig) { return }

        if ($ddHotkey.SelectedItem.ToString() -eq "Custom") {
            $tbCustomKey.Enabled = $true
            $tbCustomKey.Focus()
        }
        else {
            $tbCustomKey.Enabled = $false
        }
    })

# --- Logging Checkbox UI ---
$cbLogging.add_CheckedChanged({
        if ($script:IsApplyingConfig) { return }

        $enabled = $cbLogging.Checked
        $ddLogInterval.Enabled = $enabled
        if ($enabled) {
            $tbLogCustom.Enabled = ($ddLogInterval.SelectedItem.ToString() -eq "Custom seconds...")
        } else {
            $tbLogCustom.Enabled = $false
        }
    })

# --- Hotkey Checkbox UI ---
$cbHotkey.add_CheckedChanged({
        if ($script:IsApplyingConfig) { return }

        $enabled = $cbHotkey.Checked
        $ddHotkey.Enabled = $enabled
        if ($enabled) {
            $tbCustomKey.Enabled = ($ddHotkey.SelectedItem.ToString() -eq "Custom")
        } else {
            $tbCustomKey.Enabled = $false
        }
    })

# --- Simple buttons ---
$btnOpenTS.add_Click({ Start-Process "taskschd.msc" | Out-Null })

# --- Power plan tool ---
$btnPowerPlan.add_Click({
        try {
            # Check for telemetry backups and offer restoration
            $hasPowerPlanUsbBackup = $false
            if (Test-Path -LiteralPath $script:PowerPlanBackupPath) {
                try {
                    $ppRaw = Get-Content -LiteralPath $script:PowerPlanBackupPath -Raw
                    $ppObj = $ppRaw | ConvertFrom-Json -ErrorAction SilentlyContinue
                    $hasPowerPlanUsbBackup = ($null -ne $ppObj) -and ($ppObj.PSObject.Properties.Match('UsbSelectiveSuspendSettingIndex').Count -gt 0)
                } catch {}
            }

            $hasServiceWakeBackup = Test-Path -LiteralPath $script:ServiceWakeBackupPath
            if ((Test-Path -LiteralPath $script:DeviceWakeBackupPath) -or (Test-Path -LiteralPath $script:TaskWakeBackupPath) -or $hasServiceWakeBackup -or $hasPowerPlanUsbBackup) {
                $restorePrompt = "SAMISH found backups of system telemetry modifications (disabled wake devices, wake timers, background services, or USB selective suspend settings).`r`n`r`nWould you like to restore these system settings back to their original defaults now?`r`n`r`nIf you choose No, SAMISH will continue to verify your power plan compatibility settings."
                $restoreChoice = Show-YesNoDialog `
                    -Title "Restore Telemetry Settings?" `
                    -Message $restorePrompt `
                    -Icon ([System.Windows.Forms.MessageBoxIcon]::Question)
            
                if ($restoreChoice -eq [System.Windows.Forms.DialogResult]::Yes) {
                    $messages = @()
                    $hasFailures = $false
                    try {
                        if (Test-Path -LiteralPath $script:DeviceWakeBackupPath) {
                            $res = Restore-DeviceWakeFromBackup
                            $messages += $res.StatusMessage
                            if ($res.Failed) { $hasFailures = $true }
                        }
                        if (Test-Path -LiteralPath $script:TaskWakeBackupPath) {
                            $res = Restore-ScheduledTasksFromBackup
                            $messages += $res.StatusMessage
                            if ($res.Failed) { $hasFailures = $true }
                        }
                        if ($hasServiceWakeBackup) {
                            $res = Restore-ServicesFromBackup
                            $messages += $res.StatusMessage
                            if ($res.Failed) { $hasFailures = $true }
                        }
                        if ($hasPowerPlanUsbBackup) {
                            $res = Restore-UsbSuspendFromBackup
                            $messages += $res.StatusMessage
                            if ($res.Failed) { $hasFailures = $true }
                        }
                        
                        if ($hasFailures) {
                            Set-StatusText("Telemetry settings restore completed with warnings.")
                            [void][System.Windows.Forms.MessageBox]::Show(
                                "Some telemetry settings could not be restored.`r`n`r`n" + ($messages -join "`r`n"),
                                "SAMISH Telemetry Restore Warning",
                                [System.Windows.Forms.MessageBoxButtons]::OK,
                                [System.Windows.Forms.MessageBoxIcon]::Warning
                            )
                        } else {
                            Set-StatusText("Telemetry settings restored successfully.")
                            [void][System.Windows.Forms.MessageBox]::Show(
                                "Telemetry settings restored successfully.`r`n`r`n" + ($messages -join "`r`n"),
                                "SAMISH Telemetry Restore",
                                [System.Windows.Forms.MessageBoxButtons]::OK,
                                [System.Windows.Forms.MessageBoxIcon]::Information
                            )
                        }

                        # Refresh telemetry lists to reflect restored state
                        if ($script:btnTelemetryRefresh) { $script:btnTelemetryRefresh.PerformClick() }
                        return
                    }
                    catch {
                        Set-StatusText("Failed to restore telemetry settings.")
                        Write-SetupLog "Telemetry restore failed: $($_.Exception.Message)"  
                    }
                }
            }

            Set-StatusText("Checking power plan settings...")

            # Determine operating mode from config (do not infer)
            $opMode = "Graceful"
            try {
                if (Test-Path -LiteralPath $ConfigPath) {
                    $cfg = (Get-Content -LiteralPath $ConfigPath -Raw) | ConvertFrom-Json
                    if ($cfg -and ($cfg.PSObject.Properties.Name -contains "OperatingMode") -and $cfg.OperatingMode) {
                        $opMode = [string]$cfg.OperatingMode
                    }
                }
            }
            catch {}

            $result = PowerPlan_CheckOrRestore

            if ($result -and $result.NeedsPrompt) {

                if ($opMode -eq "Graceful") {

                    $result = Invoke-GracefulClassicCompatOptInFlow `
                        -InitialResult $result `
                        -AutoMode:$false

                }
                else {

                    $result = Handle-PowerPlanPromptIfNeeded -result $result -AutoMode:$false
                    if ($result -and $result.NeedsPrompt) {
                        $result = Handle-PowerPlanPromptIfNeeded -result $result -AutoMode:$false
                    }

                }
            }

            if ($result -and $result.StatusMessage) {
                Set-StatusText($result.StatusMessage)
            }
            else {
                Set-StatusText(Get-NoPowerPlanChangesText)
            }


        }
        catch {
            Set-StatusText("Power Plan action failed.`r`nSee details below:`r`n$($_.Exception.Message)")
            Write-SetupLog ("Power Plan action failed: " + $_.Exception.Message)
        }
    })  

# --- Read Setup ---
$btnReadSetup.add_Click({
        Apply-UIFromConfigIfPresent
        Show-CurrentConfiguration
    })

# --- Logs ---
$btnOpenLog.add_Click({
        $path = Get-VerifiedPreferredLogPathOrShowMessageBox
        if (-not $path) { return }

        try {
            Start-Process -FilePath "notepad.exe" -ArgumentList $path | Out-Null
        }
        catch {
            Show-ErrorDialog `
                -Title "Error" `
                -Message ("Failed to open log:`r`n" + $_.Exception.Message)
        }
    })


# --- Clean Reset (restarts installed mode) ---
$btnCleanReset.add_Click({
        $installed = Test-SamishInstalled
        if (-not $installed) {
            [System.Windows.Forms.MessageBox]::Show(
                "SAMISH is not installed. No reset is necessary.",
                "Clean Reset - Not Installed",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            return
        }
        $result = [System.Windows.Forms.MessageBox]::Show(
            "This will stop SAMISH and restart it in the currently installed mode (Hidden or Interactive). Continue?",
            "Confirm Clean Reset",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($result -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        try {
            Set-StatusText("Resetting SAMISH...")

            $installed = Test-SamishInstalled

            # Always stop any running engine instances first
            $stoppedCount = Stop-RunningHelperInstances
            Start-Sleep -Milliseconds 250

            if (-not $installed) {
                # Not installed => do NOT restart anything
                Remove-StartupShortcut

                Set-StatusText(
                    "SAMISH is not installed.`r`n" +
                    "Stopped $stoppedCount running instance(s).`r`n" +
                    "Nothing was restarted."
                )

                Show-DiagnosticsHeader `
                    -Context "After Clean Reset (Stop Only - Not Installed)" `
                    -Mode "Interactive" `
                    -TrayRequested:$($cbTray.Checked) `
                    -HotkeyRequested:$($cbHotkey.Checked) `
                    -LoggingRequested:$($cbLogging.Checked)

                return
            }

        
            # Installed => restart via installed mode (task-only)
            $modeToRestart = Get-ActiveInstallModeForReset

            # 1) End the running task instance first (important due to IgnoreNew)
            Stop-SamishTaskIfRunning -Mode $modeToRestart
            Start-Sleep -Milliseconds 200

            # 2) Stop any remaining engine processes (manual launch or leftover)
            $stoppedCount = Stop-RunningHelperInstances
            Start-Sleep -Milliseconds 200

            # 3) Start again via Scheduled Task (consistent with logon behavior)
            $null = Start-SamishInMode -Mode $modeToRestart

            Set-StatusText("Clean reset complete.`r`n$stoppedCount instance(s) stopped and restarted via Scheduled Task.")

            Show-DiagnosticsHeader `
                -Context "After Clean Reset" `
                -Mode $modeToRestart `
                -TrayRequested:$($cbTray.Checked) `
                -HotkeyRequested:$($cbHotkey.Checked) `
                -LoggingRequested:$($cbLogging.Checked)
        }
        catch {
            Set-StatusText("Clean reset failed.`r`nSee details below:`r`n$($_.Exception.Message)")
            Write-SetupLog ("Clean reset failed: " + $_.Exception.Message)
        }

    })

# ---------- INSTALL / UPDATE ----------
$btnInstall.add_Click({
        try {
            Set-StatusText("Preparing runtime files...")
            Sync-SamishRuntimeFiles

            $mode = if ($rbHidden.Checked) { "Hidden" } else { "Interactive" }

            $sel = $ddLogInterval.SelectedItem.ToString()
            $logEvery = 30

            if ($sel -eq "Verbose (every loop)") {
                $logEvery = 0
            }
            elseif ($sel -eq "Every 30 seconds") {
                $logEvery = 30
            }
            elseif ($sel -eq "Every 60 seconds") {
                $logEvery = 60
            }
            else {
                try {
                    $logEvery = Parse-LogEverySecondsOrThrow -RawText $tbLogCustom.Text -ContextLabel "Log interval"
                }
                catch {
                    Show-WarningDialog `
                        -Title "Invalid Log Interval" `
                        -Message $_.Exception.Message
                    return
                }
            }

            $hkMode = $ddHotkey.SelectedItem.ToString()
            $vk = 0x91
            if ($hkMode -eq "Custom") { $vk = Parse-CustomHotkeyToVk $tbCustomKey.Text }
            else { $vk = [int]$VkMap[$hkMode] }

            $enableTray = $cbTray.Checked
            if ($mode -eq "Hidden") { $enableTray = $false }

            $operatingMode = if ($rbOpClassic.Checked) { "Classic" } else { "Graceful" }

            Write-ConfigJson `
                -EnableLogging:$($cbLogging.Checked) `
                -LogEverySeconds:$logEvery `
                -EnableTrayIcon:$enableTray `
                -EnableHotkey:$($cbHotkey.Checked) `
                -HotkeyMode:$hkMode `
                -CustomHotkeyVirtualKey:$vk `
                -OperatingMode:$operatingMode `
                -SetupPath:$script:SetupExecutablePath `
                -ActiveProfileId $script:ActiveProfileId `
                -ProfilesEnabled $script:ProfilesEnabled `
                -EnableAutoRecovery:$($cbAutoRecovery.Checked)

            Set-StatusText("Installing...")
            Register-SamishEventSource

            Delete-Task -TaskNameWithSlash $TaskHidden | Out-Null
            Delete-Task -TaskNameWithSlash $TaskInteractive | Out-Null

            $HiddenXmlInstalled = Join-Path $InstallDir "SAMISH-HiddenTask.xml"
            $InteractiveXmlInstalled = Join-Path $InstallDir "SAMISH-InteractiveTask.xml"

            if ($mode -eq "Hidden") {
                Install-TaskFromXml -TaskNameNoSlash $TaskHiddenNoSlash -XmlPath $HiddenXmlInstalled | Out-Null
                Remove-StartupShortcut
            }
            else {
                Install-TaskFromXml -TaskNameNoSlash $TaskInteractiveNoSlash -XmlPath $InteractiveXmlInstalled | Out-Null

                # Interactive mode should be Task Scheduler-only (prevents double-start + duplicate tray icons)
                Remove-StartupShortcut

                # Start immediately after install in a consistent way:
                # - stop any existing instances
                # - start via the scheduled task (same path used at logon)
                Stop-RunningHelperInstances | Out-Null
                Start-Sleep -Milliseconds 300

                # Prefer your helper which runs the installed task when present
                $null = Start-SamishInMode -Mode "Interactive"
            }

            $result = $null

            if ($operatingMode -eq "Classic") {

                $result = Apply-PowerPlanFixWithBackup -PromptUser:$true -AutoMode:$true
                $result = Handle-PowerPlanPromptIfNeeded -result $result -AutoMode:$true

            }
            else {

                try {
                    $scheme = Get-ActiveSchemeGuid
                    if ($scheme) {

                        $displayOff = Get-PowerSettingSecondsAC -SchemeGuid $scheme -SubGuid $SUB_VIDEO -SettingGuid $VIDEOIDLE
                        $sleepIdle = Get-PowerSettingSecondsAC -SchemeGuid $scheme -SubGuid $SUB_SLEEP -SettingGuid $STANDBYIDLE
                        $hibIdle = Get-PowerSettingSecondsAC -SchemeGuid $scheme -SubGuid $SUB_SLEEP -SettingGuid $HIBERNATEIDLE

                        $t = Test-PowerPlanCompatibility `
                            -DisplayOffSeconds $displayOff `
                            -SleepIdleSeconds $sleepIdle `
                            -HibernateIdleSeconds $hibIdle `
                            -GapSeconds $MinGapSeconds

                        if ($t -and (-not $t.Compatible)) {

                            if (Ask-PowerPlanClassicCompatOptIn) {
                                $result = Apply-PowerPlanFixWithBackup -PromptUser:$true -AutoMode:$true
                                $result = Handle-PowerPlanPromptIfNeeded -result $result -AutoMode:$true
                            }
                            else {
                                $result = Get-NoPowerPlanChangesStatus
                            }
                        }
                    }
                }
                catch {
                    # Best effort only
                }
            }

            $msg = "Install complete.`r`nScheduled task created successfully."
            if ($result -and $result.StatusMessage) { $msg += "`r`n`r`n" + $result.StatusMessage }

            if ($operatingMode -eq "Graceful" -and $result -and $result.StatusMessage) {
                $generic = [string]$result.StatusMessage
                if ($generic -match '(?i)may prevent SAMISH' -or $generic -match '(?i)functioning as intended') {

                    $gracefulNote =
                    "Your current power plan is not compatible with SAMISH Classic.

This does not affect Graceful mode.

If you switch to Classic mode, run ""Power Plan: Check / Restore"" to ensure proper behavior."

                    $msg = $msg -replace [Regex]::Escape($generic), $gracefulNote
                }
            }

            Set-StatusText($msg)

            Show-DiagnosticsHeader `
                -Context "After Install / Update" `
                -Mode $mode `
                -TrayRequested:$enableTray `
                -HotkeyRequested:$($cbHotkey.Checked) `
                -LoggingRequested:$($cbLogging.Checked)

            if ($script:btnCleanReset) {
                $script:btnCleanReset.Enabled = $true
                if ($tooltip) { $tooltip.SetToolTip($script:btnCleanReset, "Restart background service and check for errors (safely preserves configuration).") }
            }
        }
        catch {
            Set-StatusText("Install failed.`r`nSee details below:`r`n$($_.Exception.Message)")
            Write-SetupLog ("Install failed: " + $_.Exception.Message)
        }

        # Sync Neon tab indicator in case theme is active
        if ($global:ThemeCustomActive) {
            if (Get-Command Update-TabIndicator -ErrorAction SilentlyContinue) { try { Update-TabIndicator } catch {} }
        }
    })

# ---------- UNINSTALL ----------
$btnUninstall.add_Click({
        try {
            $hiddenExists = Task-Exists -TaskNameWithSlash $TaskHidden
            $interactiveExists = Task-Exists -TaskNameWithSlash $TaskInteractive
            $shortcutExists = Test-Path -LiteralPath (Get-StartupShortcutPath)

            # NEW: treat a running engine as something to uninstall/stop even if tasks are gone
            $proc = Get-SamishProcessInfo
            $runningExists = $proc -and $proc.Running

            if (-not ($hiddenExists -or $interactiveExists -or $shortcutExists -or $runningExists)) {
                Set-StatusText("Nothing to uninstall.`r`nSAMISH is not currently installed or running.")
                Write-SetupLog "Uninstall requested: nothing to uninstall."
                return
            }

            Set-StatusText("Uninstalling SAMISH...")

            # Offer to restore the backed-up power plan settings if present
            if (Test-Path -LiteralPath $PowerPlanBackupPath) {
                $restorePrompt = "A backup of your power plan settings was found (saved when SAMISH was installed).`r`n`r`nWould you like to restore your original power plan settings?"
                $restoreChoice = Show-YesNoDialog `
                    -Title "Restore Power Plan?" `
                    -Message $restorePrompt `
                    -Icon ([System.Windows.Forms.MessageBoxIcon]::Question)
            
                if ($restoreChoice -eq [System.Windows.Forms.DialogResult]::Yes) {
                    try {
                        $restoreRes = Restore-PowerPlanFromBackup
                        Write-SetupLog "Uninstall: Power plan restored: $($restoreRes.StatusMessage)"
                    }
                    catch {
                        Write-SetupLog "Uninstall: Power plan restore failed: $($_.Exception.Message)"
                    }
                }
            }

            # Offer to restore telemetry backups if present
            $hasPowerPlanUsbBackup = $false
            if (Test-Path -LiteralPath $script:PowerPlanBackupPath) {
                try {
                    $ppRaw = Get-Content -LiteralPath $script:PowerPlanBackupPath -Raw
                    $ppObj = $ppRaw | ConvertFrom-Json -ErrorAction SilentlyContinue
                    $hasPowerPlanUsbBackup = ($null -ne $ppObj) -and ($ppObj.PSObject.Properties.Match('UsbSelectiveSuspendSettingIndex').Count -gt 0)
                } catch {}
            }

            $hasServiceWakeBackup = Test-Path -LiteralPath $script:ServiceWakeBackupPath
            if ((Test-Path -LiteralPath $script:DeviceWakeBackupPath) -or (Test-Path -LiteralPath $script:TaskWakeBackupPath) -or $hasServiceWakeBackup -or $hasPowerPlanUsbBackup) {
                $restorePrompt = "SAMISH found backups of system telemetry modifications (disabled wake devices, wake timers, background services, or USB selective suspend settings).`r`n`r`nWould you like to restore all settings back to their original defaults now?"
                $restoreChoice = Show-YesNoDialog `
                    -Title "Restore Telemetry Settings?" `
                    -Message $restorePrompt `
                    -Icon ([System.Windows.Forms.MessageBoxIcon]::Question)
            
                if ($restoreChoice -eq [System.Windows.Forms.DialogResult]::Yes) {
                    try {
                        if (Test-Path -LiteralPath $script:DeviceWakeBackupPath) {
                            $res = Restore-DeviceWakeFromBackup
                            Write-SetupLog "Uninstall: Telemetry devices restored: $($res.StatusMessage)"
                        }
                        if (Test-Path -LiteralPath $script:TaskWakeBackupPath) {
                            $res = Restore-ScheduledTasksFromBackup
                            Write-SetupLog "Uninstall: Telemetry tasks restored: $($res.StatusMessage)"
                        }
                        if ($hasServiceWakeBackup) {
                            $res = Restore-ServicesFromBackup
                            Write-SetupLog "Uninstall: Telemetry services restored: $($res.StatusMessage)"
                        }
                        if ($hasPowerPlanUsbBackup) {
                            $res = Restore-UsbSuspendFromBackup
                            Write-SetupLog "Uninstall: USB suspend restored: $($res.StatusMessage)"
                        }
                    }
                    catch {
                        Write-SetupLog "Uninstall: Telemetry restore failed: $($_.Exception.Message)"
                    }
                }
            }

            # Stop running task instances first (best effort)
            try {
                if ($interactiveExists) { Stop-SamishTaskIfRunning -Mode "Interactive" }
                if ($hiddenExists) { Stop-SamishTaskIfRunning -Mode "Hidden" }
            }
            catch {}

            # Stop any running engine processes (tray instance lives here)
            $stoppedCount = Stop-RunningHelperInstances
            Start-Sleep -Milliseconds 250

            # Remove tasks (if present)
            Delete-Task -TaskNameWithSlash $TaskHidden | Out-Null
            Delete-Task -TaskNameWithSlash $TaskInteractive | Out-Null

            # Remove any legacy Startup shortcut
            Remove-StartupShortcut

            # Remove Event Log Source
            try {
                if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\SAMISH") {
                    [System.Diagnostics.EventLog]::DeleteEventSource("SAMISH")
                    Write-SetupLog "Unregistered SAMISH Windows Event Log source."
                }
            }
            catch {
                Write-SetupLog "WARNING: Failed to unregister SAMISH Event Log source: $($_.Exception.Message)"
            }

            Set-StatusText("Uninstall complete.`r`nStopped $stoppedCount running instance(s).")
            Write-SetupLog "Uninstall complete."

            if ($script:btnCleanReset) {
                $script:btnCleanReset.Enabled = $false
                if ($tooltip) { $tooltip.SetToolTip($script:btnCleanReset, "SAMISH is not installed - clean reset unavailable.") }
            }

            $removeAllPrompt =
            "Do you also want to remove all SAMISH configuration files, logs, and profile settings from %APPDATA%\SAMISH?

Yes = Full cleanup (deletes all user configurations, custom hotkeys, logs, and profiles).
No  = Standard uninstall (keeps configuration files for future installations)."

            $removeAll = Show-YesNoDialog `
                -Title "Remove SAMISH files?" `
                -Message $removeAllPrompt `
                -Icon ([System.Windows.Forms.MessageBoxIcon]::Question)

            if ($removeAll -eq [System.Windows.Forms.DialogResult]::Yes) {
                try {
                    if (Test-Path -LiteralPath $InstallDir) {
                        Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    Write-SetupLog "Full cleanup selected: removed %APPDATA%\SAMISH."
                }
                catch {
                    Write-SetupLog ("Full cleanup encountered an error: " + $_.Exception.Message)
                }
            }

            Show-DiagnosticsHeader -Context "After Uninstall" -Mode ""

        }
        catch {
            Set-StatusText("Uninstall failed.`r`nSee details below:`r`n$($_.Exception.Message)")
            Write-SetupLog ("Uninstall failed: " + $_.Exception.Message)
        }

        # Sync Neon tab indicator in case theme is active
        if ($global:ThemeCustomActive) {
            if (Get-Command Update-TabIndicator -ErrorAction SilentlyContinue) { try { Update-TabIndicator } catch {} }
        }
    })



function Set-StatusText([string]$text) {
    if (-not $statusBox) { return }
    $timestamp = (Get-Date -Format "HH:mm:ss")
    $statusBox.AppendText("[$timestamp] $text
")
    $statusBox.SelectionStart = $statusBox.TextLength
    $statusBox.ScrollToCaret()
}

# Wire IndexChanged for ddTestTarget to refresh tooltips dynamically
if ($script:ddTestTarget) {
    $script:ddTestTarget.add_SelectedIndexChanged({
        Update-TestButtonsTooltips
    })
}

# Wire Drawer 2 tab buttons (System Telemetry vs Hardware Telemetry)
if ($script:btnDrawer2TabSystem) {
    $script:btnDrawer2TabSystem.add_Click({
        if ($script:pnlTelemetrySystem)   { $script:pnlTelemetrySystem.Visible = $true }
        if ($script:pnlTelemetryHardware) { $script:pnlTelemetryHardware.Visible = $false }
        if ($script:drawer2TabIndicator)  { $script:drawer2TabIndicator.Location = New-Object System.Drawing.Point([int](5 * $script:DpiScale), [int](154 * $script:DpiScale)) }
        # Re-evaluate action button based on currently selected item across all lists
        Sync-TelemetryActionButton
        Update-SecondaryTabStyles
    })
}
if ($script:btnDrawer2TabHardware) {
    $script:btnDrawer2TabHardware.add_Click({
        if ($script:pnlTelemetrySystem)   { $script:pnlTelemetrySystem.Visible = $false }
        if ($script:pnlTelemetryHardware) { $script:pnlTelemetryHardware.Visible = $true }
        if ($script:drawer2TabIndicator)  { $script:drawer2TabIndicator.Location = New-Object System.Drawing.Point([int](190 * $script:DpiScale), [int](154 * $script:DpiScale)) }
        # Re-evaluate action button based on currently selected item across all lists
        Sync-TelemetryActionButton
        Update-SecondaryTabStyles
    })
}

# --- Preferred Audio Device Dialog ---
function Update-ConfigKey {
    param(
        [string]$Key,
        $Value
    )
    # Always set the script-scoped variable so the UI process is in sync
    Set-Variable -Name $Key -Value $Value -Scope Script -Force

    if (Test-Path -LiteralPath $ConfigPath) {
        try {
            $raw = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction SilentlyContinue
            $cfg = $null
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $cfg = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
            }
            if (-not $cfg) {
                $cfg = @{}
            }
            if ($cfg.PSObject.Properties.Name -contains $Key) {
                $cfg.$Key = $Value
            } else {
                $cfg | Add-Member -MemberType NoteProperty -Name $Key -Value $Value -Force
            }
            $json = $cfg | ConvertTo-Json -Depth 6
            if (Get-Command Save-ContentAtomic -ErrorAction SilentlyContinue) {
                Save-ContentAtomic -Path $ConfigPath -Content $json
            } else {
                Set-Content -LiteralPath $ConfigPath -Value $json -Encoding UTF8
            }
        }
        catch {
            try { Log-Always "Update-ConfigKey error for $($Key): $_" } catch {}
        }
    }
}

function Show-PreferredAudioDialog {
    # Dynamically read current config values at open
    $currentPlaybackGuid = ""
    $currentPlaybackName = ""
    $currentCommGuid = ""
    $currentCommName = ""

    if (Test-Path -LiteralPath $ConfigPath) {
        try {
            $raw = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction SilentlyContinue
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $cfg = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($cfg) {
                    if ($cfg.PSObject.Properties.Name -contains "PreferredPlaybackDeviceGuid") { $currentPlaybackGuid = [string]$cfg.PreferredPlaybackDeviceGuid }
                    if ($cfg.PSObject.Properties.Name -contains "PreferredPlaybackDeviceName") { $currentPlaybackName = [string]$cfg.PreferredPlaybackDeviceName }
                    if ($cfg.PSObject.Properties.Name -contains "PreferredCommDeviceGuid") { $currentCommGuid = [string]$cfg.PreferredCommDeviceGuid }
                    if ($cfg.PSObject.Properties.Name -contains "PreferredCommDeviceName") { $currentCommName = [string]$cfg.PreferredCommDeviceName }
                }
            }
        } catch {}
    }

    # Sync these to script scope so other methods or the UI are consistent
    $script:PreferredPlaybackDeviceGuid = $currentPlaybackGuid
    $script:PreferredPlaybackDeviceName = $currentPlaybackName
    $script:PreferredCommDeviceGuid = $currentCommGuid
    $script:PreferredCommDeviceName = $currentCommName

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "Set Preferred Audio Device"
    $dialog.ClientSize = New-Object System.Drawing.Size([int](420 * $script:DpiScale), [int](330 * $script:DpiScale))
    $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false

    if ($form -and $form.Icon) {
        $dialog.Icon = $form.Icon
    }

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Preferred Audio Devices"
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", [float](12 * $script:DpiScale), [System.Drawing.FontStyle]::Bold)
    $lblTitle.Location = New-Object System.Drawing.Point([int](15 * $script:DpiScale), [int](15 * $script:DpiScale))
    $lblTitle.Size = New-Object System.Drawing.Size([int](410 * $script:DpiScale), [int](25 * $script:DpiScale))
    $dialog.Controls.Add($lblTitle)

    $lblCurrentTitle = New-Object System.Windows.Forms.Label
    $lblCurrentTitle.Text = "Current Settings in Config:"
    $lblCurrentTitle.Font = New-Object System.Drawing.Font("Segoe UI", [float](10 * $script:DpiScale), [System.Drawing.FontStyle]::Bold)
    $lblCurrentTitle.Location = New-Object System.Drawing.Point([int](15 * $script:DpiScale), [int](45 * $script:DpiScale))
    $lblCurrentTitle.Size = New-Object System.Drawing.Size([int](390 * $script:DpiScale), [int](15 * $script:DpiScale))
    $dialog.Controls.Add($lblCurrentTitle)

    $lblCurrentPlayback = New-Object System.Windows.Forms.Label
    $playbackName = if ($script:PreferredPlaybackDeviceName) { $script:PreferredPlaybackDeviceName } else { "(None)" }
    $lblCurrentPlayback.Text = "Playback: $playbackName"
    $lblCurrentPlayback.Font = $dialogFont
    $lblCurrentPlayback.Location = New-Object System.Drawing.Point([int](25 * $script:DpiScale), [int](65 * $script:DpiScale))
    $lblCurrentPlayback.Size = New-Object System.Drawing.Size([int](380 * $script:DpiScale), [int](20 * $script:DpiScale))
    $lblCurrentPlayback.UseMnemonic = $false
    $dialog.Controls.Add($lblCurrentPlayback)

    $lblCurrentComm = New-Object System.Windows.Forms.Label
    $commName = if ($script:PreferredCommDeviceName) { $script:PreferredCommDeviceName } else { "(None)" }
    $lblCurrentComm.Text = "Communications: $commName"
    $lblCurrentComm.Font = $dialogFont
    $lblCurrentComm.Location = New-Object System.Drawing.Point([int](25 * $script:DpiScale), [int](85 * $script:DpiScale))
    $lblCurrentComm.Size = New-Object System.Drawing.Size([int](380 * $script:DpiScale), [int](20 * $script:DpiScale))
    $lblCurrentComm.UseMnemonic = $false
    $dialog.Controls.Add($lblCurrentComm)

    $lblSelectPlayback = New-Object System.Windows.Forms.Label
    $lblSelectPlayback.Text = "Preferred Playback Device:"
    $lblSelectPlayback.Font = $dialogFont
    $lblSelectPlayback.Location = New-Object System.Drawing.Point([int](15 * $script:DpiScale), [int](115 * $script:DpiScale))
    $lblSelectPlayback.Size = New-Object System.Drawing.Size([int](390 * $script:DpiScale), [int](18 * $script:DpiScale))
    $dialog.Controls.Add($lblSelectPlayback)

    $comboPlayback = New-Object System.Windows.Forms.ComboBox
    $comboPlayback.Font = $dialogFont
    $comboPlayback.Location = New-Object System.Drawing.Point([int](15 * $script:DpiScale), [int](135 * $script:DpiScale))
    $comboPlayback.Size = New-Object System.Drawing.Size([int](390 * $script:DpiScale), [int](25 * $script:DpiScale))
    $comboPlayback.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $comboPlayback.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
    if ($null -ne $global:comboDrawItem) {
        $comboPlayback.add_DrawItem($global:comboDrawItem)
    }
    $dialog.Controls.Add($comboPlayback)

    $lblSelectComm = New-Object System.Windows.Forms.Label
    $lblSelectComm.Text = "Preferred Communications Device:"
    $lblSelectComm.Font = $dialogFont
    $lblSelectComm.Location = New-Object System.Drawing.Point([int](15 * $script:DpiScale), [int](170 * $script:DpiScale))
    $lblSelectComm.Size = New-Object System.Drawing.Size([int](390 * $script:DpiScale), [int](18 * $script:DpiScale))
    $dialog.Controls.Add($lblSelectComm)

    $comboComm = New-Object System.Windows.Forms.ComboBox
    $comboComm.Font = $dialogFont
    $comboComm.Location = New-Object System.Drawing.Point([int](15 * $script:DpiScale), [int](190 * $script:DpiScale))
    $comboComm.Size = New-Object System.Drawing.Size([int](390 * $script:DpiScale), [int](25 * $script:DpiScale))
    $comboComm.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $comboComm.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
    if ($null -ne $global:comboDrawItem) {
        $comboComm.add_DrawItem($global:comboDrawItem)
    }
    $dialog.Controls.Add($comboComm)

    # Populate dropdowns using Get-AudioEndpoints
    $devices = Get-AudioEndpoints
    $playbackItems = [System.Collections.Generic.List[System.Object]]::new()
    $commItems = [System.Collections.Generic.List[System.Object]]::new()

    $defaultObj = New-Object SamishAudio.AudioDeviceItem("", "(No Preferred Device)")
    $playbackItems.Add($defaultObj)
    $commItems.Add($defaultObj)

    foreach ($d in $devices) {
        $playbackItems.Add($d)
        $commItems.Add($d)
    }

    $comboPlayback.Items.Clear()
    foreach ($item in $playbackItems) {
        [void]$comboPlayback.Items.Add($item)
    }

    $comboComm.Items.Clear()
    foreach ($item in $commItems) {
        [void]$comboComm.Items.Add($item)
    }

    $selectedPlaybackIndex = 0
    for ($i = 0; $i -lt $playbackItems.Count; $i++) {
        if ($playbackItems[$i].Guid -eq $script:PreferredPlaybackDeviceGuid) {
            $selectedPlaybackIndex = $i
            break
        }
    }
    $comboPlayback.SelectedIndex = $selectedPlaybackIndex

    $selectedCommIndex = 0
    for ($i = 0; $i -lt $commItems.Count; $i++) {
        if ($commItems[$i].Guid -eq $script:PreferredCommDeviceGuid) {
            $selectedCommIndex = $i
            break
        }
    }
    $comboComm.SelectedIndex = $selectedCommIndex

    $btnUseCurrent = New-Object System.Windows.Forms.Button
    $btnUseCurrent.Text = "Use Current Defaults"
    $btnUseCurrent.Font = $font
    $btnUseCurrent.Size = New-Object System.Drawing.Size([int](187 * $script:DpiScale), [int](28 * $script:DpiScale))
    $btnUseCurrent.Location = New-Object System.Drawing.Point([int](15 * $script:DpiScale), [int](230 * $script:DpiScale))
    $btnUseCurrent.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnUseCurrent.FlatAppearance.BorderSize = 1
    $btnUseCurrent.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
    $dialog.Controls.Add($btnUseCurrent)

    $btnClear = New-Object System.Windows.Forms.Button
    $btnClear.Text = "Clear Preferred Devices"
    $btnClear.Font = $font
    $btnClear.Size = New-Object System.Drawing.Size([int](187 * $script:DpiScale), [int](28 * $script:DpiScale))
    $btnClear.Location = New-Object System.Drawing.Point([int](218 * $script:DpiScale), [int](230 * $script:DpiScale))
    $btnClear.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnClear.FlatAppearance.BorderSize = 1
    $btnClear.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
    $dialog.Controls.Add($btnClear)

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "Save"
    $btnSave.Font = $font
    $btnSave.Size = New-Object System.Drawing.Size([int](115 * $script:DpiScale), [int](30 * $script:DpiScale))
    $btnSave.Location = New-Object System.Drawing.Point([int](160 * $script:DpiScale), [int](280 * $script:DpiScale))
    $btnSave.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnSave.FlatAppearance.BorderSize = 1
    $btnSave.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
    $dialog.Controls.Add($btnSave)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Font = $font
    $btnCancel.Size = New-Object System.Drawing.Size([int](115 * $script:DpiScale), [int](30 * $script:DpiScale))
    $btnCancel.Location = New-Object System.Drawing.Point([int](290 * $script:DpiScale), [int](280 * $script:DpiScale))
    $btnCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCancel.FlatAppearance.BorderSize = 1
    $btnCancel.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
    $dialog.Controls.Add($btnCancel)

    # Dedicated local tooltip instance
    $localTooltip = New-SamishToolTip
    $localTooltip.SetToolTip($lblTitle, "Preferred Audio Devices configuration panel.")
    $localTooltip.SetToolTip($lblCurrentTitle, "Current audio devices stored in SAMISH configuration.")
    $localTooltip.SetToolTip($lblCurrentPlayback, "Currently saved preferred playback device.")
    $localTooltip.SetToolTip($lblCurrentComm, "Currently saved preferred communications device.")
    $localTooltip.SetToolTip($lblSelectPlayback, "Choose the preferred playback device.")
    $localTooltip.SetToolTip($lblSelectComm, "Choose the preferred communications device.")
    $localTooltip.SetToolTip($comboPlayback, "Select preferred playback audio device.")
    $localTooltip.SetToolTip($comboComm, "Select preferred communications audio device.")
    $localTooltip.SetToolTip($btnUseCurrent, "Capture current active Windows default playback and communications devices and select them as preferred.")
    $localTooltip.SetToolTip($btnClear, "Clear preferred devices from SAMISH configuration.")
    $localTooltip.SetToolTip($btnSave, "Save changes and close.")
    $localTooltip.SetToolTip($btnCancel, "Discard changes and close.")

    $btnUseCurrent.add_Click({
        try {
            $defaults = Get-DefaultAudioDeviceIds
            if ($defaults) {
                $pbIndex = 0
                for ($i = 0; $i -lt $playbackItems.Count; $i++) {
                    if ($playbackItems[$i].Guid -eq $defaults.PlaybackGuid) {
                        $pbIndex = $i
                        break
                    }
                }
                $comboPlayback.SelectedIndex = $pbIndex

                $cmIndex = 0
                for ($i = 0; $i -lt $commItems.Count; $i++) {
                    if ($commItems[$i].Guid -eq $defaults.CommGuid) {
                        $cmIndex = $i
                        break
                    }
                }
                $comboComm.SelectedIndex = $cmIndex

                [System.Windows.Forms.MessageBox]::Show(
                    "Current system default devices selected:`r`n`r`nPlayback: $($defaults.PlaybackName)`r`nCommunications: $($defaults.CommName)`r`n`r`nClick Save to persist.",
                    "Capture Defaults",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
            } else {
                [System.Windows.Forms.MessageBox]::Show(
                    "Failed to capture current default audio devices.",
                    "Error",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                ) | Out-Null
            }
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Error capturing defaults: $_",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    })

    $btnClear.add_Click({
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Are you sure you want to clear your preferred audio device settings?`r`nThis will reset them to empty strings.",
            "Confirm Clear Settings",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
            $comboPlayback.SelectedIndex = 0
            $comboComm.SelectedIndex = 0
            
            Update-ConfigKey -Key "PreferredPlaybackDeviceGuid" -Value ""
            Update-ConfigKey -Key "PreferredPlaybackDeviceName" -Value ""
            Update-ConfigKey -Key "PreferredCommDeviceGuid" -Value ""
            Update-ConfigKey -Key "PreferredCommDeviceName" -Value ""

            $lblCurrentPlayback.Text = "Playback: (None)"
            $lblCurrentComm.Text = "Communications: (None)"

            [System.Windows.Forms.MessageBox]::Show(
                "Preferred devices cleared.",
                "Cleared",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
    })

    $btnSave.add_Click({
        $selPlayback = $comboPlayback.SelectedItem
        $selComm = $comboComm.SelectedItem

        Update-ConfigKey -Key "PreferredPlaybackDeviceGuid" -Value $selPlayback.Guid
        Update-ConfigKey -Key "PreferredPlaybackDeviceName" -Value $selPlayback.Name
        Update-ConfigKey -Key "PreferredCommDeviceGuid" -Value $selComm.Guid
        Update-ConfigKey -Key "PreferredCommDeviceName" -Value $selComm.Name

        $lblCurrentPlayback.Text = "Playback: $(if ($selPlayback.Name) { $selPlayback.Name } else { '(None)' })"
        $lblCurrentComm.Text = "Communications: $(if ($selComm.Name) { $selComm.Name } else { '(None)' })"

        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dialog.Close()
    })

    $btnCancel.add_Click({
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $dialog.Close()
    })

    if (Get-Command Set-BrandTheme -ErrorAction SilentlyContinue) {
        Set-BrandTheme -Form $dialog -IsCustom $global:ThemeCustomActive
    }

    $dialog.ShowDialog() | Out-Null
    $dialog.Dispose()
}

if ($script:btnPreferredAudio) {
    $script:btnPreferredAudio.add_Click({
        Show-PreferredAudioDialog
    })
}

function Show-GameModeDialog {
    # Dynamically read current config values at open
    $currentEnabled = $false
    $currentList = @()

    if (Test-Path -LiteralPath $ConfigPath) {
        try {
            $raw = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction SilentlyContinue
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $cfg = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($cfg) {
                    if ($cfg.PSObject.Properties.Name -contains "GameModeEnabled") { $currentEnabled = [bool]$cfg.GameModeEnabled }
                    if ($cfg.PSObject.Properties.Name -contains "GameModeList") { $currentList = @($cfg.GameModeList) }
                }
            }
        } catch {}
    }

    # Sync to script scope
    $script:GameModeEnabled = $currentEnabled
    $script:GameModeList = $currentList

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "Game Mode Settings"
    $dialog.ClientSize = New-Object System.Drawing.Size([int](420 * $script:DpiScale), [int](450 * $script:DpiScale))
    $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false

    if ($form -and $form.Icon) {
        $dialog.Icon = $form.Icon
    }

    $dialogFont = if ($null -ne $font) { $font } else { New-Object System.Drawing.Font("Segoe UI", [float](10 * $script:DpiScale)) }

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Game Mode Settings"
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", [float](12 * $script:DpiScale), [System.Drawing.FontStyle]::Bold)
    $lblTitle.Location = New-Object System.Drawing.Point([int](15 * $script:DpiScale), [int](15 * $script:DpiScale))
    $lblTitle.Size = New-Object System.Drawing.Size([int](390 * $script:DpiScale), [int](25 * $script:DpiScale))
    $dialog.Controls.Add($lblTitle)

    $chkEnabled = New-Object System.Windows.Forms.CheckBox
    $chkEnabled.Text = "Enable Game-Mode Guard"
    $chkEnabled.Checked = $script:GameModeEnabled
    $chkEnabled.Font = $dialogFont
    $chkEnabled.Location = New-Object System.Drawing.Point([int](15 * $script:DpiScale), [int](50 * $script:DpiScale))
    $chkEnabled.Size = New-Object System.Drawing.Size([int](390 * $script:DpiScale), [int](20 * $script:DpiScale))
    $dialog.Controls.Add($chkEnabled)

    $lblListBox = New-Object System.Windows.Forms.Label
    $lblListBox.Text = "Monitored Applications and Games:"
    $lblListBox.Font = $dialogFont
    $lblListBox.Location = New-Object System.Drawing.Point([int](15 * $script:DpiScale), [int](80 * $script:DpiScale))
    $lblListBox.Size = New-Object System.Drawing.Size([int](390 * $script:DpiScale), [int](18 * $script:DpiScale))
    $dialog.Controls.Add($lblListBox)

    $lstGames = New-Object System.Windows.Forms.ListBox
    $lstGames.Font = $dialogFont
    $lstGames.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
    $lstGames.Location = New-Object System.Drawing.Point([int](15 * $script:DpiScale), [int](100 * $script:DpiScale))
    $lstGames.Size = New-Object System.Drawing.Size([int](390 * $script:DpiScale), [int](180 * $script:DpiScale))
    foreach ($game in $script:GameModeList) {
        if (-not [string]::IsNullOrWhiteSpace($game)) {
            [void]$lstGames.Items.Add($game.ToLower())
        }
    }
    $dialog.Controls.Add($lstGames)

    # ListBox item custom draw handler (Cyan/SAMISH Blue highlight)
    $lstGamesDrawItem = {
        param($sender, $e)
        if ($e.Index -lt 0 -or $e.Index -ge $sender.Items.Count) { return }

        $itemText = $sender.Items[$e.Index].ToString()
        $isHighlighted = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -eq [System.Windows.Forms.DrawItemState]::Selected

        $highlightColor = if ($global:ThemeCustomActive) { $global:ThemeCustomPrimary } else { $script:BrandCyan }
        if ($null -eq $highlightColor) { $highlightColor = [System.Drawing.Color]::FromArgb(0, 215, 255) }

        if ($isHighlighted) {
            $brushBack = New-Object System.Drawing.SolidBrush($highlightColor)
            $e.Graphics.FillRectangle($brushBack, $e.Bounds)
            $brushBack.Dispose()
        }
        else {
            $brushBack = New-Object System.Drawing.SolidBrush($sender.BackColor)
            $e.Graphics.FillRectangle($brushBack, $e.Bounds)
            $brushBack.Dispose()
        }

        $foreColor = if ($isHighlighted) {
            [System.Drawing.Color]::Black
        }
        else {
            $sender.ForeColor
        }
        $brushFore = New-Object System.Drawing.SolidBrush($foreColor)
        
        $rect = New-Object System.Drawing.RectangleF($e.Bounds.X, $e.Bounds.Y, $e.Bounds.Width, $e.Bounds.Height)
        $textFormat = New-Object System.Drawing.StringFormat
        $textFormat.LineAlignment = [System.Drawing.StringAlignment]::Center

        $e.Graphics.DrawString($itemText, $e.Font, $brushFore, $rect, $textFormat)
    
        $brushFore.Dispose()
        $textFormat.Dispose()
        $e.DrawFocusRectangle()
    }
    $lstGames.add_DrawItem($lstGamesDrawItem)

    $lblAdd = New-Object System.Windows.Forms.Label
    $lblAdd.Text = "Add Process Name:"
    $lblAdd.Font = $dialogFont
    $lblAdd.Location = New-Object System.Drawing.Point([int](15 * $script:DpiScale), [int](290 * $script:DpiScale))
    $lblAdd.Size = New-Object System.Drawing.Size([int](390 * $script:DpiScale), [int](18 * $script:DpiScale))
    $dialog.Controls.Add($lblAdd)

    $txtAdd = New-Object System.Windows.Forms.TextBox
    $txtAdd.Font = $dialogFont
    $txtAdd.Location = New-Object System.Drawing.Point([int](15 * $script:DpiScale), [int](310 * $script:DpiScale))
    $txtAdd.Size = New-Object System.Drawing.Size([int](260 * $script:DpiScale), [int](25 * $script:DpiScale))
    $dialog.Controls.Add($txtAdd)

    $btnAdd = New-Object System.Windows.Forms.Button
    $btnAdd.Text = "Add"
    $btnAdd.Font = $dialogFont
    $btnAdd.Size = New-Object System.Drawing.Size([int](115 * $script:DpiScale), [int](28 * $script:DpiScale))
    $btnAdd.Location = New-Object System.Drawing.Point([int](290 * $script:DpiScale), [int](309 * $script:DpiScale))
    $btnAdd.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnAdd.FlatAppearance.BorderSize = 1
    $btnAdd.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
    $dialog.Controls.Add($btnAdd)

    $btnRemove = New-Object System.Windows.Forms.Button
    $btnRemove.Text = "Remove Selected"
    $btnRemove.Font = $dialogFont
    $btnRemove.Size = New-Object System.Drawing.Size([int](120 * $script:DpiScale), [int](28 * $script:DpiScale))
    $btnRemove.Location = New-Object System.Drawing.Point([int](15 * $script:DpiScale), [int](350 * $script:DpiScale))
    $btnRemove.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnRemove.FlatAppearance.BorderSize = 1
    $btnRemove.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
    $dialog.Controls.Add($btnRemove)

    $btnScanFolder = New-Object System.Windows.Forms.Button
    $btnScanFolder.Text = "Add from Folder"
    $btnScanFolder.Font = $dialogFont
    $btnScanFolder.Size = New-Object System.Drawing.Size([int](125 * $script:DpiScale), [int](28 * $script:DpiScale))
    $btnScanFolder.Location = New-Object System.Drawing.Point([int](150 * $script:DpiScale), [int](350 * $script:DpiScale))
    $btnScanFolder.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnScanFolder.FlatAppearance.BorderSize = 1
    $btnScanFolder.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
    $dialog.Controls.Add($btnScanFolder)

    $btnDetect = New-Object System.Windows.Forms.Button
    $btnDetect.Text = "Scan Running"
    $btnDetect.Font = $dialogFont
    $btnDetect.Size = New-Object System.Drawing.Size([int](115 * $script:DpiScale), [int](28 * $script:DpiScale))
    $btnDetect.Location = New-Object System.Drawing.Point([int](290 * $script:DpiScale), [int](350 * $script:DpiScale))
    $btnDetect.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnDetect.FlatAppearance.BorderSize = 1
    $btnDetect.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
    $dialog.Controls.Add($btnDetect)

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "Save"
    $btnSave.Font = $dialogFont
    $btnSave.Size = New-Object System.Drawing.Size([int](115 * $script:DpiScale), [int](30 * $script:DpiScale))
    $btnSave.Location = New-Object System.Drawing.Point([int](160 * $script:DpiScale), [int](400 * $script:DpiScale))
    $btnSave.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnSave.FlatAppearance.BorderSize = 1
    $btnSave.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
    $dialog.Controls.Add($btnSave)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Font = $dialogFont
    $btnCancel.Size = New-Object System.Drawing.Size([int](115 * $script:DpiScale), [int](30 * $script:DpiScale))
    $btnCancel.Location = New-Object System.Drawing.Point([int](290 * $script:DpiScale), [int](400 * $script:DpiScale))
    $btnCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCancel.FlatAppearance.BorderSize = 1
    $btnCancel.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
    $dialog.Controls.Add($btnCancel)

    # Dedicated local tooltip instance
    $localTooltip = New-SamishToolTip
    $localTooltip.SetToolTip($lblTitle, "Game Mode Settings configuration panel.")
    $localTooltip.SetToolTip($chkEnabled, "Toggle Game-Mode Guard. When enabled, sleep diagnostics`r`nare paused when running listed games or applications.")
    $localTooltip.SetToolTip($lblListBox, "List of process names that trigger Game Mode when they are running.")
    $localTooltip.SetToolTip($lstGames, "Shows currently configured game and application process names. Select a name to remove it.")
    $localTooltip.SetToolTip($lblAdd, "Enter a process name to add to the monitored list.`r`nExtension '.exe' is not required.")
    $localTooltip.SetToolTip($txtAdd, "Type the executable name here (e.g. cyber_engine_tweaks).`r`nThe '.exe' extension is not required and will be automatically stripped.")
    $localTooltip.SetToolTip($btnAdd, "Add the process name from the text box to the monitored list.`r`nExtension '.exe' is not required.")
    $localTooltip.SetToolTip($btnRemove, "Remove the selected process name from the monitored list.")
    $localTooltip.SetToolTip($btnScanFolder, "Select a game library or installation directory to scan`r`nand automatically add its executable files.")
    $localTooltip.SetToolTip($btnDetect, "Scan currently running processes and automatically`r`nadd active game or launcher executables.")
    $localTooltip.SetToolTip($btnSave, "Save changes to config.json and close the dialog.")
    $localTooltip.SetToolTip($btnCancel, "Discard changes and close the dialog.")

    # Event handlers
    $btnAdd.add_Click({
        $name = $txtAdd.Text.Trim()
        if (-not [string]::IsNullOrEmpty($name)) {
            if ($name.EndsWith(".exe", [System.StringComparison]::OrdinalIgnoreCase)) {
                $name = $name.Substring(0, $name.Length - 4)
            }
            $name = $name.ToLower()
            if (-not $lstGames.Items.Contains($name)) {
                [void]$lstGames.Items.Add($name)
                $txtAdd.Text = ""
            } else {
                [System.Windows.Forms.MessageBox]::Show(
                    "Process name '$name' is already in the list.",
                    "Duplicate Process",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                ) | Out-Null
            }
        }
    })

    $btnRemove.add_Click({
        $selIndex = $lstGames.SelectedIndex
        if ($selIndex -ge 0) {
            $lstGames.Items.RemoveAt($selIndex)
        } else {
            [System.Windows.Forms.MessageBox]::Show(
                "Please select a process name from the list to remove.",
                "No Selection",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
    })

    $btnScanFolder.add_Click({
        try {
            $dialogFolder = New-Object System.Windows.Forms.FolderBrowserDialog
            $dialogFolder.Description = "Select a folder to scan for application and game executables (e.g., Steam library or game install directory)"
            $dialogFolder.ShowNewFolderButton = $false
            if ($dialogFolder.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $path = $dialogFolder.SelectedPath
                if (-not [string]::IsNullOrEmpty($path) -and (Test-Path -LiteralPath $path)) {
                    $dialog.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
                    
                    # Recursively find .exe files
                    $files = @()
                    try {
                        $files = Get-ChildItem -LiteralPath $path -Filter *.exe -File -Recurse -ErrorAction SilentlyContinue
                    } catch {}

                    $added = @()
                    $ignoredKeywords = @("uninstall", "redist", "vc_redist", "crashhandler", "touchup", "cleanup", "helper", "setup", "install", "update", "config", "cefsharp", "unitycrashhandler")

                    foreach ($file in $files) {
                        $name = $file.BaseName.ToLower()
                        # Filter out common installers, uninstallers, helpers
                        $ignore = $false
                        foreach ($keyword in $ignoredKeywords) {
                            if ($name -like "*$keyword*") {
                                $ignore = $true
                                break
                            }
                        }
                        if (-not $ignore -and -not [string]::IsNullOrWhiteSpace($name)) {
                            if (-not $lstGames.Items.Contains($name)) {
                                [void]$lstGames.Items.Add($name)
                                $added += $name
                            }
                        }
                    }

                    $dialog.Cursor = [System.Windows.Forms.Cursors]::Default

                    if ($added.Count -gt 0) {
                        $msg = "Successfully scanned folder.`r`nAdded $($added.Count) process names to the list."
                        [System.Windows.Forms.MessageBox]::Show(
                            $msg,
                            "Folder Scan Complete",
                            [System.Windows.Forms.MessageBoxButtons]::OK,
                            [System.Windows.Forms.MessageBoxIcon]::Information
                        ) | Out-Null
                    } else {
                        [System.Windows.Forms.MessageBox]::Show(
                            "No new executables were found in the selected folder.",
                            "Scan Complete",
                            [System.Windows.Forms.MessageBoxButtons]::OK,
                            [System.Windows.Forms.MessageBoxIcon]::Information
                        ) | Out-Null
                    }
                }
            }
            $dialogFolder.Dispose()
        }
        catch {
            $dialog.Cursor = [System.Windows.Forms.Cursors]::Default
            [System.Windows.Forms.MessageBox]::Show(
                "Error scanning folder: $_",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    })

    $btnDetect.add_Click({
        try {
            $commonGames = @(
                "steam", "epicgameslauncher", "galaxyclient", "eadesktop", "upc", "riotclientux", 
                "battle.net", "origin", "discord", "cs2", "valorant", "fortniteclient-win64-shipping", 
                "minecraft", "gta5", "r5apex", "cyberpunk2077", "cod", "eldenring", "hl2", "portal2", 
                "witcher3", "starfield"
            )
            $detected = @()
            $runningProcs = Get-Process -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ProcessName -Unique
            foreach ($proc in $runningProcs) {
                $procLower = $proc.ToLower()
                if ($commonGames -contains $procLower) {
                    if (-not $lstGames.Items.Contains($procLower)) {
                        [void]$lstGames.Items.Add($procLower)
                        $detected += $procLower
                    }
                }
            }
            if ($detected.Count -gt 0) {
                $msg = "Detected and added $($detected.Count) game processes:`r`n`r`n" + ($detected -join ", ")
                [System.Windows.Forms.MessageBox]::Show(
                    $msg,
                    "Games Detected",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
            } else {
                [System.Windows.Forms.MessageBox]::Show(
                    "No running games from the common list were detected.",
                    "None Detected",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
            }
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Error scanning running processes: $_",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    })

    $btnSave.add_Click({
        $items = @()
        foreach ($item in $lstGames.Items) {
            $items += [string]$item
        }
        $enabledState = [bool]$chkEnabled.Checked

        Update-ConfigKey -Key "GameModeEnabled" -Value $enabledState
        Update-ConfigKey -Key "GameModeList" -Value $items

        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dialog.Close()
    })

    $btnCancel.add_Click({
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $dialog.Close()
    })

    if (Get-Command Set-BrandTheme -ErrorAction SilentlyContinue) {
        Set-BrandTheme -Form $dialog -IsCustom $global:ThemeCustomActive
    }

    $dialog.ShowDialog() | Out-Null
    $dialog.Dispose()
}

if ($script:btnGameMode) {
    $script:btnGameMode.add_Click({
        Show-GameModeDialog
    })
}





