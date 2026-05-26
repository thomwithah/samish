# ---------- UI wiring ----------

# ---------- Custom DrawItem event for ComboBoxes (SAMISH Cyan Highlight) ----------
$comboDrawItem = {
    param($sender, $e)
    if ($e.Index -lt 0 -or $e.Index -ge $sender.Items.Count) { return }

    $itemText = $sender.Items[$e.Index].ToString()
    $isHighlighted = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -eq [System.Windows.Forms.DrawItemState]::Selected

    $highlightColor = if ($global:ThemeNeonActive) { $global:NeonCyan } else { $script:BrandCyan }
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
    } elseif (-not $sender.Enabled) {
        if ($global:ThemeNeonActive) {
            $global:NeonCyan
        } else {
            [System.Drawing.Color]::Gray
        }
    } else {
        if ($global:ThemeNeonActive) {
            $global:NeonCyan
        } else {
            $sender.ForeColor
        }
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

$logCtrl = if ($script:ddLogInterval) { $script:ddLogInterval } else { $ddLogInterval }
if ($logCtrl) { $logCtrl.add_DrawItem($comboDrawItem) }

$hkCtrl = if ($script:ddHotkey) { $script:ddHotkey } else { $ddHotkey }
if ($hkCtrl) { $hkCtrl.add_DrawItem($comboDrawItem) }

$wakeCtrl = if ($script:ddDiagOnWakeAction) { $script:ddDiagOnWakeAction } else { $ddOnWakeAction }
if ($wakeCtrl) { $wakeCtrl.add_DrawItem($comboDrawItem) }

$testCtrl = if ($script:ddTestTarget) { $script:ddTestTarget } else { $ddTestTarget }
if ($testCtrl) { $testCtrl.add_DrawItem($comboDrawItem) }

# ---------- Custom Focus Borders for TextBoxes ----------
$tbLogSingle = $null
$arrLogSingle = @($tbLogCustom | Where-Object { $_ -is [System.Windows.Forms.Control] })
if ($arrLogSingle.Count -gt 0) { $tbLogSingle = $arrLogSingle[-1] }

$tbKeySingle = $null
$arrKeySingle = @($tbCustomKey | Where-Object { $_ -is [System.Windows.Forms.Control] })
if ($arrKeySingle.Count -gt 0) { $tbKeySingle = $arrKeySingle[-1] }

if ($cfgGroup) {
    $cfgGroup.add_Paint({
        param($sender, $e)
        try {
            $tbLog = $null
            $arrLog = @($tbLogCustom | Where-Object { $_ -is [System.Windows.Forms.Control] })
            if ($arrLog.Count -gt 0) { $tbLog = $arrLog[-1] }
            
            $tbKey = $null
            $arrKey = @($tbCustomKey | Where-Object { $_ -is [System.Windows.Forms.Control] })
            if ($arrKey.Count -gt 0) { $tbKey = $arrKey[-1] }

            if ($tbLog -is [System.Windows.Forms.Control] -and $tbLog.Focused) {
                $rect = New-Object System.Drawing.Rectangle($tbLog.Location.X - 1, $tbLog.Location.Y - 1, $tbLog.Width + 1, $tbLog.Height + 1)
                $pen = New-Object System.Drawing.Pen($BrandCyan, 2)
                $e.Graphics.DrawRectangle($pen, $rect)
                $pen.Dispose()
            }
            if ($tbKey -is [System.Windows.Forms.Control] -and $tbKey.Focused) {
                $rect = New-Object System.Drawing.Rectangle($tbKey.Location.X - 1, $tbKey.Location.Y - 1, $tbKey.Width + 1, $tbKey.Height + 1)
                $pen = New-Object System.Drawing.Pen($BrandCyan, 2)
                $e.Graphics.DrawRectangle($pen, $rect)
                $pen.Dispose()
            }
        } catch {
            # Silently suppress any drawing exceptions (like legacy array indexing bugs)
        }
    })

    $tbLogSingle.add_GotFocus({ $cfgGroup.Invalidate() })
    $tbLogSingle.add_LostFocus({ $cfgGroup.Invalidate() })
    $tbKeySingle.add_GotFocus({ $cfgGroup.Invalidate() })
    $tbKeySingle.add_LostFocus({ $cfgGroup.Invalidate() })
}

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
                -ProfilesEnabled $script:ProfilesEnabled

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
        $smtcType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
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

function Flash-DiagnosticsStatus {
    param([string]$Message)

    if (-not $script:lblDiagDetail) { return }

    # Kill any previous flash timer
    if ($script:lblDiagDetailFlashTimer) {
        try {
            $script:lblDiagDetailFlashTimer.Stop()
            $script:lblDiagDetailFlashTimer.Dispose()
        }
        catch {}
        $script:lblDiagDetailFlashTimer = $null
    }

    $script:lblDiagDetail.Text = $Message
    $script:lblDiagDetail.ForeColor = $script:BrandCyan
    
    $script:lblDiagDetailFlashTick = 0
    $script:lblDiagDetailFlashTimer = New-Object System.Windows.Forms.Timer
    $script:lblDiagDetailFlashTimer.Interval = 180
    $script:lblDiagDetailFlashTimer.add_Tick({
            $script:lblDiagDetailFlashTick++
            if ($script:lblDiagDetailFlashTick % 2 -eq 0) {
                $script:lblDiagDetail.ForeColor = $script:BrandCyan
            }
            else {
                $script:lblDiagDetail.ForeColor = $script:BrandPurple
            }

            # 6 full cycles (12 color changes total)
            if ($script:lblDiagDetailFlashTick -ge 12) {
                try {
                    if ($script:lblDiagDetailFlashTimer) {
                        $script:lblDiagDetailFlashTimer.Stop()
                        $script:lblDiagDetailFlashTimer.Dispose()
                        $script:lblDiagDetailFlashTimer = $null
                    }
                }
                catch {}

                # Restore the appropriate resting color based on selection
                $restingColor = [System.Drawing.Color]::DimGray
                if ($script:listBlockers -and $script:listBlockers.SelectedIndex -ge 0) {
                    $idx = $script:listBlockers.SelectedIndex
                    if ($script:ActiveBlockersList -and $idx -lt $script:ActiveBlockersList.Count) {
                        $b = $script:ActiveBlockersList[$idx]
                        if ($b -and $b.IsNotBlocking) {
                            $restingColor = $script:BrandPurple
                        }
                    }
                }
                $script:lblDiagDetail.ForeColor = $restingColor
            }
        })
    $script:lblDiagDetailFlashTimer.Start()
}

function Complete-SleepDiagnosticsListsUpdate {
    param([hashtable]$SyncState)

    $script:listBlockers.Items.Clear()
    $script:listOverrides.Items.Clear()
    $script:listAutomated.Items.Clear()

    # Disable buttons until selection is made
    if ($script:btnDiagAutomate) {
        $script:btnDiagAutomate.Enabled = $false
        $script:btnDiagAutomate.Text = "Add to Automated Apps"
    }
    if ($script:btnDiagIgnore) { $script:btnDiagIgnore.Enabled = $false }
    if ($script:btnDiagRestore) { $script:btnDiagRestore.Enabled = $false }
    if ($script:btnDiagStopAuto) { $script:btnDiagStopAuto.Enabled = $false }
    if ($script:btnDiagOpenLocation) { $script:btnDiagOpenLocation.Enabled = $false }
    Set-OperatingModeBoxState -Enabled $false

    # ---- Active Blockers ----
    $script:ActiveBlockersList = @()
    if ($SyncState.Error) {
        $script:lblDiagDetail.Text = "Error scanning blockers: $($SyncState.Error)"
    }
    else {
        if ($SyncState.Blockers) {
            $realBlockers = @()
            $nonBlockers = @()
            foreach ($b in $SyncState.Blockers) {
                if ($b.ProcessName -like "*BEACN*" -or $b.DisplayName -like "*BEACN*") { continue }
                if ($b.IsNotBlocking -eq $true) {
                    $nonBlockers += $b
                }
                else {
                    $realBlockers += $b
                }
            }

            $sortedReal = $realBlockers | Sort-Object DisplayName
            $sortedNon = $nonBlockers | Sort-Object DisplayName

            $finalBlockers = @()
            if ($sortedReal) { $finalBlockers += $sortedReal }
            if ($sortedNon) { $finalBlockers += $sortedNon }

            foreach ($b in $finalBlockers) {
                $script:ActiveBlockersList += $b
                $icon = if ($b.IsNotBlocking -eq $true) {
                    "[App (Not Blocking)]"
                }
                else {
                    switch ($b.BlockerType) {
                        'App' { "[App]" }
                        'Driver' { "[Driver]" }
                        'Service' { "[Service]" }
                        default { "[?]" }
                    }
                }
                $script:listBlockers.Items.Add("$icon $($b.DisplayName)") | Out-Null
            }
        }
    }
    if ($script:listBlockers.Items.Count -eq 0) {
        $script:listBlockers.Items.Add("(No active blockers found - your system can sleep!)") | Out-Null
    }

    # ---- System Overrides ----
    $script:SystemOverridesList = @()
    if ($SyncState.Overrides) {
        foreach ($ov in $SyncState.Overrides) {
            if ($ov.Name -like "*BEACN*") { continue }
            $script:SystemOverridesList += $ov
            $script:listOverrides.Items.Add($ov.DisplayLabel) | Out-Null
        }
    }
    if ($script:listOverrides.Items.Count -eq 0) {
        $script:listOverrides.Items.Add("(No custom overrides configured)") | Out-Null
    }

    # ---- Automated Apps ----
    if ($script:MonitoredApps) {
        foreach ($app in $script:MonitoredApps) {
            $label = Get-AutomatedAppDisplayLabel -app $app
            $script:listAutomated.Items.Add($label) | Out-Null
        }
    }
    if ($script:listAutomated.Items.Count -eq 0) {
        $script:listAutomated.Items.Add("(No apps automated by SAMISH yet)") | Out-Null
    }
}

function Update-SleepDiagnosticsListsAsync {
    $script:listBlockers.Items.Clear()
    $script:listOverrides.Items.Clear()
    $script:listAutomated.Items.Clear()
    $script:listBlockers.Items.Add("(Scanning for active blockers in background...)") | Out-Null
    $script:listOverrides.Items.Add("(Scanning for overrides...)") | Out-Null
    $script:listAutomated.Items.Add("(Scanning automated apps...)") | Out-Null

    $script:lblDiagDetail.Text = "Scanning system blockers in background... Please wait."
    $script:btnDiagScan.Enabled = $false

    $script:DiagSyncState = [hashtable]::Synchronized(@{
            "DiagModulePath"    = $DiagModulePath
            "Blockers"          = $null
            "Overrides"         = $null
            "Error"             = $null
            "Complete"          = $false
            "AutomatedAppNames" = @($script:MonitoredApps | ForEach-Object { $_.ProcessName })
        })

    $script:DiagRunspace = [runspacefactory]::CreateRunspace()
    $script:DiagRunspace.ApartmentState = "STA"
    $script:DiagRunspace.ThreadOptions = "ReuseThread"
    $script:DiagRunspace.Open()
    $script:DiagRunspace.SessionStateProxy.SetVariable("SyncState", $script:DiagSyncState)

    $script:DiagPowerShell = [powershell]::Create()
    $script:DiagPowerShell.Runspace = $script:DiagRunspace

    $script:DiagPowerShell.AddScript({
            try {
                if (Test-Path -LiteralPath $SyncState.DiagModulePath) {
                    . $SyncState.DiagModulePath
                }
                $SyncState.Blockers = Get-ActiveSleepBlockers -AutomatedAppNames $SyncState.AutomatedAppNames
                $SyncState.Overrides = Get-SystemOverrides
            }
            catch {
                $SyncState.Error = $_.Exception.Message
            }
            finally {
                $SyncState.Complete = $true
            }
        }) | Out-Null

    $script:DiagAsyncResult = $script:DiagPowerShell.BeginInvoke()

    $script:DiagTimer = New-Object System.Windows.Forms.Timer
    $script:DiagTimer.Interval = 100
    $script:DiagTimer.add_Tick({
            if ($script:DiagSyncState.Complete) {
                $script:DiagTimer.Stop()
                $script:DiagTimer.Dispose()
                $script:DiagTimer = $null

                try {
                    $null = $script:DiagPowerShell.EndInvoke($script:DiagAsyncResult)
                }
                catch {}
                $script:DiagPowerShell.Dispose()
                $script:DiagRunspace.Close()
                $script:DiagRunspace.Dispose()

                Complete-SleepDiagnosticsListsUpdate -SyncState $script:DiagSyncState
                $script:lblDiagDetail.Text = "Last scan completed at $(Get-Date -Format 'HH:mm:ss')."
                $script:lblDiagDetail.ForeColor = [System.Drawing.Color]::DimGray
                $script:btnDiagScan.Enabled = $true
            }
        })
    $script:DiagTimer.Start()
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
        if (Get-Command Save-ContentAtomic -ErrorAction SilentlyContinue) {
            Save-ContentAtomic -Path $ConfigPath -Content $json
        }
        else {
            Set-Content -LiteralPath $ConfigPath -Value $json -Encoding UTF8
        }
        Write-SetupLog "Saved MonitoredApps config update."
    }
    catch {
        Write-SetupLog "Error saving MonitoredApps: $($_.Exception.Message)"
    }
}

