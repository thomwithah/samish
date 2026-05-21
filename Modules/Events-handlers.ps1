# ---------- UI wiring ----------

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
        if ($ddHotkey.SelectedItem.ToString() -eq "Custom") {
            $tbCustomKey.Enabled = $true
            $tbCustomKey.Focus()
        }
        else {
            $tbCustomKey.Enabled = $false
        }
    })

# --- Simple buttons ---
$btnOpenTS.add_Click({ Start-Process "taskschd.msc" | Out-Null })

# --- Power plan tool ---
$btnPowerPlan.add_Click({
        try {
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

$btnLiveLog.add_Click({
        if ($script:IsLiveLogMode) {
            Exit-LiveLogMode
        }
        else {
            Enter-LiveLogMode
        }
    })

$script:DeferredStatusText = $null

function Set-StatusText([string]$text) {

    # If live log is active, do NOT overwrite the live log display.
    # Instead, buffer the update for restoration when Live Log exits.
    if ($script:IsLiveLogMode) {

        $script:DeferredStatusLatest = $text

        # Store a small queue (helpful if multiple actions happen during Live Log)
        $script:DeferredStatusUpdates += $text

        # Hard cap queue to avoid runaway memory in long sessions
        if ($script:DeferredStatusUpdates.Count -gt 25) {
            $script:DeferredStatusUpdates = $script:DeferredStatusUpdates[-25..-1]
        }

        return
    }

    # Normal behavior
    $statusBox.Text = $text
    $statusBox.Refresh()
}

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
                -ActiveProfileId $script:ActiveProfileId `
                -ProfilesEnabled $script:ProfilesEnabled

            Set-StatusText("Installing...")

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
    })

# ============================================================
# Sleep & Hibernate Diagnostics - Event Wiring
# ============================================================

$btnSleepDiag.add_Click({
        try {
            Show-SleepDiagnosticsDialog
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Failed to open Sleep & Hibernate Diagnostics:`r`n$($_.Exception.Message)",
                "SAMISH - Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    })

# ---- Helpers ------------------------------------------------

function Update-SleepDiagnosticsLists {
    $script:listBlockers.Items.Clear()
    $script:listOverrides.Items.Clear()
    $script:listAutomated.Items.Clear()

    # ---- Active Blockers ----
    $script:ActiveBlockersList = @()
    try {
        $blockers = Get-ActiveSleepBlockers
        foreach ($b in $blockers) {
            # BEACN is already natively managed by SAMISH - skip from the list
            if ($b.ProcessName -like "*BEACN*" -or $b.DisplayName -like "*BEACN*") { continue }
            $script:ActiveBlockersList += $b
            $icon = switch ($b.BlockerType) {
                'App' { "[App]" }
                'Driver' { "[Driver]" }
                'Service' { "[Service]" }
                default { "[?]" }
            }
            $script:listBlockers.Items.Add("$icon $($b.DisplayName)") | Out-Null
        }
    }
    catch {
        $script:lblDiagDetail.Text = "Error scanning blockers: $($_.Exception.Message)"
    }
    if ($script:listBlockers.Items.Count -eq 0) {
        $script:listBlockers.Items.Add("(No active blockers found - your system can sleep!)") | Out-Null
    }

    # ---- System Overrides ----
    $script:SystemOverridesList = @()
    try {
        $overrides = Get-SystemOverrides
        foreach ($ov in $overrides) {
            # Skip BEACN overrides that SAMISH manages
            if ($ov.Name -like "*BEACN*") { continue }
            $script:SystemOverridesList += $ov
            $script:listOverrides.Items.Add($ov.DisplayLabel) | Out-Null
        }
    }
    catch {}
    if ($script:listOverrides.Items.Count -eq 0) {
        $script:listOverrides.Items.Add("(No custom overrides configured)") | Out-Null
    }

    # ---- Automated Apps ----
    if ($script:MonitoredApps) {
        foreach ($app in $script:MonitoredApps) {
            $modeTag = if ($app.RecoveryMode) { " [$($app.RecoveryMode)]" } else { "" }
            $script:listAutomated.Items.Add("$($app.ProcessName)$modeTag") | Out-Null
        }
    }
    if ($script:listAutomated.Items.Count -eq 0) {
        $script:listAutomated.Items.Add("(No apps automated by SAMISH yet)") | Out-Null
    }
}

function Save-MonitoredAppsToConfig {
    Ensure-InstallFolder
    try {
        $cfg = @{}
        if (Test-Path -LiteralPath $ConfigPath) {
            $cfg = (Get-Content -LiteralPath $ConfigPath -Raw) | ConvertFrom-Json
        }
        $cfg.MonitoredApps = $script:MonitoredApps
        $json = $cfg | ConvertTo-Json -Depth 6
        Set-Content -LiteralPath $ConfigPath -Value $json -Encoding UTF8
        Write-SetupLog "Saved MonitoredApps config update."
    }
    catch {
        Write-SetupLog "Error saving MonitoredApps: $($_.Exception.Message)"
    }
}

# ---- Main init (called from Show-SleepDiagnosticsDialog) ----

function Init-SleepDiagnosticsEventHandlers {

    # Populate lists on first open
    Update-SleepDiagnosticsLists

    # ---------- Scan Blockers ----------
    $script:btnDiagScan.add_Click({
            Update-SleepDiagnosticsLists
            $script:lblDiagDetail.Text = "Scan complete - $(Get-Date -Format 'HH:mm:ss')."
        })

    # ---------- Active Blockers selection ----------
    $script:listBlockers.add_SelectedIndexChanged({
            $idx = $script:listBlockers.SelectedIndex
            $hasValidItem = ($idx -ge 0 -and $idx -lt $script:ActiveBlockersList.Count)

            $script:btnDiagAutomate.Enabled = $false
            $script:btnDiagIgnore.Enabled = $false

            if (-not $hasValidItem) {
                $script:lblDiagDetail.Text = "Select an active blocker to see details."
                return
            }

            $b = $script:ActiveBlockersList[$idx]
            $script:lblDiagDetail.Text = "[$($b.BlockerType)]  $($b.DisplayName)`r`nSection: $($b.Section)    Reason: $($b.Reason)"

            # Enable buttons based on type - mutually exclusive
            if ($b.BlockerType -eq 'App') {
                $script:btnDiagAutomate.Enabled = $true
                $script:btnDiagIgnore.Enabled = $false
            }
            else {
                $script:btnDiagAutomate.Enabled = $false
                $script:btnDiagIgnore.Enabled = $true
            }
        })

    # ---------- System Overrides selection ----------
    $script:listOverrides.add_SelectedIndexChanged({
            $idx = $script:listOverrides.SelectedIndex
            $hasValidItem = ($idx -ge 0 -and $idx -lt $script:SystemOverridesList.Count)
            $script:btnDiagRestore.Enabled = $hasValidItem
            if ($hasValidItem) {
                $ov = $script:SystemOverridesList[$idx]
                $script:lblDiagDetail.Text = "Ignored: [$($ov.OverrideType)]  $($ov.Name)    Requests overridden: $($ov.Requests)"
            }
        })

    # ---------- Automated Apps selection ----------
    $script:listAutomated.add_SelectedIndexChanged({
            $idx = $script:listAutomated.SelectedIndex
            $hasValidItem = ($idx -ge 0 -and $idx -lt $script:MonitoredApps.Count)
            $script:btnDiagStopAuto.Enabled = $hasValidItem
            $script:btnDiagOpenLocation.Enabled = $hasValidItem
            if ($hasValidItem) {
                $app = $script:MonitoredApps[$idx]
                $mode = if ($app.RecoveryMode) { $app.RecoveryMode } else { "Graceful" }
                $script:lblDiagDetail.Text = "Automated: $($app.ProcessName)    Mode: $mode`r`nPath: $($app.ExecutablePath)"
            }
        })

    # ---------- Automate App ----------
    $script:btnDiagAutomate.add_Click({
            $idx = $script:listBlockers.SelectedIndex
            if ($idx -lt 0 -or $idx -ge $script:ActiveBlockersList.Count) { return }

            $b = $script:ActiveBlockersList[$idx]
            if ($b.BlockerType -ne 'App') {
                [System.Windows.Forms.MessageBox]::Show(
                    "Only application processes can be automated by SAMISH.`r`nFor drivers or services, use 'Ignore Blocker' instead.",
                    "SAMISH - Apps Only",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
                return
            }

            if ($script:MonitoredApps | Where-Object { $_.ProcessName -eq $b.ProcessName }) {
                [System.Windows.Forms.MessageBox]::Show(
                    "$($b.ProcessName) is already configured for automated recovery.",
                    "SAMISH - Already Configured",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
                return
            }

            $path = Resolve-ProcessExecutablePath -ProcessName $b.ProcessName -ExecutableName $b.ExecutableName
            if (-not $path) {
                [System.Windows.Forms.MessageBox]::Show(
                    "SAMISH could not find the executable for $($b.ProcessName).`r`nMake sure the application is running and try again.",
                    "SAMISH - Path Not Found",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
                return
            }

            $chosenMode = if ($script:rbDiagClassic -and $script:rbDiagClassic.Checked) { "Classic" } else { "Graceful" }

            $modeDetail = if ($chosenMode -eq "Classic") {
                "Classic mode: immediately terminates the app - more reliable, but any unsaved work in that application will be lost."
            }
            else {
                "Graceful mode: asks the app to close cleanly - safer for unsaved work, but may occasionally fail if the app is unresponsive."
            }

            $msg = "SAMISH will automatically close $($b.ProcessName) before your computer sleeps or hibernates, then restart it when the system wakes.`r`n`r`n$modeDetail`r`n`r`nConfigure automated recovery for $($b.ProcessName) using $chosenMode mode?"

            $choice = [System.Windows.Forms.MessageBox]::Show(
                $msg,
                "SAMISH - Confirm Automation",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )

            if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) {
                $newApp = [ordered]@{
                    ProcessName    = $b.ProcessName
                    ExecutablePath = $path
                    RecoveryMode   = $chosenMode
                }
                $script:MonitoredApps += [pscustomobject]$newApp
                Save-MonitoredAppsToConfig
                Update-SleepDiagnosticsLists
                $script:lblDiagDetail.Text = "$($b.ProcessName) has been added to SAMISH automation ($chosenMode mode)."
            }
        })

    # ---------- Ignore Blocker ----------
    $script:btnDiagIgnore.add_Click({
            $idx = $script:listBlockers.SelectedIndex
            if ($idx -lt 0 -or $idx -ge $script:ActiveBlockersList.Count) { return }

            $b = $script:ActiveBlockersList[$idx]

            $typeMap = @{ App = 'PROCESS'; Driver = 'DRIVER'; Service = 'SERVICE' }
            $callerType = $typeMap[$b.BlockerType]
            if (-not $callerType) { $callerType = 'PROCESS' }

            $msg = "Windows will be told to ignore power requests from:`r`n  $($b.DisplayName) [$($b.BlockerType)]`r`n`r`nThis blocker will no longer prevent sleep or hibernation.`r`n`r`nYou can undo this at any time using 'Restore'.`r`n`r`nContinue?"

            $choice = [System.Windows.Forms.MessageBox]::Show(
                $msg,
                "SAMISH - Confirm Override",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )

            if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) {
                try {
                    $requests = @($b.Section)
                    Add-SystemOverride -BlockerType $callerType -Name $b.RawEntry -Requests $requests
                    Update-SleepDiagnosticsLists
                    $script:lblDiagDetail.Text = "Blocker '$($b.DisplayName)' is now ignored - it will not prevent sleep or hibernation."
                }
                catch {
                    [System.Windows.Forms.MessageBox]::Show(
                        "Failed to apply override: $($_.Exception.Message)",
                        "SAMISH - Error",
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Error
                    )
                }
            }
        })

    # ---------- Stop Automating ----------
    $script:btnDiagStopAuto.add_Click({
            $idx = $script:listAutomated.SelectedIndex
            if ($idx -lt 0 -or $idx -ge $script:MonitoredApps.Count) { return }

            $app = $script:MonitoredApps[$idx]

            $choice = [System.Windows.Forms.MessageBox]::Show(
                "Stop automating $($app.ProcessName)?`r`n`r`nSAMISH will no longer close this application before sleep or hibernation, or restart it on wake. The application itself will not be uninstalled or otherwise affected.",
                "SAMISH - Stop Automating",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )

            if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) {
                $script:MonitoredApps = @($script:MonitoredApps | Where-Object { $_.ProcessName -ne $app.ProcessName })
                Save-MonitoredAppsToConfig
                Update-SleepDiagnosticsLists
                $script:lblDiagDetail.Text = "$($app.ProcessName) removed from SAMISH automation."
            }
        })

    # ---------- Open Location ----------
    $script:btnDiagOpenLocation.add_Click({
            $idx = $script:listAutomated.SelectedIndex
            if ($idx -lt 0 -or $idx -ge $script:MonitoredApps.Count) { return }

            $app = $script:MonitoredApps[$idx]
            if ($app.ExecutablePath -and (Test-Path $app.ExecutablePath)) {
                # Open Explorer and select the file
                Start-Process "explorer.exe" -ArgumentList "/select,`"$($app.ExecutablePath)`""
            }
            else {
                [System.Windows.Forms.MessageBox]::Show(
                    "The executable path for $($app.ProcessName) could not be found on disk.",
                    "SAMISH - Path Not Found",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
            }
        })

    # ---------- Restore Blocker ----------
    $script:btnDiagRestore.add_Click({
            $idx = $script:listOverrides.SelectedIndex
            if ($idx -lt 0 -or $idx -ge $script:SystemOverridesList.Count) { return }

            $ov = $script:SystemOverridesList[$idx]

            $choice = [System.Windows.Forms.MessageBox]::Show(
                "Restore the sleep and hibernation power request for:`r`n  $($ov.Name)`r`n`r`nAfter this, the item may once again prevent sleep or hibernation if it holds an active power request.`r`n`r`nContinue?",
                "SAMISH - Confirm Restore",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )

            if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) {
                try {
                    Remove-SystemOverride -BlockerType $ov.OverrideType -Name $ov.Name
                    Update-SleepDiagnosticsLists
                    $script:lblDiagDetail.Text = "Override removed - '$($ov.Name)' may now affect sleep and hibernation."
                }
                catch {
                    [System.Windows.Forms.MessageBox]::Show(
                        "Failed to remove override: $($_.Exception.Message)",
                        "SAMISH - Error",
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Error
                    )
                }
            }
        })
}




