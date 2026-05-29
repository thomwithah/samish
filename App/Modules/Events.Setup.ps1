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

            if ((Test-Path -LiteralPath $script:DeviceWakeBackupPath) -or (Test-Path -LiteralPath $script:TaskWakeBackupPath) -or $hasPowerPlanUsbBackup) {
                $restorePrompt = "SAMISH found backups of system telemetry modifications (disabled wake devices, wake timers, or USB selective suspend settings).`r`n`r`nWould you like to restore these system settings back to their original defaults now?`r`n`r`nIf you choose No, SAMISH will continue to verify your power plan compatibility settings."
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

        }
        catch {
            Set-StatusText("Install failed.`r`nSee details below:`r`n$($_.Exception.Message)")
            Write-SetupLog ("Install failed: " + $_.Exception.Message)
        }

        # Sync Neon tab indicator in case theme is active
        if ($global:ThemeNeonActive) {
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

            if ((Test-Path -LiteralPath $script:DeviceWakeBackupPath) -or (Test-Path -LiteralPath $script:TaskWakeBackupPath) -or $hasPowerPlanUsbBackup) {
                $restorePrompt = "SAMISH found backups of system telemetry modifications (disabled wake devices, wake timers, or USB selective suspend settings).`r`n`r`nWould you like to restore all settings back to their original defaults now?"
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
        if ($global:ThemeNeonActive) {
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
        # Reset action button — context changes when switching tabs
        if ($script:btnTelemetryAction) { 
            $script:btnTelemetryAction.Text = "Select Item..." 
            Update-TelemetryActionTooltip -text "Select an armed hardware device, USB hub, or active wake timer above to take corrective action."
        }
        Update-SecondaryTabStyles
    })
}
if ($script:btnDrawer2TabHardware) {
    $script:btnDrawer2TabHardware.add_Click({
        if ($script:pnlTelemetrySystem)   { $script:pnlTelemetrySystem.Visible = $false }
        if ($script:pnlTelemetryHardware) { $script:pnlTelemetryHardware.Visible = $true }
        if ($script:drawer2TabIndicator)  { $script:drawer2TabIndicator.Location = New-Object System.Drawing.Point([int](190 * $script:DpiScale), [int](154 * $script:DpiScale)) }
        # Reset action button — context changes when switching tabs
        if ($script:btnTelemetryAction) { 
            $script:btnTelemetryAction.Text = "Select Item..." 
            Update-TelemetryActionTooltip -text "Select an armed hardware device, USB hub, or active wake timer above to take corrective action."
        }
        Update-SecondaryTabStyles
    })
}