# ---- Helper: enable/disable Operating Mode box children in Sleep Diagnostics ----
# Defined at file scope so event handler scriptblocks can always resolve it.
function Set-OperatingModeBoxState {
    param([bool]$Enabled)

    if (-not $script:grpDiagOperatingMode) { return }

    foreach ($ctrl in $script:grpDiagOperatingMode.Controls) {
        if ($ctrl.Name -eq "pnlOnWakeBorder" -or $ctrl -is [System.Windows.Forms.Panel]) {
            # Handle ComboBox inside Panel
            if ($script:ddDiagOnWakeAction) {
                $script:ddDiagOnWakeAction.Enabled = $Enabled
            }
            if ($global:ThemeNeonActive) {
                $ctrl.Enabled = $true
                $ctrl.BackColor = if ($Enabled) { $global:NeonPurple } else { [System.Drawing.Color]::FromArgb(60, 60, 65) }
            } else {
                $ctrl.Enabled = $Enabled
                $ctrl.BackColor = [System.Drawing.Color]::DarkGray
            }
        }
        elseif ($ctrl -is [System.Windows.Forms.RadioButton] -or $ctrl -is [System.Windows.Forms.Label]) {
            if ($global:ThemeNeonActive) {
                $ctrl.Enabled = $true
                $ctrl.ForeColor = if ($Enabled) { $global:NeonText } else { [System.Drawing.Color]::FromArgb(100, 100, 110) }
                if ($ctrl -is [System.Windows.Forms.RadioButton]) {
                    $ctrl.AutoCheck = $Enabled
                }
            } else {
                $ctrl.Enabled = $Enabled
                if ($ctrl -is [System.Windows.Forms.RadioButton]) {
                    $ctrl.AutoCheck = $true
                    $ctrl.ForeColor = [System.Drawing.SystemColors]::ControlText
                }
                elseif ($ctrl -is [System.Windows.Forms.Label]) {
                    $ctrl.ForeColor = $BrandPurple
                }
            }
        }
        else {
            $ctrl.Enabled = $Enabled
        }
    }

    if ($Enabled) {
        # Kill any previous flash timer before starting a new one (prevents race condition crash)
        if ($script:diagFlashTimer) {
            $script:diagFlashTimer.Stop()
            $script:diagFlashTimer.Dispose()
            $script:diagFlashTimer = $null
        }

        # Determine colors safely
        $color1 = if ($global:ThemeNeonActive) { $global:NeonCyan } else { $script:BrandCyan }
        if ($null -eq $color1) { $color1 = [System.Drawing.Color]::FromArgb(0, 215, 255) }
        $color2 = if ($global:ThemeNeonActive) { $global:NeonPink } else { [System.Drawing.SystemColors]::ControlText }
        if ($null -eq $color2) { $color2 = [System.Drawing.Color]::Black }

        # Triple-flash: Cyan -> ControlText (6 ticks @ 180ms each)
        $script:grpDiagOperatingMode.ForeColor = $color1
        $script:grpDiagOperatingMode.Refresh()
        $script:diagFlashTick = 0
        $script:diagFlashTimer = New-Object System.Windows.Forms.Timer
        $script:diagFlashTimer.Interval = 180
        $script:diagFlashTimer.Tag = [PSCustomObject]@{
            Color1 = $color1
            Color2 = $color2
        }
        $script:diagFlashTimer.add_Tick({
                param($sender, $e)
                $script:diagFlashTick++
                $colors = $sender.Tag
                if ($script:diagFlashTick % 2 -eq 0) {
                    $script:grpDiagOperatingMode.ForeColor = $colors.Color1
                }
                else {
                    $script:grpDiagOperatingMode.ForeColor = $colors.Color2
                }
                if ($script:diagFlashTick -ge 5) {
                    # Ensure we end on final color then clean up
                    $script:grpDiagOperatingMode.ForeColor = $colors.Color2
                    if ($script:diagFlashTimer) {
                        $script:diagFlashTimer.Stop()
                        $script:diagFlashTimer.Dispose()
                        $script:diagFlashTimer = $null
                    }
                }
            })
        $script:diagFlashTimer.Start()
    }
    else {
        # Also kill any running flash timer when disabling
        if ($script:diagFlashTimer) {
            $script:diagFlashTimer.Stop()
            $script:diagFlashTimer.Dispose()
            $script:diagFlashTimer = $null
        }
        $script:grpDiagOperatingMode.ForeColor = if ($global:ThemeNeonActive) { $global:NeonPink } else { [System.Drawing.Color]::Gray }
    }
}

function Populate-OnWakeActionDropdown {
    param(
        [string]$beforeSleepMode,
        [string]$selectedValue
    )

    if (-not $script:ddDiagOnWakeAction) { return }

    $script:ddDiagOnWakeAction.Items.Clear()

    if ($beforeSleepMode -eq "PauseMedia") {
        $script:ddDiagOnWakeAction.Items.Add("Smart Restore (Restore previous state)") | Out-Null
        $script:ddDiagOnWakeAction.Items.Add("Always Play") | Out-Null
        $script:ddDiagOnWakeAction.Items.Add("Always Pause") | Out-Null

        if ($script:diagTip) {
            $script:diagTip.SetToolTip($script:ddDiagOnWakeAction, "Configure media playback on wake: Smart Restore plays if it was playing before sleep; Always Play forces playback; Always Pause leaves media paused.")
        }
    }
    else {
        $script:ddDiagOnWakeAction.Items.Add("Smart Restore (Restore previous state)") | Out-Null
        $script:ddDiagOnWakeAction.Items.Add("Reopen Only (Do Not Play)") | Out-Null
        $script:ddDiagOnWakeAction.Items.Add("Always Play") | Out-Null
        $script:ddDiagOnWakeAction.Items.Add("Keep Closed") | Out-Null

        if ($script:diagTip) {
            $script:diagTip.SetToolTip($script:ddDiagOnWakeAction, "Configure application recovery on wake: Smart Restore restarts the app and resumes playback if it was playing; Always Play restarts and plays; Keep Closed leaves it closed; Reopen Only restarts the app but leaves media paused.")
        }
    }

    $index = 0
    if ($beforeSleepMode -eq "PauseMedia") {
        $index = switch ($selectedValue) {
            "Smart" { 0 }
            "Play" { 1 }
            "Pause" { 2 }
            default { 0 }
        }
    }
    else {
        $index = switch ($selectedValue) {
            "Smart" { 0 }
            "ReopenNoPlay" { 1 }
            "Play" { 2 }
            "KeepClosed" { 3 }
            default { 0 }
        }
    }

    if ($script:ddDiagOnWakeAction.Items.Count -gt $index) {
        $script:ddDiagOnWakeAction.SelectedIndex = $index
    }
}

function Get-OnWakeActionFromDropdown {
    param([string]$beforeSleepMode)

    if (-not $script:ddDiagOnWakeAction -or $script:ddDiagOnWakeAction.SelectedIndex -lt 0) {
        return "Smart"
    }

    $idx = $script:ddDiagOnWakeAction.SelectedIndex
    if ($beforeSleepMode -eq "PauseMedia") {
        $result = switch ($idx) {
            0 { "Smart" }
            1 { "Play" }
            2 { "Pause" }
            default { "Smart" }
        }
        return $result
    }
    else {
        $result = switch ($idx) {
            0 { "Smart" }
            1 { "ReopenNoPlay" }
            2 { "Play" }
            3 { "KeepClosed" }
            default { "Smart" }
        }
        return $result
    }
}

# ---- Main init (called from Show-SleepDiagnosticsDialog) ----

function Init-SleepDiagnosticsEventHandlers {

    # Populate lists on first open
    Update-SleepDiagnosticsListsAsync

    # ---------- DrawItem event for Page 2 ListBoxes (OwnerDrawFixed) ----------
    $lbDrawItem = {
        param($sender, $e)
        if ($e.Index -lt 0 -or $e.Index -ge $sender.Items.Count) { return }

        $itemText = $sender.Items[$e.Index].ToString()
        $isHighlighted = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -eq [System.Windows.Forms.DrawItemState]::Selected

        # Background color selection
        if ($isHighlighted) {
            $brushBack = New-Object System.Drawing.SolidBrush($BrandCyan) # SAMISH Cyan/Blue
            $e.Graphics.FillRectangle($brushBack, $e.Bounds)
            $brushBack.Dispose()
        }
        else {
            $brushBack = New-Object System.Drawing.SolidBrush($sender.BackColor)
            $e.Graphics.FillRectangle($brushBack, $e.Bounds)
            $brushBack.Dispose()
        }

        # Foreground color selection
        $foreColor = $sender.ForeColor
        if ($isHighlighted) {
            $foreColor = [System.Drawing.Color]::Black # Black text on Cyan highlight
        }
        else {
            # Active blockers non-blocker styling
            if ($sender -eq $script:listBlockers) {
                if ($script:ActiveBlockersList -and $e.Index -lt $script:ActiveBlockersList.Count) {
                    $b = $script:ActiveBlockersList[$e.Index]
                    if ($b -and $b.IsNotBlocking) {
                        $foreColor = $BrandPurple
                    }
                }
            }
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

    if ($script:listBlockers) { $script:listBlockers.add_DrawItem($lbDrawItem) }
    if ($script:listOverrides) { $script:listOverrides.add_DrawItem($lbDrawItem) }
    if ($script:listAutomated) { $script:listAutomated.add_DrawItem($lbDrawItem) }
    if ($script:listArmedDevices) { $script:listArmedDevices.add_DrawItem($lbDrawItem) }

    # Guard flag: prevents the two list selection handlers from triggering each other
    $script:diagListMutex = $false

    # ---------- Scan Blockers ----------
    $script:btnDiagScan.add_Click({
            Update-SleepDiagnosticsListsAsync
        })

    # ---------- Active Blockers selection ----------
    $script:listBlockers.add_SelectedIndexChanged({
            if ($script:diagListMutex) { return }
            $script:diagListMutex = $true
            $script:listAutomated.ClearSelected()
            $script:listOverrides.ClearSelected()
            $script:diagListMutex = $false

            $idx = $script:listBlockers.SelectedIndex
            $hasValidItem = ($idx -ge 0 -and $idx -lt $script:ActiveBlockersList.Count)

            $script:btnDiagAutomate.Enabled = $false
            $script:btnDiagAutomate.Text = "Add to Automated Apps"
            $script:btnDiagIgnore.Enabled = $false

            if (-not $hasValidItem) {
                $script:lblDiagDetail.Text = "Select an active blocker to see details."
                $script:lblDiagDetail.ForeColor = [System.Drawing.Color]::DimGray
                Set-OperatingModeBoxState -Enabled $false
                return
            }

            $b = $script:ActiveBlockersList[$idx]
            $script:lblDiagDetail.Text = "[$($b.BlockerType)]  $($b.DisplayName)`r`nSection: $($b.Section)    Reason: $($b.Reason)"

            if ($b.IsNotBlocking -eq $true) {
                $script:lblDiagDetail.ForeColor = $script:BrandPurple
            }
            else {
                $script:lblDiagDetail.ForeColor = [System.Drawing.Color]::DimGray
            }

            # Enable buttons based on type - mutually exclusive
            if ($b.BlockerType -eq 'App') {
                $script:btnDiagIgnore.Enabled = $false

                # Check if already automated
                $alreadyAutomated = $false
                if ($script:MonitoredApps) {
                    $alreadyAutomated = [bool]($script:MonitoredApps | Where-Object { $_.ProcessName -eq $b.ProcessName })
                }

                if ($alreadyAutomated) {
                    $script:btnDiagAutomate.Enabled = $false
                    $script:btnDiagAutomate.Text = "Already Automated"
                    # Still enable the Operating Mode box so they can view/edit the config
                    # Find the automated app's config to sync
                    $app = $script:MonitoredApps | Where-Object { $_.ProcessName -eq $b.ProcessName } | Select-Object -First 1
                    $mode = if ($app.RecoveryMode) { $app.RecoveryMode } else { $script:OperatingMode }
                    $onWake = if ($app.PSObject.Properties['OnWakeAction']) { $app.OnWakeAction } else { "Smart" }
                    Set-OperatingModeBoxState -Enabled $true
                    $script:diagSyncingControls = $true
                    try {
                        if ($mode -eq "Classic") {
                            if ($script:rbDiagClassic) { $script:rbDiagClassic.Checked = $true }
                        }
                        elseif ($mode -eq "PauseMedia") {
                            if ($script:rbDiagPauseMedia) { $script:rbDiagPauseMedia.Checked = $true }
                        }
                        else {
                            if ($script:rbDiagGraceful) { $script:rbDiagGraceful.Checked = $true }
                        }
                        Populate-OnWakeActionDropdown -beforeSleepMode $mode -selectedValue $onWake
                    }
                    finally {
                        $script:diagSyncingControls = $false
                    }
                }
                else {
                    $script:btnDiagAutomate.Enabled = $true
                    $script:btnDiagAutomate.Text = "Add to Automated Apps"
                    # Light up the Operating Mode box and reset to safe defaults
                    Set-OperatingModeBoxState -Enabled $true
                    $script:diagSyncingControls = $true
                    try {
                        if ($script:rbDiagGraceful) { $script:rbDiagGraceful.Checked = $true }
                        Populate-OnWakeActionDropdown -beforeSleepMode "Graceful" -selectedValue "Smart"
                    }
                    finally {
                        $script:diagSyncingControls = $false
                    }
                }
            }
            else {
                $script:btnDiagAutomate.Enabled = $false
                $script:btnDiagAutomate.Text = "Add to Automated Apps"
                $script:btnDiagIgnore.Enabled = $true
                # Non-app blockers can't be automated; grey the box back out
                Set-OperatingModeBoxState -Enabled $false
            }
        })

    # ---------- System Overrides selection ----------
    $script:listOverrides.add_SelectedIndexChanged({
            if ($script:diagListMutex) { return }
            $script:diagListMutex = $true
            $script:listBlockers.ClearSelected()
            $script:listAutomated.ClearSelected()
            $script:diagListMutex = $false

            $idx = $script:listOverrides.SelectedIndex
            $hasValidItem = ($idx -ge 0 -and $idx -lt $script:SystemOverridesList.Count)
            $script:btnDiagRestore.Enabled = $hasValidItem
            if ($hasValidItem) {
                $ov = $script:SystemOverridesList[$idx]
                $script:lblDiagDetail.Text = "Ignored: [$($ov.OverrideType)]  $($ov.Name)    Requests overridden: $($ov.Requests)"
                $script:lblDiagDetail.ForeColor = [System.Drawing.Color]::DimGray
            }
        })

    # ---------- Automated Apps selection ----------
    $script:listAutomated.add_SelectedIndexChanged({
            if ($script:diagListMutex) { return }
            $script:diagListMutex = $true
            $script:listBlockers.ClearSelected()
            $script:listOverrides.ClearSelected()
            $script:diagListMutex = $false

            $idx = $script:listAutomated.SelectedIndex
            $hasValidItem = ($idx -ge 0 -and $idx -lt $script:MonitoredApps.Count)
            $script:btnDiagStopAuto.Enabled = $hasValidItem
            $script:btnDiagOpenLocation.Enabled = $hasValidItem
            if ($hasValidItem) {
                $app = $script:MonitoredApps[$idx]
                $mode = if ($app.RecoveryMode) { $app.RecoveryMode } else { $script:OperatingMode }
                $onWake = if ($app.PSObject.Properties['OnWakeAction']) { $app.OnWakeAction } else { "Smart" }
                $displayMode = if ($mode -eq "PauseMedia") { "Keep App Open" } else { $mode }
 
                $script:lblDiagDetail.Text = "Automated: $($app.ProcessName)    Mode: $displayMode`r`nPath: $($app.ExecutablePath)"
                $script:lblDiagDetail.ForeColor = [System.Drawing.Color]::DimGray

                # Light up the Operating Mode box and sync its controls to this app's saved values
                Set-OperatingModeBoxState -Enabled $true
                $script:diagSyncingControls = $true
                try {
                    if ($mode -eq "Classic") {
                        if ($script:rbDiagClassic) { $script:rbDiagClassic.Checked = $true }
                    }
                    elseif ($mode -eq "PauseMedia") {
                        if ($script:rbDiagPauseMedia) { $script:rbDiagPauseMedia.Checked = $true }
                    }
                    else {
                        if ($script:rbDiagGraceful) { $script:rbDiagGraceful.Checked = $true }
                    }

                    Populate-OnWakeActionDropdown -beforeSleepMode $mode -selectedValue $onWake
                }
                finally {
                    $script:diagSyncingControls = $false
                }
            }
            else {
                # Nothing selected - grey the box back out
                Set-OperatingModeBoxState -Enabled $false
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

            $script:btnDiagAutomate.Enabled = $false
            $script:lblDiagDetail.Text = "Searching for executable path for $($b.ProcessName) in background... Please wait."

            $script:PathSyncState = [hashtable]::Synchronized(@{
                    "DiagModulePath" = $DiagModulePath
                    "ProcessName"    = $b.ProcessName
                    "ExecutableName" = $b.ExecutableName
                    "Path"           = $null
                    "Complete"       = $false
                })

            $script:PathRunspace = [runspacefactory]::CreateRunspace()
            $script:PathRunspace.ApartmentState = "STA"
            $script:PathRunspace.ThreadOptions = "ReuseThread"
            $script:PathRunspace.Open()
            $script:PathRunspace.SessionStateProxy.SetVariable("SyncState", $script:PathSyncState)

            $script:PathPowerShell = [powershell]::Create()
            $script:PathPowerShell.Runspace = $script:PathRunspace

            $script:PathPowerShell.AddScript({
                    try {
                        if (Test-Path -LiteralPath $SyncState.DiagModulePath) {
                            . $SyncState.DiagModulePath
                        }
                        $SyncState.Path = Resolve-ProcessExecutablePath -ProcessName $SyncState.ProcessName -ExecutableName $SyncState.ExecutableName
                    }
                    catch {}
                    finally {
                        $SyncState.Complete = $true
                    }
                }) | Out-Null

            $script:PathAsyncResult = $script:PathPowerShell.BeginInvoke()

            $script:PathTimer = New-Object System.Windows.Forms.Timer
            $script:PathTimer.Interval = 100
            $script:PathTimer.add_Tick({
                    if ($script:PathSyncState.Complete) {
                        $script:PathTimer.Stop()
                        $script:PathTimer.Dispose()
                        $script:PathTimer = $null

                        try {
                            $null = $script:PathPowerShell.EndInvoke($script:PathAsyncResult)
                        }
                        catch {}
                        $script:PathPowerShell.Dispose()
                        $script:PathRunspace.Close()
                        $script:PathRunspace.Dispose()

                        $script:btnDiagAutomate.Enabled = $true

                        $path = $script:PathSyncState.Path
                        $procName = $script:PathSyncState.ProcessName
                        $execName = $script:PathSyncState.ExecutableName

                        if (-not $path) {
                            $script:lblDiagDetail.Text = "Automatic search failed. Please manually locate the executable for $procName."
                        
                            Add-Type -AssemblyName System.Windows.Forms
                            $dialog = New-Object System.Windows.Forms.OpenFileDialog
                            $dialog.Title = "Locate the executable for: $procName"
                            $dialog.Filter = "Executable Files (*.exe)|*.exe"
                            $dialog.FileName = $execName
                            $dialog.InitialDirectory = $env:ProgramFiles

                            if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                                if (Test-Path -LiteralPath $dialog.FileName) {
                                    $path = $dialog.FileName
                                }
                            }
                        }

                        if (-not $path) {
                            $script:lblDiagDetail.Text = "Automation cancelled: Executable path not found."
                            return
                        }

                        $chosenMode = "Graceful"
                        if ($script:rbDiagClassic -and $script:rbDiagClassic.Checked) {
                            $chosenMode = "Classic"
                        }
                        elseif ($script:rbDiagPauseMedia -and $script:rbDiagPauseMedia.Checked) {
                            $chosenMode = "PauseMedia"
                        }

                        $onWake = Get-OnWakeActionFromDropdown -beforeSleepMode $chosenMode

                        $modeDetail = if ($chosenMode -eq "Classic") {
                            "Before Sleep: Close App (Classic) (immediately terminates the app. More reliable, but any unsaved work will be lost)."
                        }
                        elseif ($chosenMode -eq "PauseMedia") {
                            "Before Sleep: Pause Media Only (pauses media playback via WinRT SMTC instead of closing the app)."
                        }
                        else {
                            "Before Sleep: Close App (Graceful) (asks the app to close cleanly. Safer for unsaved work, but may occasionally fail if unresponsive)."
                        }

                        $wakeDetail = switch ($onWake) {
                            "Play" { "On Wake: Always Play (forces media playback to start)." }
                            "Pause" { "On Wake: Always Pause (keeps media playback paused)." }
                            "KeepClosed" { "On Wake: Keep Closed (does not reopen the app on wake)." }
                            "ReopenNoPlay" { "On Wake: Reopen Only (reopens the app on wake but keeps media paused)." }
                            default { "On Wake: Smart Restore (restores previous state before sleep)." }
                        }

                        $msg = "SAMISH will automatically manage $procName when your computer transitions to sleep and wake.`r`n`r`n$modeDetail`r`n`r`n$wakeDetail`r`n`r`nConfigure automated management for $procName with these settings?"

                        $choice = [System.Windows.Forms.MessageBox]::Show(
                            $msg,
                            "SAMISH - Confirm Automation",
                            [System.Windows.Forms.MessageBoxButtons]::YesNo,
                            [System.Windows.Forms.MessageBoxIcon]::Question
                        )

                        if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) {
                            $newApp = [ordered]@{
                                ProcessName    = $procName
                                ExecutablePath = $path
                                RecoveryMode   = $chosenMode
                                OnWakeAction   = $onWake
                            }
                            $script:MonitoredApps += [pscustomobject]$newApp
                            Save-MonitoredAppsToConfig
                            if (Get-Command Update-TestGroupState -ErrorAction SilentlyContinue) {
                                try { Update-TestGroupState } catch {}
                            }
                            Update-SleepDiagnosticsListsAsync
                            $script:lblDiagDetail.Text = "$procName added to SAMISH automation ($chosenMode mode, On Wake Action: $onWake)."
                        }
                        else {
                            $script:lblDiagDetail.Text = "Automation configuration cancelled."
                        }
                    }
                })
            $script:PathTimer.Start()
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
                    Update-SleepDiagnosticsListsAsync
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
                if (Get-Command Update-TestGroupState -ErrorAction SilentlyContinue) {
                    try { Update-TestGroupState } catch {}
                }
                Update-SleepDiagnosticsListsAsync
                $script:lblDiagDetail.Text = "$($app.ProcessName) removed from SAMISH automation."

                # No app is selected after removal -- grey the Operating Mode box and reset to safe defaults
                Set-OperatingModeBoxState -Enabled $false
                if ($script:rbDiagGraceful) { $script:rbDiagGraceful.Checked = $true }
                if ($script:ddDiagOnWakeAction) { 
                    $script:ddDiagOnWakeAction.Items.Clear()
                    $script:ddDiagOnWakeAction.Items.Add("- Select App -") | Out-Null
                    $script:ddDiagOnWakeAction.SelectedIndex = 0
                }
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
                    Update-SleepDiagnosticsListsAsync
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

    # ---------- Live-save Operating Mode options (for already-automated apps) ----------
    $saveRecoveryMode = {
        if ($script:diagSyncingControls) { return }

        $idx = $script:listAutomated.SelectedIndex
        if ($idx -lt 0 -or $idx -ge $script:MonitoredApps.Count) { return }

        $chosenMode = "Graceful"
        if ($script:rbDiagClassic -and $script:rbDiagClassic.Checked) {
            $chosenMode = "Classic"
        }
        elseif ($script:rbDiagPauseMedia -and $script:rbDiagPauseMedia.Checked) {
            $chosenMode = "PauseMedia"
        }

        $app = $script:MonitoredApps[$idx]
        if ($app.RecoveryMode -eq $chosenMode) { return }

        # Sync the dropdown options based on new RecoveryMode selection
        $onWake = if ($app.PSObject.Properties['OnWakeAction']) { $app.OnWakeAction } else { "Smart" }
        $script:diagSyncingControls = $true
        try {
            Populate-OnWakeActionDropdown -beforeSleepMode $chosenMode -selectedValue $onWake
        }
        finally {
            $script:diagSyncingControls = $false
        }

        $newOnWake = Get-OnWakeActionFromDropdown -beforeSleepMode $chosenMode

        $app.RecoveryMode = $chosenMode
        $app.OnWakeAction = $newOnWake
        $script:MonitoredApps[$idx] = $app
        Save-MonitoredAppsToConfig
        Update-AutomatedAppsListDisplay

        $displayChosen = if ($chosenMode -eq "PauseMedia") { "Keep App Open" } else { $chosenMode }
        $displayOnWake = switch ($newOnWake) {
            "Smart" { "Smart Restore" }
            "Play" { "Always Play" }
            "Pause" { "Always Pause" }
            "KeepClosed" { "Keep Closed" }
            "ReopenOnly" { "Reopen Only" }
            default { $newOnWake }
        }
        Flash-DiagnosticsStatus "Saved: $($app.ProcessName) set to $displayChosen ($displayOnWake on wake)."
    }

    if ($script:rbDiagGraceful) { $script:rbDiagGraceful.add_CheckedChanged($saveRecoveryMode) }
    if ($script:rbDiagClassic) { $script:rbDiagClassic.add_CheckedChanged($saveRecoveryMode) }
    if ($script:rbDiagPauseMedia) { $script:rbDiagPauseMedia.add_CheckedChanged($saveRecoveryMode) }

    # ---------- Live-save On Wake Action dropdown ----------
    if ($script:ddDiagOnWakeAction) {
        $script:ddDiagOnWakeAction.add_SelectedIndexChanged({
                if ($script:diagSyncingControls) { return }

                $idx = $script:listAutomated.SelectedIndex
                if ($idx -lt 0 -or $idx -ge $script:MonitoredApps.Count) { return }

                $app = $script:MonitoredApps[$idx]
                $chosenMode = if ($app.RecoveryMode) { $app.RecoveryMode } else { "Graceful" }
                $newOnWake = Get-OnWakeActionFromDropdown -beforeSleepMode $chosenMode

                if ($app.OnWakeAction -eq $newOnWake) { return }

                $app.OnWakeAction = $newOnWake
                $script:MonitoredApps[$idx] = $app
                Save-MonitoredAppsToConfig
                Update-AutomatedAppsListDisplay
 
                $displayChosen = if ($chosenMode -eq "PauseMedia") { "Keep App Open" } else { $chosenMode }
                $displayOnWake = switch ($newOnWake) {
                    "Smart" { "Smart Restore" }
                    "Play" { "Always Play" }
                    "Pause" { "Always Pause" }
                    "KeepClosed" { "Keep Closed" }
                    "ReopenOnly" { "Reopen Only" }
                    default { $newOnWake }
                }
                Flash-DiagnosticsStatus "Saved: $($app.ProcessName) set to $displayChosen ($displayOnWake on wake)."
            })
    }
}

# Operating Mode Tests -- Event Wiring
# ============================================================

# ---- Resolve-TestTarget -------------------------------------
# Reads the selected item from the test target dropdown and returns a
# structured object with everything the three button handlers need.
# Callers must check .Valid before using any other field.
function Resolve-TestTarget {
    try {
        if (-not $script:ddTestTarget -or $script:ddTestTarget.SelectedIndex -lt 0) {
            return [pscustomobject]@{
                Valid             = $false
                Error             = "No target selected in the dropdown."
                IsDeviceSoftware  = $false
                ProcessName       = ""
                ConfiguredPath    = ""
                DisplayName       = ""
                WindowWakeDelayMs = 800
                ShutdownWaitMs    = 800
            }
        }

        $selected = [string]$script:ddTestTarget.SelectedItem

        # ---- Device Software target ----
        if ($selected -like "Device Software:*") {

            $procName = ""
            $configPath = ""
            $regSearch = ""
            $displayName = $selected
            $gracefulWake = 800
            $gracefulWait = 800

            try {
                if ($script:ProfileMetaById -and
                    $script:ProfileMetaById.ContainsKey($script:ActiveProfileId)) {
                    $meta = $script:ProfileMetaById[$script:ActiveProfileId]

                    $displayName = $meta.DisplayName

                    if ($meta.Raw.targets -and $meta.Raw.targets.Count -gt 0) {
                        $t = $meta.Raw.targets[0]
                        $procName = [string]$t.processName
                        $configPath = if ($t.PSObject.Properties["defaultExePath"]) { [string]$t.defaultExePath } else { "" }
                        $regSearch = if ($t.PSObject.Properties["registrySearchString"]) { [string]$t.registrySearchString } else { $procName }
                    }

                    # Pull timing defaults from the profile if present
                    if ($meta.Raw.PSObject.Properties["gracefulWindowWakeDelayMs"]) {
                        try { $gracefulWake = [int]$meta.Raw.gracefulWindowWakeDelayMs } catch {}
                    }
                    if ($meta.Raw.PSObject.Properties["gracefulShutdownWaitMs"]) {
                        try { $gracefulWait = [int]$meta.Raw.gracefulShutdownWaitMs } catch {}
                    }
                }
            }
            catch {
                # Profile metadata read failed - fall back to empty strings; the
                # caller will surface a useful error via Get-AppExecutablePath.
                Write-SetupLog "Resolve-TestTarget: profile metadata read error: $($_.Exception.Message)"
            }

            if (-not $procName) {
                return [pscustomobject]@{
                    Valid             = $false
                    Error             = "Could not resolve a process name from the selected profile."
                    IsDeviceSoftware  = $true
                    ProcessName       = ""
                    ConfiguredPath    = ""
                    DisplayName       = $displayName
                    WindowWakeDelayMs = $gracefulWake
                    ShutdownWaitMs    = $gracefulWait
                }
            }

            # Resolve the best available executable path (Config > Running process > Registry)
            $pathResult = $null
            if (Get-Command Get-AppExecutablePath -ErrorAction SilentlyContinue) {
                try {
                    $pathResult = Get-AppExecutablePath `
                        -ProcessName $procName `
                        -ConfiguredPath $configPath `
                        -RegistrySearchString $regSearch
                }
                catch {
                    Write-SetupLog "Resolve-TestTarget: Get-AppExecutablePath threw: $($_.Exception.Message)"
                }
            }

            $resolvedPath = if ($pathResult -and $pathResult.IsValid) { $pathResult.Path } else { $configPath }

            return [pscustomobject]@{
                Valid             = $true
                Error             = ""
                IsDeviceSoftware  = $true
                ProcessName       = $procName
                ConfiguredPath    = $resolvedPath
                DisplayName       = $displayName
                WindowWakeDelayMs = $gracefulWake
                ShutdownWaitMs    = $gracefulWait
                BeforeSleepMode   = $script:OperatingMode
                OnWakeAction      = "Smart"
            }
        }

        # ---- Automated App target ----
        if ($selected -like "Automated App:*") {

            $targetProcName = $selected.Replace("Automated App:", "").Trim()

            $app = $null
            if ($script:MonitoredApps) {
                $app = $script:MonitoredApps | Where-Object { $_.ProcessName -eq $targetProcName } | Select-Object -First 1
            }

            if (-not $app) {
                return [pscustomobject]@{
                    Valid             = $false
                    Error             = "Automated app '$targetProcName' not found in the current MonitoredApps list. Try reopening the test group."
                    IsDeviceSoftware  = $false
                    ProcessName       = $targetProcName
                    ConfiguredPath    = ""
                    DisplayName       = $targetProcName
                    WindowWakeDelayMs = 800
                    ShutdownWaitMs    = 800
                }
            }

            $exePath = if ($app.PSObject.Properties["ExecutablePath"]) { [string]$app.ExecutablePath } else { "" }

            # Resolve path using Get-AppExecutablePath helper
            $resolvedPath = $exePath
            if (Get-Command Get-AppExecutablePath -ErrorAction SilentlyContinue) {
                try {
                    $pathResult = Get-AppExecutablePath -ProcessName $app.ProcessName -ConfiguredPath $exePath
                    if ($pathResult -and $pathResult.IsValid) {
                        $resolvedPath = $pathResult.Path
                    }
                }
                catch {
                    Write-SetupLog "Resolve-TestTarget: Get-AppExecutablePath threw for Automated App: $($_.Exception.Message)"
                }
            }

            $beforeSleepMode = if ($app.RecoveryMode) { $app.RecoveryMode } else { $script:OperatingMode }
            $onWakeAction = if ($app.PSObject.Properties['OnWakeAction']) { $app.OnWakeAction } else { "Smart" }

            return [pscustomobject]@{
                Valid             = $true
                Error             = ""
                IsDeviceSoftware  = $false
                ProcessName       = $app.ProcessName
                ConfiguredPath    = $resolvedPath
                DisplayName       = $app.ProcessName
                WindowWakeDelayMs = 800
                ShutdownWaitMs    = 800
                BeforeSleepMode   = $beforeSleepMode
                OnWakeAction      = $onWakeAction
            }
        }

        # Fallback: the item did not match either known prefix
        return [pscustomobject]@{
            Valid             = $false
            Error             = "Unrecognised target format: '$selected'."
            IsDeviceSoftware  = $false
            ProcessName       = ""
            ConfiguredPath    = ""
            DisplayName       = $selected
            WindowWakeDelayMs = 800
            ShutdownWaitMs    = 800
        }
    }
    catch {
        Write-SetupLog "Resolve-TestTarget: unexpected error: $($_.Exception.Message)"
        return [pscustomobject]@{
            Valid             = $false
            Error             = "Unexpected error resolving target: $($_.Exception.Message)"
            IsDeviceSoftware  = $false
            ProcessName       = ""
            ConfiguredPath    = ""
            DisplayName       = ""
            WindowWakeDelayMs = 800
            ShutdownWaitMs    = 800
        }
    }
}

# ---- Update-TestButtonsTooltips --------------------------------------
# Evaluates SAMISH installation, active profile, and process running states
# to update the tooltips for the four diagnostic test buttons on Page 2.
function Update-TestButtonsTooltips {
    # Check general group availability
    $isInstalled = $false
    $deviceRunning = $false
    $hasAutomated = ($script:MonitoredApps -and $script:MonitoredApps.Count -gt 0)
    try { $isInstalled = Test-SamishInstalled } catch {}

    $profileProcName = $null
    try {
        if ($script:ProfileMetaById -and $script:ProfileMetaById.ContainsKey($script:ActiveProfileId)) {
            $meta = $script:ProfileMetaById[$script:ActiveProfileId]
            if ($meta.Raw.targets -and $meta.Raw.targets.Count -gt 0) {
                $profileProcName = [string]$meta.Raw.targets[0].processName
            }
        }
    } catch {}
    if ($profileProcName) {
        try {
            $deviceRunning = ($null -ne (Get-Process -Name $profileProcName -ErrorAction SilentlyContinue | Select-Object -First 1))
        } catch {}
    }

    $groupAvailable = ($isInstalled -or $hasAutomated -or $deviceRunning)

    # Base tooltips
    $baseSleep = "Test whether SAMISH can close this application or pause its media playback based on its configured sleep action."
    $baseWake = "Test whether SAMISH can launch this application and/or restore its media playback status based on its configured wake action."
    $baseGraceful = "Test close app (graceful) behavior, forcing a WM_CLOSE command to ask the application to close cleanly."
    $baseForce = "Test close app (classic) behavior, forcing immediate process termination."

    if (-not $groupAvailable) {
        $reason = "[Unavailable - Requires SAMISH to be installed, the active profile's device software to be running, or automated apps configured.]"
        $tipSleep = "$reason`r`n`r`n$baseSleep"
        $tipWake = "$reason`r`n`r`n$baseWake"
        $tipGraceful = "$reason`r`n`r`n$baseGraceful"
        $tipForce = "$reason`r`n`r`n$baseForce"
    }
    else {
        $target = Resolve-TestTarget
        if (-not $target.Valid) {
            $reason = "[Unavailable - No valid target selected in dropdown]"
            $tipSleep = "$reason`r`n`r`n$baseSleep"
            $tipWake = "$reason`r`n`r`n$baseWake"
            $tipGraceful = "$reason`r`n`r`n$baseGraceful"
            $tipForce = "$reason`r`n`r`n$baseForce"
        }
        else {
            $proc = Get-Process -Name $target.ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
            $running = $null -ne $proc

            if ($running) {
                $statusSleep = "[Available - Target is running]"
                $statusGraceful = "[Available - Target is running]"
                $statusForce = "[Available - Target is running]"

                if ($target.BeforeSleepMode -eq "PauseMedia") {
                    $statusWake = "[Available - Target is running (testing playback resumption)]"
                    $guidanceWake = "This will test media playback resumption on the running application."
                }
                else {
                    $statusWake = "[Unavailable - Target is running. Click 'Test Sleep/Hibernate' first.]"
                    $guidanceWake = "The application must be stopped before testing the launch action."
                }

                $guidanceSleep = "Warning: This test will attempt to close or pause the running application."
                $guidanceGraceful = "Warning: This test will attempt to gracefully close the running application."
                $guidanceForce = "Warning: This test will force-terminate the running application."

                $tipSleep = "$statusSleep`r`n`r`n$baseSleep`r`n`r`n$guidanceSleep"
                $tipWake = "$statusWake`r`n`r`n$baseWake`r`n`r`n$guidanceWake"
                $tipGraceful = "$statusGraceful`r`n`r`n$baseGraceful`r`n`r`n$guidanceGraceful"
                $tipForce = "$statusForce`r`n`r`n$baseForce`r`n`r`n$guidanceForce"
            }
            else {
                $statusSleep = "[Unavailable - Target is not running. Click 'Test Wake/Resume' first.]"
                $statusGraceful = "[Unavailable - Target is not running. Click 'Test Wake/Resume' first.]"
                $statusForce = "[Unavailable - Target is not running. Click 'Test Wake/Resume' first.]"
                
                $statusWake = "[Available - Target is not running]"

                $guidanceSleep = "The application must be running to test sleep actions."
                $guidanceGraceful = "The application must be running to test graceful close."
                $guidanceForce = "The application must be running to test force close."
                
                $pathText = if ($target.ConfiguredPath) { $target.ConfiguredPath } else { "(Auto-detect on launch)" }
                $guidanceWake = "This will attempt to launch the application using its configured path: $pathText"

                $tipSleep = "$statusSleep`r`n`r`n$baseSleep`r`n`r`n$guidanceSleep"
                $tipWake = "$statusWake`r`n`r`n$baseWake`r`n`r`n$guidanceWake"
                $tipGraceful = "$statusGraceful`r`n`r`n$baseGraceful`r`n`r`n$guidanceGraceful"
                $tipForce = "$statusForce`r`n`r`n$baseForce`r`n`r`n$guidanceForce"
            }
        }
    }

    # Set tooltips dynamically
    if ($script:btnTestStop) { $script:tooltip.SetToolTip($script:btnTestStop, $tipSleep) }
    if ($script:btnTestStart) { $script:tooltip.SetToolTip($script:btnTestStart, $tipWake) }
    if ($script:btnTestGraceful) { $script:tooltip.SetToolTip($script:btnTestGraceful, $tipGraceful) }
    if ($script:btnTestClassic) { $script:tooltip.SetToolTip($script:btnTestClassic, $tipForce) }
}

# ---- Test Graceful Stop -------------------------------------
$script:btnTestGraceful.add_Click({
        try {
            $target = Resolve-TestTarget

            if (-not $target.Valid) {
                $msg = "Cannot run test: $($target.Error)"
                Set-StatusText $msg
                Write-SetupLog "Operating Mode Test (Graceful): $msg"
                return
            }

            # Check whether the app is currently running before calling Graceful stop.
            $proc = Get-Process -Name $target.ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $proc) {
                $msg = "$($target.DisplayName) is not currently running. Nothing to stop."
                Set-StatusText $msg
                Write-SetupLog "Operating Mode Test (Graceful): $msg"
                return
            }

            Set-StatusText "Running Graceful Stop test on $($target.DisplayName)..."
            Write-SetupLog "Operating Mode Test (Graceful): starting test on $($target.DisplayName) (process: $($target.ProcessName))"

            if (-not (Get-Command Invoke-AppStopGraceful -ErrorAction SilentlyContinue)) {
                $msg = "Invoke-AppStopGraceful is not available in this session. The Graceful module may not have loaded."
                Set-StatusText $msg
                Write-SetupLog "Operating Mode Test (Graceful): $msg"
                return
            }

            $r = Invoke-AppStopGraceful `
                -ProcessName       $target.ProcessName `
                -ConfiguredPath    $target.ConfiguredPath `
                -WindowWakeDelayMs $target.WindowWakeDelayMs `
                -ShutdownWaitMs    $target.ShutdownWaitMs

            # Build a human-readable result line.
            $method = if ($r -and $r.Method) { [string]$r.Method } else { "Unknown" }
            $stopped = ($r -and $r.Stopped -eq $true)
            $errTxt = if ($r -and $r.Error) { [string]$r.Error } else { "" }

            if ($stopped) {
                $msg = "Graceful Stop test PASSED for $($target.DisplayName). Method: $method."
            }
            else {
                $msg = "Graceful Stop test did not confirm a clean stop for $($target.DisplayName). Method: $method."
                if ($errTxt) { $msg += " $errTxt" }
            }

            # Informational note when the SAMISH engine is installed (no blocking).
            if (Test-SamishInstalled) {
                $msg += "`r`n`r`nNote: SAMISH engine is installed and running. Tests are safe during active use. The engine only triggers when your system has been idle for an extended period."
            }

            Set-StatusText $msg
            Write-SetupLog "Operating Mode Test (Graceful): $msg"
        }
        catch {
            $errMsg = "Graceful Stop test encountered an unexpected error: $($_.Exception.Message)"
            Set-StatusText $errMsg
            Write-SetupLog "Operating Mode Test (Graceful): $errMsg"
        }
        finally {
            Update-TestButtonsTooltips
        }
    })

# ---- Test Classic Stop --------------------------------------
$script:btnTestClassic.add_Click({
        try {
            $target = Resolve-TestTarget

            if (-not $target.Valid) {
                $msg = "Cannot run test: $($target.Error)"
                Set-StatusText $msg
                Write-SetupLog "Operating Mode Test (Classic): $msg"
                return
            }

            # Check whether the app is currently running before calling Classic stop.
            $proc = Get-Process -Name $target.ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $proc) {
                $msg = "$($target.DisplayName) is not currently running. Nothing to stop."
                Set-StatusText $msg
                Write-SetupLog "Operating Mode Test (Classic): $msg"
                return
            }

            Set-StatusText "Running Classic Stop test on $($target.DisplayName)..."
            Write-SetupLog "Operating Mode Test (Classic): starting test on $($target.DisplayName) (process: $($target.ProcessName))"

            if (-not (Get-Command Invoke-AppStop -ErrorAction SilentlyContinue)) {
                $msg = "Invoke-AppStop is not available in this session. The Classic module may not have loaded."
                Set-StatusText $msg
                Write-SetupLog "Operating Mode Test (Classic): $msg"
                return
            }

            $r = Invoke-AppStop -ProcessName $target.ProcessName

            $stopped = ($r -and $r.Stopped -eq $true)
            $status = if ($r -and $r.Status) { [string]$r.Status } else { "Unknown" }

            if ($stopped) {
                $msg = "Classic Stop test PASSED for $($target.DisplayName). Status: $status."
            }
            else {
                $msg = "Classic Stop test did not confirm a stop for $($target.DisplayName). Status: $status."
            }

            # Informational note when the SAMISH engine is installed (no blocking).
            if (Test-SamishInstalled) {
                $msg += "`r`n`r`nNote: SAMISH engine is installed and running. Tests are safe during active use. The engine only triggers when your system has been idle for an extended period."
            }

            Set-StatusText $msg
            Write-SetupLog "Operating Mode Test (Classic): $msg"
        }
        catch {
            $errMsg = "Classic Stop test encountered an unexpected error: $($_.Exception.Message)"
            Set-StatusText $errMsg
            Write-SetupLog "Operating Mode Test (Classic): $errMsg"
        }
        finally {
            Update-TestButtonsTooltips
        }
    })

# ---- Start Test ----------------------------------------------
$script:btnTestStart.add_Click({
        try {
            $target = Resolve-TestTarget

            if (-not $target.Valid) {
                $msg = "Cannot run test: $($target.Error)"
                Set-StatusText $msg
                Write-SetupLog "Operating Mode Test (Start): $msg"
                return
            }

            # If configured for PauseMedia and already running, we test playback resumption directly
            $proc = Get-Process -Name $target.ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($proc) {
                if ($target.BeforeSleepMode -eq "PauseMedia") {
                    Set-StatusText "Relaunch not required ($($target.DisplayName) is running). Testing Media Play action..."
                    $resumed = Invoke-SmtcActionForProcess -ProcessName $target.ProcessName -Action "Play"
                    if ($resumed) {
                        $msg = "Start Test PASSED for $($target.DisplayName) (Media Play command succeeded)."
                    }
                    else {
                        $msg = "Start Test did not confirm playback for $($target.DisplayName) (SMTC play command failed or no session found)."
                    }
                    Set-StatusText $msg
                    Write-SetupLog "Operating Mode Test (Start): $msg"
                    return
                }
                else {
                    $msg = "$($target.DisplayName) is already running. Click 'Stop Test' first, then click 'Start Test' to verify it relaunches."
                    Set-StatusText $msg
                    Write-SetupLog "Operating Mode Test (Start): $msg"
                    return
                }
            }

            # A valid executable path is required to start the app.
            if (-not $target.ConfiguredPath -or -not (Test-Path -LiteralPath $target.ConfiguredPath -ErrorAction SilentlyContinue)) {
                $pathMsg = "SAMISH could not locate the executable for $($target.DisplayName)."
                if ($target.ConfiguredPath) {
                    $pathMsg += "`r`n`r`nPath tried: $($target.ConfiguredPath)"
                }
                $pathMsg += "`r`n`r`nIf the application is currently installed, try launching it once so SAMISH can detect it, then re-run the Start test."
                Write-SetupLog "Operating Mode Test (Start): path not found for $($target.DisplayName). Path tried: $($target.ConfiguredPath)"
                try {
                    Show-WarningDialog -Title "SAMISH - Start Test: Path Not Found" -Message $pathMsg
                }
                catch {
                    Set-StatusText $pathMsg
                }
                return
            }

            $infoMsg = "Running Start Test for $($target.DisplayName)..."
            if ($target.OnWakeAction -eq "Smart") {
                $smartNote = "Since the Start Test button runs in an ad-hoc test context (outside of actual system sleep/wake transitions), it does not have a real pre-sleep state. For the test, if the wake action is configured as Smart Restore, the test will assume the app was playing and attempt playback restoration."
                $infoMsg = "$smartNote`r`n`r`nRunning Start Test (Smart Restore: assuming pre-sleep playback state was playing) for $($target.DisplayName)..."
                Write-SetupLog "Operating Mode Test (Start): $smartNote"
            }
            Set-StatusText $infoMsg
            Write-SetupLog "Operating Mode Test (Start): starting test for $($target.DisplayName) (process: $($target.ProcessName), path: $($target.ConfiguredPath))"

            if (-not (Get-Command Invoke-AppStart -ErrorAction SilentlyContinue)) {
                $msg = "Invoke-AppStart is not available in this session. The Classic module may not have loaded."
                Set-StatusText $msg
                Write-SetupLog "Operating Mode Test (Start): $msg"
                return
            }

            $r = Invoke-AppStart -ProcessName $target.ProcessName -ExePath $target.ConfiguredPath

            $started = ($r -and $r.Started -eq $true)
            $status = if ($r -and $r.Status) { [string]$r.Status } else { "Unknown" }
            $method = if ($r -and $r.Method) { [string]$r.Method } else { "" }
            $trace = if ($r -and $r.Log) { [string]$r.Log } else { "" }

            if ($started) {
                $msg = "Start Test PASSED for $($target.DisplayName). Status: $status"
                if ($method) { $msg += " (Method: $method)" }
                $msg += "."

                # If the app has Media Control, try to send the Play command to complete the wake test
                $shouldPlay = ($target.OnWakeAction -eq "Play" -or $target.OnWakeAction -eq "Smart")
                if ($shouldPlay) {
                    Write-SetupLog "Operating Mode Test (Start): polling SMTC session to send Play command (up to 15 seconds, retrying every 250 ms)."
                    $sessionFound = $false
                    $playConfirmed = $false
                    $processCrashed = $false

                    for ($i = 0; $i -lt 60; $i++) {
                        # Early Exit: Check if process is still running
                        $currentProc = Get-Process -Name $target.ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
                        if (-not $currentProc) {
                            $processCrashed = $true
                            break
                        }

                        $session = Get-SmtcSessionForProcess -ProcessName $target.ProcessName
                        if ($session) {
                            $sessionFound = $true
                            
                            # Send Play command
                            $resumed = Invoke-SmtcActionForProcess -ProcessName $target.ProcessName -Action "Play"
                            
                            # Sleep for 250 ms to allow playback state to transition
                            Start-Sleep -Milliseconds 250
                            
                            # Verify playback state
                            $statusVal = Get-SmtcPlaybackStatus -ProcessName $target.ProcessName
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
                        $msg += " Media play failed because the application process exited or crashed during startup."
                    }
                    elseif ($playConfirmed) {
                        $logMsg = "Media Control Confirmed via SMTC after $loops loops ($timeString)."
                        Write-SetupLog "Operating Mode Test (Start): $logMsg"
                        $msg += " $logMsg"
                    }
                    elseif ($sessionFound) {
                        $msg += " Media play command sent but playback state could not be confirmed within 15 seconds ($loops loops tried)."
                    }
                    else {
                        $msg += " Warning: SMTC session not found within 15 seconds to resume playback ($loops loops tried)."
                    }
                }

                if ($method -ne "Direct" -and $trace) {
                    $msg += "`r`n`r`nDiagnostic Trace:"
                    foreach ($step in $trace.Split(";")) {
                        $trimmed = $step.Trim()
                        if ($trimmed) { $msg += "`r`n- $trimmed" }
                    }
                }
            }
            elseif ($status -eq "AlreadyRunning") {
                $msg = "$($target.DisplayName) started (or was already running) by the time the launch command fired. Status: $status."
            }
            elseif ($status -eq "PathInvalid") {
                $msg = "Start Test could not launch $($target.DisplayName). The executable path was not found or is invalid."
            }
            else {
                $msg = "Start Test did not confirm a launch for $($target.DisplayName). Status: $status."
                if ($trace) {
                    $msg += "`r`n`r`nDiagnostic Trace:"
                    foreach ($step in $trace.Split(";")) {
                        $trimmed = $step.Trim()
                        if ($trimmed) { $msg += "`r`n- $trimmed" }
                    }
                }
            }

            # Retain the Smart Restore note in the final status bar message if applicable (prepended for logical/chronological flow)
            if ($target.OnWakeAction -eq "Smart") {
                $msg = "Note: Since the Start Test button runs in an ad-hoc test context (outside of actual system sleep/wake transitions), it does not have a real pre-sleep state. For the test, if the wake action is configured as Smart Restore, the test will assume the app was playing and attempt playback restoration.`r`n`r`n$msg"
            }

            # Informational note when the SAMISH engine is installed (no blocking).
            if (Test-SamishInstalled) {
                $msg += "`r`n`r`nNote: SAMISH engine is installed and running. Tests are safe during active use. The engine only triggers when your system has been idle for an extended period."
            }

            Set-StatusText $msg
            Write-SetupLog "Operating Mode Test (Start): $msg"
        }
        catch {
            $errMsg = "Start Test encountered an unexpected error: $($_.Exception.Message)"
            Set-StatusText $errMsg
            Write-SetupLog "Operating Mode Test (Start): $errMsg"
        }
        finally {
            Update-TestButtonsTooltips
        }
    })

# ---- Stop Test -----------------------------------------------
$script:btnTestStop.add_Click({
        try {
            $target = Resolve-TestTarget

            if (-not $target.Valid) {
                $msg = "Cannot run test: $($target.Error)"
                Set-StatusText $msg
                Write-SetupLog "Operating Mode Test (Stop): $msg"
                return
            }

            # App must be running to test stop/pause actions
            $proc = Get-Process -Name $target.ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $proc) {
                $msg = "$($target.DisplayName) is not currently running. Nothing to stop."
                Set-StatusText $msg
                Write-SetupLog "Operating Mode Test (Stop): $msg"
                return
            }

            # Run the configured before-sleep stop/pause action
            $mode = $target.BeforeSleepMode
            Set-StatusText "Running Stop Test ($mode) on $($target.DisplayName)..."
            Write-SetupLog "Operating Mode Test (Stop): starting stop test ($mode) on $($target.DisplayName)"

            if ($mode -eq "PauseMedia") {
                $paused = Invoke-SmtcActionForProcess -ProcessName $target.ProcessName -Action "Pause"
                if ($paused) {
                    $msg = "Stop Test PASSED for $($target.DisplayName) (Media successfully paused)."
                }
                else {
                    $msg = "Stop Test did not confirm media pause for $($target.DisplayName) (SMTC pause command failed or no session found)."
                }
            }
            elseif ($mode -eq "Graceful") {
                if (-not (Get-Command Invoke-AppStopGraceful -ErrorAction SilentlyContinue)) {
                    $msg = "Invoke-AppStopGraceful is not available in this session. The Graceful module may not have loaded."
                    Set-StatusText $msg
                    return
                }
                $r = Invoke-AppStopGraceful `
                    -ProcessName       $target.ProcessName `
                    -ConfiguredPath    $target.ConfiguredPath `
                    -WindowWakeDelayMs $target.WindowWakeDelayMs `
                    -ShutdownWaitMs    $target.ShutdownWaitMs
                $method = if ($r -and $r.Method) { [string]$r.Method } else { "Unknown" }
                $stopped = ($r -and $r.Stopped -eq $true)
                $errTxt = if ($r -and $r.Error) { [string]$r.Error } else { "" }
                if ($stopped) {
                    $msg = "Stop Test PASSED for $($target.DisplayName) (Graceful close succeeded via $method)."
                }
                else {
                    $msg = "Stop Test did not confirm a clean stop for $($target.DisplayName). Method: $method."
                    if ($errTxt) { $msg += " $errTxt" }
                }
            }
            else {
                # Classic mode fallback
                if (-not (Get-Command Invoke-AppStop -ErrorAction SilentlyContinue)) {
                    $msg = "Invoke-AppStop is not available in this session. The Classic module may not have loaded."
                    Set-StatusText $msg
                    return
                }
                $r = Invoke-AppStop -ProcessName $target.ProcessName
                $stopped = ($r -and $r.Stopped -eq $true)
                $status = if ($r -and $r.Status) { [string]$r.Status } else { "Unknown" }
                if ($stopped) {
                    $msg = "Stop Test PASSED for $($target.DisplayName) (Classic close succeeded. Status: $status)."
                }
                else {
                    $msg = "Stop Test did not confirm a stop for $($target.DisplayName). Status: $status."
                }
            }

            # Informational note when the SAMISH engine is installed (no blocking).
            if (Test-SamishInstalled) {
                $msg += "`r`n`r`nNote: SAMISH engine is installed and running. Tests are safe during active use. The engine only triggers when your system has been idle for an extended period."
            }

            Set-StatusText $msg
            Write-SetupLog "Operating Mode Test (Stop): $msg"
        }
        catch {
            $errMsg = "Stop Test encountered an unexpected error: $($_.Exception.Message)"
            Set-StatusText $errMsg
            Write-SetupLog "Operating Mode Test (Stop): $errMsg"
        }
        finally {
            Update-TestButtonsTooltips
        }
    })

# ---- Helper to format automated app label with friendly Before Sleep and On Wake Actions ----
function Get-AutomatedAppDisplayLabel {
    param(
        [Parameter(Mandatory = $true)]
        $app
    )

    $sleepMode = if ($app.RecoveryMode) { $app.RecoveryMode } else { $script:OperatingMode }
    if ($sleepMode -eq "PauseMedia") { $sleepMode = "Keep App Open" }

    $onWake = if ($app.PSObject.Properties['OnWakeAction']) { $app.OnWakeAction } else { "Smart" }
    $onWakeLabel = switch ($onWake) {
        "Smart" { "Smart" }
        "Play" { "Play" }
        "Pause" { "Pause" }
        "KeepClosed" { "Keep Closed" }
        "ReopenOnly" { "Reopen Only" }
        default { $onWake }
    }

    return "$($app.ProcessName) [$sleepMode - $onWakeLabel]"
}

# ---- Live Sync operating mode updates for automated apps display ----
function Update-AutomatedAppsListDisplay {
    if (-not $script:listAutomated -or -not $script:MonitoredApps) { return }

    # Sync selection to restore it after update
    $selectedIndex = $script:listAutomated.SelectedIndex

    $script:diagListMutex = $true
    try {
        $script:listAutomated.Items.Clear()
        foreach ($app in $script:MonitoredApps) {
            $label = Get-AutomatedAppDisplayLabel -app $app
            $script:listAutomated.Items.Add($label) | Out-Null
        }

        if ($script:listAutomated.Items.Count -eq 0) {
            $script:listAutomated.Items.Add("(No apps automated by SAMISH yet)") | Out-Null
        }
        else {
            if ($selectedIndex -ge 0 -and $selectedIndex -lt $script:listAutomated.Items.Count) {
                $script:listAutomated.SelectedIndex = $selectedIndex
            }
        }
    }
    catch {}
    finally {
        $script:diagListMutex = $false
    }
}

$syncOperatingMode = {
    $script:OperatingMode = if ($rbOpClassic.Checked) { "Classic" } else { "Graceful" }
    Update-AutomatedAppsListDisplay
    
    # Also update details label if an app is selected
    if ($script:listAutomated -and $script:lblDiagDetail) {
        $idx = $script:listAutomated.SelectedIndex
        if ($idx -ge 0 -and $idx -lt $script:MonitoredApps.Count) {
            $app = $script:MonitoredApps[$idx]
            $mode = if ($app.RecoveryMode) { $app.RecoveryMode } else { $script:OperatingMode }
            $displayMode = if ($mode -eq "PauseMedia") { "Keep App Open" } else { $mode }
            $script:lblDiagDetail.Text = "Automated: $($app.ProcessName)    Mode: $displayMode`r`nPath: $($app.ExecutablePath)"
        }
    }
}

if ($rbOpGraceful) { $rbOpGraceful.add_CheckedChanged($syncOperatingMode) }
if ($rbOpClassic) { $rbOpClassic.add_CheckedChanged($syncOperatingMode) }


# =====================================================================
# V1.2.2 CUSTOM TAB UNDERLINE AND HOVER DECORATORS
# =====================================================================

function Update-TabIndicator {
    if (-not $script:tabIndicatorLine) { return }
    $isExpanded = ($form.ClientSize.Width -gt 800)
    
    if ($global:ThemeNeonActive) {
        $btnTabSetup.BackColor = [System.Drawing.Color]::FromArgb(35, 35, 40)
        $btnTabDiag.BackColor  = [System.Drawing.Color]::FromArgb(35, 35, 40)
    } else {
        $btnTabSetup.BackColor = [System.Drawing.SystemColors]::Control
        $btnTabDiag.BackColor  = [System.Drawing.SystemColors]::Control
    }

    if ($tabControl.SelectedIndex -eq 0) {
        if ($global:ThemeNeonActive) {
            $btnTabSetup.ForeColor = $global:NeonCyan
            $btnTabDiag.ForeColor  = $global:NeonText
        } else {
            $btnTabSetup.ForeColor = [System.Drawing.SystemColors]::ControlText
            $btnTabDiag.ForeColor  = [System.Drawing.Color]::DimGray
        }

        # Setup tab is active
        if ($isExpanded) {
            $script:tabIndicatorLine.Location = New-Object System.Drawing.Point(330, 78)
            $script:tabIndicatorLine.Size = New-Object System.Drawing.Size(190, 2)
        }
        else {
            $script:tabIndicatorLine.Location = New-Object System.Drawing.Point(330, 78)
            $script:tabIndicatorLine.Size = New-Object System.Drawing.Size(145, 2)
        }
    }
    else {
        if ($global:ThemeNeonActive) {
            $btnTabDiag.ForeColor  = $global:NeonCyan
            $btnTabSetup.ForeColor = $global:NeonText
        } else {
            $btnTabDiag.ForeColor  = [System.Drawing.SystemColors]::ControlText
            $btnTabSetup.ForeColor = [System.Drawing.Color]::DimGray
        }

        # Diagnostics tab is active
        if ($isExpanded) {
            $script:tabIndicatorLine.Location = New-Object System.Drawing.Point(530, 78)
            $script:tabIndicatorLine.Size = New-Object System.Drawing.Size(260, 2)
        }
        else {
            $script:tabIndicatorLine.Location = New-Object System.Drawing.Point(485, 78)
            $script:tabIndicatorLine.Size = New-Object System.Drawing.Size(180, 2)
        }
    }
    Update-SecondaryTabStyles
}

function global:Update-SecondaryTabStyles {
    if ($global:ThemeNeonActive) {
        $secTabBg = [System.Drawing.Color]::FromArgb(35, 35, 40)
        $activeColor = $global:NeonCyan
        $inactiveColor = $global:NeonText
    } else {
        $secTabBg = [System.Drawing.SystemColors]::Control
        $activeColor = [System.Drawing.SystemColors]::ControlText
        $inactiveColor = [System.Drawing.Color]::DimGray
    }

    # Telemetry tabs
    if ($script:btnTelemetryTabTimers -and $script:btnTelemetryTabArmed) {
        $script:btnTelemetryTabTimers.BackColor = $secTabBg
        $script:btnTelemetryTabArmed.BackColor = $secTabBg
        if ($script:tabTelemetryDetails -and $script:tabTelemetryDetails.SelectedIndex -eq 0) {
            $script:btnTelemetryTabTimers.ForeColor = $activeColor
            $script:btnTelemetryTabArmed.ForeColor = $inactiveColor
        } else {
            $script:btnTelemetryTabArmed.ForeColor = $activeColor
            $script:btnTelemetryTabTimers.ForeColor = $inactiveColor
        }
    }

    # Tools / Live Log tabs
    if ($script:btnSubTabTools -and $script:btnSubTabLive) {
        $script:btnSubTabTools.BackColor = $secTabBg
        $script:btnSubTabLive.BackColor = $secTabBg
        if ($script:IsLiveLogMode) {
            $script:btnSubTabLive.ForeColor = $activeColor
            $script:btnSubTabTools.ForeColor = $inactiveColor
        } else {
            $script:btnSubTabTools.ForeColor = $activeColor
            $script:btnSubTabLive.ForeColor = $inactiveColor
        }
    }
}

# (Removed Register-ButtonHoverBorder helper function and event hooks - hover background is natively handled by FlatAppearance in UI.ps1)


# =====================================================================
# V1.1.0 NAVIGATION & DRAWER EVENT HANDLERS
# =====================================================================

function Hide-All-Drawers {
    if ($script:grpAdvancedTools) { $script:grpAdvancedTools.Visible = $false }
    if ($script:grpAdvancedDiag)  { $script:grpAdvancedDiag.Visible  = $false }
    $form.ClientSize = New-Object System.Drawing.Size(800, 640)
    if ($script:pnlTabWrapper) {
        $script:pnlTabWrapper.Size = New-Object System.Drawing.Size(780, 490)
    }
    $tabControl.Size = New-Object System.Drawing.Size(788, 498)

    # Reset drawer button labels so they never show stale "Close X" state
    if ($btnToolsAdvanced) { $btnToolsAdvanced.Text = "Advanced Tools >>" }
    if ($btnDiagAdvanced)  { $btnDiagAdvanced.Text  = "Diagnostics >>" }

    if ($script:toolsDrawerSep) { $script:toolsDrawerSep.Visible = $false }
    if ($script:diagDrawerSep)  { $script:diagDrawerSep.Visible  = $false }

    # Return logo to its home position
    if ($script:logo) { $script:logo.Location = New-Object System.Drawing.Point(718, 12) }

    # Hide live log controls if active
    if ($script:IsLiveLogMode) { Exit-LiveLogMode }

    # Stop telemetry if running
    if ($script:TelemetryTimer) {
        $script:TelemetryTimer.Stop()
        $script:TelemetryTimer.Dispose()
        $script:TelemetryTimer = $null
    }

    if ($script:mainSep) { $script:mainSep.Width = 764 }
    if ($script:bottomMetadata) {
        $script:bottomMetadata.Location = New-Object System.Drawing.Point(480, 606)
        $script:bottomMetadata.BringToFront()
    }

    # Contract tab buttons to default names/sizes
    if ($btnTabSetup) {
        $btnTabSetup.Text = "1. Setup && Install"
        $btnTabSetup.Location = New-Object System.Drawing.Point(330, 48)
        $btnTabSetup.Size = New-Object System.Drawing.Size(145, 30)
    }
    if ($btnTabDiag) {
        $btnTabDiag.Text = "2. Sleep Automation"
        $btnTabDiag.Location = New-Object System.Drawing.Point(485, 48)
        $btnTabDiag.Size = New-Object System.Drawing.Size(180, 30)
    }

    # Hide and reset Advanced Tools sub-tabs
    if ($btnSubTabTools) {
        $btnSubTabTools.Visible = $false
        $btnSubTabTools.Font = $boldFont
        $btnSubTabTools.ForeColor = [System.Drawing.SystemColors]::ControlText
    }
    if ($btnSubTabLive) {
        $btnSubTabLive.Visible = $false
        $btnSubTabLive.Font = $font
        $btnSubTabLive.ForeColor = [System.Drawing.Color]::DimGray
    }
    if ($script:advancedTabIndicator) {
        $script:advancedTabIndicator.Visible = $false
    }
    Update-TabIndicator
}

$btnTabSetup.add_Click({
        $tabControl.SelectedIndex = 0
        $btnTabSetup.Font = $boldFont
        $btnTabDiag.Font = $font
        Hide-All-Drawers
        Update-TabIndicator
    })

$btnTabDiag.add_Click({
        $tabControl.SelectedIndex = 1
        $btnTabDiag.Font = $boldFont
        $btnTabSetup.Font = $font
        Hide-All-Drawers
        # Initialize Page 2 handlers on first visit (was never called — root cause of all Page 2 bugs)
        if (-not $script:diagInitialized) {
            $script:diagInitialized = $true
            Init-SleepDiagnosticsEventHandlers
        }
        Update-TabIndicator
    })

$btnToolsAdvanced.add_Click({
        if ($form.ClientSize.Width -eq 800) {
            # Expand — slide logo to far right of new header space
            if ($script:pnlTabWrapper) {
                $script:pnlTabWrapper.Size = New-Object System.Drawing.Size(1160, 490)
            }
            $tabControl.Size = New-Object System.Drawing.Size(1168, 498)
            $form.ClientSize = New-Object System.Drawing.Size(1180, 640)
            [System.Windows.Forms.Application]::DoEvents()
            if ($script:grpAdvancedTools) {
                $script:grpAdvancedTools.Visible = $true
                $script:grpAdvancedTools.Invalidate()
            }
            if ($script:logo) { $script:logo.Location = New-Object System.Drawing.Point(1098, 12) }
            $btnToolsAdvanced.Text = "<< Close Tools"
            if ($script:toolsDrawerSep) { $script:toolsDrawerSep.Visible = $true }
            if ($script:mainSep) { $script:mainSep.Width = 1144 }
            if ($script:bottomMetadata) {
                $script:bottomMetadata.Location = New-Object System.Drawing.Point(860, 606)
                $script:bottomMetadata.BringToFront()
            }

            # Expand tab buttons to long names/sizes (Setup anchored at X=330)
            if ($btnTabSetup) {
                $btnTabSetup.Text = "1. Setup && Installation"
                $btnTabSetup.Location = New-Object System.Drawing.Point(330, 48)
                $btnTabSetup.Size = New-Object System.Drawing.Size(190, 30)
            }
            if ($btnTabDiag) {
                $btnTabDiag.Text = "2. Sleep Automation && Diagnostics"
                $btnTabDiag.Location = New-Object System.Drawing.Point(530, 48)
                $btnTabDiag.Size = New-Object System.Drawing.Size(260, 30)
            }

            # Show sub-tabs
            if ($btnSubTabTools) { $btnSubTabTools.Visible = $true }
            if ($btnSubTabLive) { $btnSubTabLive.Visible = $true }
            if ($script:advancedTabIndicator) {
                if ($script:IsLiveLogMode) {
                    $script:advancedTabIndicator.Location = New-Object System.Drawing.Point(270, 38)
                }
                else {
                    $script:advancedTabIndicator.Location = New-Object System.Drawing.Point(190, 38)
                }
                $script:advancedTabIndicator.Visible = $true
            }
            Update-TabIndicator
        }
        else {
            # Collapse (Hide-All-Drawers resets text and logo)
            Hide-All-Drawers
        }
    })

$btnDiagAdvanced.add_Click({
        if ($form.ClientSize.Width -eq 800) {
            # Expand — slide logo to far right of new header space
            if ($script:pnlTabWrapper) {
                $script:pnlTabWrapper.Size = New-Object System.Drawing.Size(1160, 490)
            }
            $tabControl.Size = New-Object System.Drawing.Size(1168, 498)
            $form.ClientSize = New-Object System.Drawing.Size(1180, 640)
            [System.Windows.Forms.Application]::DoEvents()
            if ($script:grpAdvancedDiag) {
                $script:grpAdvancedDiag.Visible = $true
                $script:grpAdvancedDiag.Invalidate()
            }
            if ($script:logo) { $script:logo.Location = New-Object System.Drawing.Point(1098, 12) }
            $btnDiagAdvanced.Text = "<< Close Diagnostics"
            if ($script:diagDrawerSep) { $script:diagDrawerSep.Visible = $true }
            if ($script:mainSep) { $script:mainSep.Width = 1144 }
            if ($script:bottomMetadata) {
                $script:bottomMetadata.Location = New-Object System.Drawing.Point(860, 606)
                $script:bottomMetadata.BringToFront()
            }

            # Expand tab buttons to long names/sizes (Setup anchored at X=330)
            if ($btnTabSetup) {
                $btnTabSetup.Text = "1. Setup && Installation"
                $btnTabSetup.Location = New-Object System.Drawing.Point(330, 48)
                $btnTabSetup.Size = New-Object System.Drawing.Size(190, 30)
            }
            if ($btnTabDiag) {
                $btnTabDiag.Text = "2. Sleep Automation && Diagnostics"
                $btnTabDiag.Location = New-Object System.Drawing.Point(530, 48)
                $btnTabDiag.Size = New-Object System.Drawing.Size(260, 30)
            }

            # Trigger telemetry refresh
            if ($script:btnTelemetryRefresh) { $script:btnTelemetryRefresh.PerformClick() }
            Update-TabIndicator
        }
        else {
            # Collapse (Hide-All-Drawers resets text and logo)
            Hide-All-Drawers
        }
    })

$script:btnTelemetryRefresh.add_Click({
        $script:lblTelemetryStates.Text = "Querying system telemetry..."
        $script:txtLastWake.Text = ""
        $script:txtWakeTimers.Text = ""
        $script:listArmedDevices.Items.Clear()
    
        # Run async (simulated here with immediate run for brevity, but could use runspace)
        try {
            $diag = Get-SystemPowerDiagnostics
            $script:txtLastWake.Text = $diag.LastWake
        
            if ($diag.WakeTimers.Count -gt 0) {
                $script:txtWakeTimers.Text = ($diag.WakeTimers -join "`r`n")
            }
            else {
                $script:txtWakeTimers.Text = "No active wake timers."
            }
        
            if ($diag.ArmedDevices.Count -gt 0) {
                foreach ($dev in $diag.ArmedDevices) {
                    $script:listArmedDevices.Items.Add($dev) | Out-Null
                }
            }
            else {
                $script:listArmedDevices.Items.Add("No devices armed to wake the system.") | Out-Null
            }
        
            $script:lblTelemetryStates.Text = "Supported Sleep States: " + ($diag.SleepSupport -join ", ")
        }
        catch {
            $script:lblTelemetryStates.Text = "Failed to query telemetry."
        }
    })

# ----- Live Log Sub-Tab Handlers -----
function Show-SubTabTools {
    if ($btnSubTabTools) {
        $btnSubTabTools.Font = $boldFont
    }
    if ($btnSubTabLive) {
        $btnSubTabLive.Font = $font
    }

    # Hide live log and controls
    if ($txtLiveLog) { $txtLiveLog.Visible = $false }
    if ($script:liveLogSep) { $script:liveLogSep.Visible = $false }
    if ($btnLivePause) { $btnLivePause.Visible = $false }
    if ($btnLiveCopy) { $btnLiveCopy.Visible = $false }
    if ($btnLiveClear) { $btnLiveClear.Visible = $false }

    if ($script:LiveLogTimer) {
        $script:LiveLogTimer.Stop()
        $script:LiveLogTimer.Dispose()
        $script:LiveLogTimer = $null
    }
    $script:IsLiveLogMode = $false

    # Show utility buttons
    if ($btnPowerPlan) { $btnPowerPlan.Visible = $true }
    if ($btnOpenTS) { $btnOpenTS.Visible = $true }
    if ($btnCleanReset) { $btnCleanReset.Visible = $true }
    if ($btnReadSetup) { $btnReadSetup.Visible = $true }
    if ($btnOpenLog) { $btnOpenLog.Visible = $true }

    if ($script:advancedTabIndicator) {
        $script:advancedTabIndicator.Location = New-Object System.Drawing.Point(190, 38)
        $script:advancedTabIndicator.Visible = $true
    }
    Update-SecondaryTabStyles
}

function Show-SubTabLive {
    if ($btnSubTabLive) {
        $btnSubTabLive.Font = $boldFont
    }
    if ($btnSubTabTools) {
        $btnSubTabTools.Font = $font
    }

    if (-not $script:LiveLogPath) { $script:LiveLogPath = Get-VerifiedPreferredLogPathOrShowMessageBox }
    $path = $script:LiveLogPath
    if (-not $path -or -not (Test-Path -LiteralPath $path)) {
        # Switch back to tools if log path isn't valid
        Show-SubTabTools
        return
    }

    $script:IsLiveLogMode = $true
    $script:IsLiveLogPaused = $false
    if ($btnLivePause) { $btnLivePause.Text = "Pause" }

    # Hide utility buttons
    if ($btnPowerPlan) { $btnPowerPlan.Visible = $false }
    if ($btnOpenTS) { $btnOpenTS.Visible = $false }
    if ($btnCleanReset) { $btnCleanReset.Visible = $false }
    if ($btnReadSetup) { $btnReadSetup.Visible = $false }
    if ($btnOpenLog) { $btnOpenLog.Visible = $false }

    # Show live log controls
    if ($txtLiveLog) { $txtLiveLog.Visible = $true }
    if ($script:liveLogSep) { $script:liveLogSep.Visible = $true }
    if ($btnLivePause) { $btnLivePause.Visible = $true }
    if ($btnLiveCopy) { $btnLiveCopy.Visible = $true }
    if ($btnLiveClear) { $btnLiveClear.Visible = $true }

    if ($txtLiveLog) {
        $txtLiveLog.Clear()
        $tail = Read-LogTailText -Path $path -MaxChars 100000
        if (-not [string]::IsNullOrEmpty($tail)) {
            $txtLiveLog.AppendText($tail)
            if (-not $tail.EndsWith("`n")) {
                $txtLiveLog.AppendText("`r`n")
            }
        }
    }

    try {
        $fi = Get-Item -LiteralPath $path
        $script:LiveLogPosition = [int64]$fi.Length
    }
    catch { $script:LiveLogPosition = 0 }

    if ($script:LiveLogTimer) {
        $script:LiveLogTimer.Stop()
        $script:LiveLogTimer.Dispose()
        $script:LiveLogTimer = $null
    }

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 350
    $timer.Add_Tick({
            if ($script:IsLiveLogPaused) { return }

            $fi = Get-Item -LiteralPath $script:LiveLogPath -ErrorAction SilentlyContinue
            if ($fi -and $fi.Length -gt $script:LiveLogPosition) {
                $fs = [System.IO.File]::Open($script:LiveLogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $fs.Seek($script:LiveLogPosition, [System.IO.SeekOrigin]::Begin) | Out-Null
                $reader = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
                $newText = $reader.ReadToEnd()
                $script:LiveLogPosition = $fi.Length
                $reader.Dispose()
                $fs.Dispose()

                if (![string]::IsNullOrEmpty($newText)) {
                    $txtLiveLog.AppendText($newText)
                    $txtLiveLog.SelectionStart = $txtLiveLog.TextLength
                    $txtLiveLog.ScrollToCaret()
                }
            }
        })
    $script:LiveLogTimer = $timer
    $timer.Start()

    if ($script:advancedTabIndicator) {
        $script:advancedTabIndicator.Location = New-Object System.Drawing.Point(270, 38)
        $script:advancedTabIndicator.Visible = $true
    }
    Update-SecondaryTabStyles
}

function Enter-LiveLogMode {
    Show-SubTabLive
}

function Exit-LiveLogMode {
    Show-SubTabTools
}

# Wire sub-tab buttons
if ($btnSubTabTools) { $btnSubTabTools.add_Click({ Show-SubTabTools }) }
if ($btnSubTabLive) { $btnSubTabLive.add_Click({ Show-SubTabLive }) }

if ($btnLivePause) {
    $btnLivePause.add_Click({ 
        $script:IsLiveLogPaused = -not $script:IsLiveLogPaused
        if ($script:IsLiveLogPaused) { $btnLivePause.Text = "Resume" } else { $btnLivePause.Text = "Pause" }
    })
}
if ($btnLiveClear) { $btnLiveClear.add_Click({ if ($txtLiveLog) { $txtLiveLog.Clear() } }) }
if ($btnLiveCopy) {
    $btnLiveCopy.add_Click({ 
        if ($txtLiveLog -and $txtLiveLog.Text) { [System.Windows.Forms.Clipboard]::SetText($txtLiveLog.Text) }
    })
}

# Wire double-click on version label/metadata to open changelog
if ($bottomMetadata) {
    $bottomMetadata.add_DoubleClick({
        $changelogPath = Join-Path $PackageDir "CHANGELOG.md"
        if (Test-Path -LiteralPath $changelogPath) {
            Write-SetupLog "Changelog found at '$changelogPath'. Attempting to open."
            try {
                Start-Process $changelogPath | Out-Null
            }
            catch {
                Write-SetupLog "Error opening changelog: $($_.Exception.Message)"
            }
        }
        else {
            Write-SetupLog "Changelog not found at expected path: '$changelogPath'"
        }
    })
}

# Replace Set-StatusText to remove deferred logic
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

# Wire custom telemetry sub-tab buttons
if ($btnTelemetryTabTimers) {
    $btnTelemetryTabTimers.add_Click({
        $tabTelemetryDetails.SelectedIndex = 0
        $btnTelemetryTabTimers.Font = $boldFont
        $btnTelemetryTabArmed.Font = $font
        $telemetryTabIndicator.Location = New-Object System.Drawing.Point(15, 142)
        $telemetryTabIndicator.Width = 90
        Update-SecondaryTabStyles
    })
}
if ($btnTelemetryTabArmed) {
    $btnTelemetryTabArmed.add_Click({
        $tabTelemetryDetails.SelectedIndex = 1
        $btnTelemetryTabArmed.Font = $boldFont
        $btnTelemetryTabTimers.Font = $font
        $telemetryTabIndicator.Location = New-Object System.Drawing.Point(110, 142)
        $telemetryTabIndicator.Width = 115
        Update-SecondaryTabStyles
    })
}

# Initialise tooltips on load
Update-TestButtonsTooltips

# --- Branding Interactions (Easter Egg) ---
if ($logo) {
    $logo.add_DoubleClick({
        if ($global:IsThemeAnimating) { return }
        . (Join-Path $global:PackageDir "Modules\Theme-Extension.ps1")
        Invoke-BrandSequence -Form $form
    })
}


