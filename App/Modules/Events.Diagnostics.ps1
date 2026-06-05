# ---------- Events.Diagnostics.ps1 ----------
# ============================================================
# Sleep & Hibernate Diagnostics - Event Wiring
# ============================================================

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

function Sync-TelemetryActionButton {
    <#
    .SYNOPSIS
        Re-evaluates the currently selected telemetry list item and updates
        the action button text + visual state to match. Called when switching
        between System Telemetry and Hardware Telemetry sub-tabs.
    #>
    if (-not $script:btnTelemetryAction) { return }

    # Check wake timers list (System Telemetry tab)
    if ($script:listWakeTimers -and $script:listWakeTimers.SelectedIndex -ge 0) {
        $sel = $script:listWakeTimers.Items[$script:listWakeTimers.SelectedIndex].ToString()
        if ($sel -ne "No active wake timers.") {
            if ($sel -match 'NT TASK\\([^\''\"]+)') {
                $script:btnTelemetryAction.Text = "Disable Timer"
                Set-ButtonVisualState -Button $script:btnTelemetryAction -Active $true
                return
            } elseif ($sel -match '^\s*Timer set by \[SERVICE\]') {
                $script:btnTelemetryAction.Text = "Disable Service"
                Set-ButtonVisualState -Button $script:btnTelemetryAction -Active $true
                return
            } elseif ($sel -match '^\s*Timer set by \[PROCESS\]') {
                $script:btnTelemetryAction.Text = "Stop Process"
                Set-ButtonVisualState -Button $script:btnTelemetryAction -Active $true
                return
            }
        }
    }

    # Check armed devices list (Hardware Telemetry tab)
    if ($script:listArmedDevices -and $script:listArmedDevices.SelectedIndex -ge 0) {
        $sel = $script:listArmedDevices.Items[$script:listArmedDevices.SelectedIndex].ToString()
        if ($sel -ne "No devices armed to wake the system.") {
            $script:btnTelemetryAction.Text = "Disable Wake"
            Set-ButtonVisualState -Button $script:btnTelemetryAction -Active $true
            return
        }
    }

    # Check hardware scans list (Hardware Telemetry tab)
    if ($script:listHardwareScans -and $script:listHardwareScans.SelectedIndex -ge 0) {
        $sel = $script:listHardwareScans.Items[$script:listHardwareScans.SelectedIndex].ToString()
        if ($sel -match "^USB:\s*(.+)$") {
            $script:btnTelemetryAction.Text = "Toggle Suspend"
            Set-ButtonVisualState -Button $script:btnTelemetryAction -Active $true
            return
        }
    }

    # No valid selection in any list
    $script:btnTelemetryAction.Text = "Select Item..."
    Set-ButtonVisualState -Button $script:btnTelemetryAction -Active $false
    Update-TelemetryActionTooltip -text "Select an armed hardware device, USB hub, or active wake timer above to take corrective action."
}

function Complete-SleepDiagnosticsListsUpdate {
    param(
        [hashtable]$SyncState,
        [switch]$Silent
    )

    # Disable buttons until selection is made (visual-only, keeps tooltips)
    if ($script:btnDiagAutomate) {
        Set-ButtonVisualState -Button $script:btnDiagAutomate -Active $false
        $script:btnDiagAutomate.Text = "Add to Automated Apps"
    }
    if ($script:btnDiagIgnore) { Set-ButtonVisualState -Button $script:btnDiagIgnore -Active $false }
    if ($script:btnDiagRestore) { Set-ButtonVisualState -Button $script:btnDiagRestore -Active $false }
    if ($script:btnDiagStopAuto) { Set-ButtonVisualState -Button $script:btnDiagStopAuto -Active $false }
    if ($script:btnDiagOpenLocation) { Set-ButtonVisualState -Button $script:btnDiagOpenLocation -Active $false }
    Set-OperatingModeBoxState -Enabled $false

    # ---- Active Blockers ----
    $newBlockersItems = @()
    $script:ActiveBlockersList = @()
    if ($SyncState.Error) {
        if (-not $Silent) {
            $script:lblDiagDetail.Text = "Error scanning blockers: $($SyncState.Error)"
        }
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
                $newBlockersItems += "$icon $($b.DisplayName)"
            }
        }
    }
    if ($newBlockersItems.Count -eq 0) {
        $newBlockersItems += "(No active blockers found - your system can sleep!)"
    }

    # ---- System Overrides ----
    $newOverridesItems = @()
    $script:SystemOverridesList = @()
    if ($SyncState.Overrides) {
        foreach ($ov in $SyncState.Overrides) {
            if ($ov.Name -like "*BEACN*") { continue }
            $script:SystemOverridesList += $ov
            $newOverridesItems += $ov.DisplayLabel
        }
    }
    if ($newOverridesItems.Count -eq 0) {
        $newOverridesItems += "(No custom overrides configured)"
    }

    # ---- Automated Apps ----
    $newAutomatedItems = @()
    if ($script:MonitoredApps) {
        foreach ($app in $script:MonitoredApps) {
            $label = Get-AutomatedAppDisplayLabel -app $app
            $newAutomatedItems += $label
        }
    }
    if ($newAutomatedItems.Count -eq 0) {
        $newAutomatedItems += "(No apps automated by SAMISH yet)"
    }

    # Update list boxes with fail-forward try/catch and diff-based check
    try {
        if ($Silent) {
            # listBlockers update
            $currentBlockers = @($script:listBlockers.Items)
            $blockersChanged = $false
            if ($currentBlockers.Count -ne $newBlockersItems.Count) {
                $blockersChanged = $true
            }
            else {
                for ($k = 0; $k -lt $newBlockersItems.Count; $k++) {
                    if ($currentBlockers[$k] -ne $newBlockersItems[$k]) {
                        $blockersChanged = $true
                        break
                    }
                }
            }
            if ($blockersChanged) {
                try {
                    $script:listBlockers.BeginUpdate()
                    $script:listBlockers.Items.Clear()
                    foreach ($item in $newBlockersItems) {
                        $script:listBlockers.Items.Add($item) | Out-Null
                    }
                }
                finally {
                    $script:listBlockers.EndUpdate()
                }
            }

            # listOverrides update
            $currentOverrides = @($script:listOverrides.Items)
            $overridesChanged = $false
            if ($currentOverrides.Count -ne $newOverridesItems.Count) {
                $overridesChanged = $true
            }
            else {
                for ($k = 0; $k -lt $newOverridesItems.Count; $k++) {
                    if ($currentOverrides[$k] -ne $newOverridesItems[$k]) {
                        $overridesChanged = $true
                        break
                    }
                }
            }
            if ($overridesChanged) {
                try {
                    $script:listOverrides.BeginUpdate()
                    $script:listOverrides.Items.Clear()
                    foreach ($item in $newOverridesItems) {
                        $script:listOverrides.Items.Add($item) | Out-Null
                    }
                }
                finally {
                    $script:listOverrides.EndUpdate()
                }
            }

            # listAutomated update
            $currentAutomated = @($script:listAutomated.Items)
            $automatedChanged = $false
            if ($currentAutomated.Count -ne $newAutomatedItems.Count) {
                $automatedChanged = $true
            }
            else {
                for ($k = 0; $k -lt $newAutomatedItems.Count; $k++) {
                    if ($currentAutomated[$k] -ne $newAutomatedItems[$k]) {
                        $automatedChanged = $true
                        break
                    }
                }
            }
            if ($automatedChanged) {
                try {
                    $script:listAutomated.BeginUpdate()
                    $script:listAutomated.Items.Clear()
                    foreach ($item in $newAutomatedItems) {
                        $script:listAutomated.Items.Add($item) | Out-Null
                    }
                }
                finally {
                    $script:listAutomated.EndUpdate()
                }
            }
        }
        else {
            # Non-silent path: always clear and redraw
            $script:listBlockers.Items.Clear()
            foreach ($item in $newBlockersItems) { $script:listBlockers.Items.Add($item) | Out-Null }
            
            $script:listOverrides.Items.Clear()
            foreach ($item in $newOverridesItems) { $script:listOverrides.Items.Add($item) | Out-Null }

            $script:listAutomated.Items.Clear()
            foreach ($item in $newAutomatedItems) { $script:listAutomated.Items.Add($item) | Out-Null }
        }
    }
    catch {
        # Fail forward fallback: if diff logic throws, redraw lists directly to maintain reliability
        try {
            $script:listBlockers.Items.Clear()
            foreach ($item in $newBlockersItems) { $script:listBlockers.Items.Add($item) | Out-Null }
            $script:listOverrides.Items.Clear()
            foreach ($item in $newOverridesItems) { $script:listOverrides.Items.Add($item) | Out-Null }
            $script:listAutomated.Items.Clear()
            foreach ($item in $newAutomatedItems) { $script:listAutomated.Items.Add($item) | Out-Null }
        }
        catch {}
    }
}

function Update-SleepDiagnosticsListsAsync {
    param(
        [switch]$Silent
    )

    if (-not $Silent) {
        $script:listBlockers.Items.Clear()
        $script:listOverrides.Items.Clear()
        $script:listAutomated.Items.Clear()
        $script:listBlockers.Items.Add("(Scanning for active blockers in background...)") | Out-Null
        $script:listOverrides.Items.Add("(Scanning for overrides...)") | Out-Null
        $script:listAutomated.Items.Add("(Scanning automated apps...)") | Out-Null

        $script:lblDiagDetail.Text = "Scanning system blockers in background... Please wait."
        Set-ButtonVisualState -Button $script:btnDiagScan -Active $false
    }

    $script:DiagSyncState = [hashtable]::Synchronized(@{
            "DiagModulePath"    = $DiagModulePath
            "Blockers"          = $null
            "Overrides"         = $null
            "Error"             = $null
            "Complete"          = $false
            "AutomatedAppNames" = @($script:MonitoredApps | ForEach-Object { $_.ProcessName })
            "Silent"            = [bool]$Silent
        })

    try {
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

                    $isSilent = $script:DiagSyncState.Silent
                    Complete-SleepDiagnosticsListsUpdate -SyncState $script:DiagSyncState -Silent $isSilent
                    
                    if (-not $isSilent) {
                        $script:lblDiagDetail.Text = "Last scan completed at $(Get-Date -Format 'HH:mm:ss')."
                        $script:lblDiagDetail.ForeColor = [System.Drawing.Color]::DimGray
                        Set-ButtonVisualState -Button $script:btnDiagScan -Active $true
                    }
                }
            })
        $script:DiagTimer.Start()
    }
    catch {
        # Fail forward gracefully: clean up runspaces and restore button state if execution fails
        if ($script:btnDiagScan) { Set-ButtonVisualState -Button $script:btnDiagScan -Active $true }
        if ($script:lblDiagDetail) { $script:lblDiagDetail.Text = "Failed to launch scanner: $($_.Exception.Message)" }
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
        if ($ctrl -is [System.Windows.Forms.ComboBox]) {
            # Keep Enabled=$true always to avoid OS disabled-border rendering in neon mode.
            # Exception: fall back to Enabled toggling if the SelectionChangeCommitted hook failed to register.
            try {
                if ($script:wakeDropdownFallback) {
                    $ctrl.Enabled = $Enabled
                }
                else {
                    $ctrl.Enabled = $true
                    $script:wakeDropdownActive = $Enabled
                }
                # When disabled, reset the items and selection to "Select App"
                if (-not $Enabled) {
                    $ctrl.Items.Clear()
                    [void]$ctrl.Items.Add("- Select App -")
                    $ctrl.SelectedIndex = 0
                }
            }
            catch {
                $errPath = if ($global:PackageDir) { "$global:PackageDir\SAMISH_ERROR.txt" } else { "C:\Scripts\GOOGLE-ANTI-GRAVITY\SAMISH\SAMISH_ERROR.txt" }
                Out-File -FilePath $errPath -Append `
                    -InputObject "[$(Get-Date -Format 'HH:mm:ss')] WakeDropdown state update failed: $($_.Exception.Message)"
                try { $ctrl.Enabled = $Enabled } catch {}  # last-resort fallback
            }
            if ($global:ThemeCustomActive) {
                $ctrl.BackColor = if ($Enabled) { $global:ThemeCustomInput } else { $global:ThemeCustomDisabled }
                $ctrl.ForeColor = if ($Enabled) { $global:ThemeCustomPrimary } else { $global:ThemeCustomDisabledText }
            }
            else {
                if ($Enabled) {
                    $ctrl.ResetBackColor()
                    $ctrl.ResetForeColor()
                }
                else {
                    # Mimic OS disabled appearance without using Enabled=$false (avoids border change)
                    $ctrl.BackColor = [System.Drawing.SystemColors]::Control
                    $ctrl.ForeColor = [System.Drawing.SystemColors]::GrayText
                }
            }
        }
        elseif ($ctrl -is [System.Windows.Forms.RadioButton] -or $ctrl -is [System.Windows.Forms.Label] -or $ctrl -is [System.Windows.Forms.CheckBox]) {
            if ($global:ThemeCustomActive) {
                $ctrl.Enabled = $true
                $ctrl.ForeColor = if ($Enabled) { $global:ThemeCustomText } else { $global:ThemeCustomDisabledText }
                if ($ctrl -is [System.Windows.Forms.RadioButton]) {
                    $ctrl.AutoCheck = $Enabled
                }
            }
            else {
                $ctrl.Enabled = $Enabled
                $ctrl.ForeColor = [System.Drawing.SystemColors]::ControlText
                if ($ctrl -is [System.Windows.Forms.RadioButton]) {
                    $ctrl.AutoCheck = $true
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
        $color1 = if ($global:ThemeCustomActive) { $global:ThemeCustomPrimary } else { $script:BrandCyan }
        if ($null -eq $color1) { $color1 = [System.Drawing.Color]::FromArgb(0, 215, 255) }
        $color2 = if ($global:ThemeCustomActive) { $global:ThemeCustomAlert } else { $script:BrandPurple }
        if ($null -eq $color2) { $color2 = [System.Drawing.Color]::FromArgb(255, 60, 160) }

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
        $script:grpDiagOperatingMode.ForeColor = if ($global:ThemeCustomActive) { [System.Drawing.Color]::FromArgb(120, 60, 80) } else { [System.Drawing.Color]::Gray }
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
    if ($script:listHardwareScans) { $script:listHardwareScans.add_DrawItem($lbDrawItem) }
    if ($script:listWakeTimers) { $script:listWakeTimers.add_DrawItem($lbDrawItem) }
 
    # Helper to set the dynamic tooltip safely
    function script:Update-TelemetryActionTooltip {
        param([string]$text)
        try {
            if ($tooltip -and $script:btnTelemetryAction) {
                $tooltip.SetToolTip($script:btnTelemetryAction, $text)
            }
        }
        catch {}
    }

    # ---------- Symmetrical Telemetry Selection Handling ----------
    $script:listArmedDevices.add_SelectedIndexChanged({
            if ($script:diagListMutex) { return }
            $script:diagListMutex = $true
            if ($script:listHardwareScans) { $script:listHardwareScans.ClearSelected() }
            if ($script:listWakeTimers) { $script:listWakeTimers.ClearSelected() }
            $script:diagListMutex = $false

            $idx = $script:listArmedDevices.SelectedIndex
            if ($idx -ge 0 -and $idx -lt $script:listArmedDevices.Items.Count) {
                $selectedItem = $script:listArmedDevices.Items[$idx].ToString()
                if ($selectedItem -ne "No devices armed to wake the system.") {
                    $script:btnTelemetryAction.Text = "Disable Wake"
                    Set-ButtonVisualState -Button $script:btnTelemetryAction -Active $true
                    $script:lblDiagDetail.Text = "Hardware Device: $selectedItem"
                    $script:lblDiagDetail.ForeColor = [System.Drawing.Color]::DimGray
                    Update-TelemetryActionTooltip -text "Disables the wake capability for the selected hardware device to prevent it from waking the PC from sleep. Creates a backup of the configuration that can be restored later."
                    return
                }
            }
        
            $script:btnTelemetryAction.Text = "Select Item..."
            Set-ButtonVisualState -Button $script:btnTelemetryAction -Active $false
            Update-TelemetryActionTooltip -text "Select an armed hardware device, USB hub, or active wake timer above to take corrective action."
        })

    if ($script:listHardwareScans) {
        $script:listHardwareScans.add_SelectedIndexChanged({
                if ($script:diagListMutex) { return }
                $script:diagListMutex = $true
                if ($script:listArmedDevices) { $script:listArmedDevices.ClearSelected() }
                if ($script:listWakeTimers) { $script:listWakeTimers.ClearSelected() }
                $script:diagListMutex = $false

                $idx = $script:listHardwareScans.SelectedIndex
                if ($idx -ge 0 -and $idx -lt $script:listHardwareScans.Items.Count) {
                    $selectedItem = $script:listHardwareScans.Items[$idx].ToString()
                    if ($selectedItem -match "^USB:\s*(.+)$") {
                        $script:btnTelemetryAction.Text = "Toggle Suspend"
                        Set-ButtonVisualState -Button $script:btnTelemetryAction -Active $true
                        $script:lblDiagDetail.Text = "USB Hub: $($Matches[1])"
                        $script:lblDiagDetail.ForeColor = [System.Drawing.Color]::DimGray
                        Update-TelemetryActionTooltip -text "Toggles USB Selective Suspend for the selected USB Hub to allow Windows to suspend the device when idle, saving power and preventing wake-locks. Creates a backup of the configuration that can be restored later."
                        return
                    }
                }

                $script:btnTelemetryAction.Text = "Select Item..."
                Set-ButtonVisualState -Button $script:btnTelemetryAction -Active $false
                Update-TelemetryActionTooltip -text "Select an armed hardware device, USB hub, or active wake timer above to take corrective action."
            })
    }

    if ($script:listWakeTimers) {
        $script:listWakeTimers.add_SelectedIndexChanged({
                if ($script:diagListMutex) { return }
                $script:diagListMutex = $true
                if ($script:listArmedDevices) { $script:listArmedDevices.ClearSelected() }
                if ($script:listHardwareScans) { $script:listHardwareScans.ClearSelected() }
                $script:diagListMutex = $false

                $idx = $script:listWakeTimers.SelectedIndex
                if ($idx -ge 0 -and $idx -lt $script:listWakeTimers.Items.Count) {
                    $selectedItem = $script:listWakeTimers.Items[$idx].ToString()
                    if ($selectedItem -ne "No active wake timers.") {
                        if ($selectedItem -match 'NT TASK\\([^\''"]+)') {
                            $script:btnTelemetryAction.Text = "Disable Timer"
                            Set-ButtonVisualState -Button $script:btnTelemetryAction -Active $true
                            $script:lblDiagDetail.Text = "Active Wake Timer (Scheduled Task): $selectedItem"
                            $script:lblDiagDetail.ForeColor = [System.Drawing.Color]::DimGray
                            Update-TelemetryActionTooltip -text "Disables the scheduled task associated with the active wake timer to prevent it from waking the PC from sleep. Creates a backup of the configuration that can be restored later."
                            return
                        }
                        elseif ($selectedItem -match '^Timer set by \[SERVICE\]') {
                            $script:btnTelemetryAction.Text = "Disable Service"
                            Set-ButtonVisualState -Button $script:btnTelemetryAction -Active $true
                            $script:lblDiagDetail.Text = "Active Wake Timer (Service): $selectedItem"
                            $script:lblDiagDetail.ForeColor = [System.Drawing.Color]::DimGray
                            Update-TelemetryActionTooltip -text "Disables and stops the Windows Service associated with the active wake timer to prevent it from waking the PC from sleep. Creates a backup of the configuration that can be restored later."
                            return
                        }
                        elseif ($selectedItem -match '^Timer set by \[PROCESS\]') {
                            $script:btnTelemetryAction.Text = "Stop Process"
                            Set-ButtonVisualState -Button $script:btnTelemetryAction -Active $true
                            $script:lblDiagDetail.Text = "Active Wake Timer (Process): $selectedItem"
                            $script:lblDiagDetail.ForeColor = [System.Drawing.Color]::DimGray
                            Update-TelemetryActionTooltip -text "Terminates the running process associated with the active wake timer to prevent it from waking the PC from sleep."
                            return
                        }
                    }
                }

                $script:btnTelemetryAction.Text = "Select Item..."
                Set-ButtonVisualState -Button $script:btnTelemetryAction -Active $false
                Update-TelemetryActionTooltip -text "Select an armed hardware device, USB hub, or active wake timer above to take corrective action."
            })
    }

    # ---------- Dynamic Telemetry Action Click Handler ----------
    if ($script:btnTelemetryAction) {
        $script:btnTelemetryAction.add_Click({
                if ($script:btnTelemetryAction.Text -eq "Disable Wake") {
                    $idx = $script:listArmedDevices.SelectedIndex
                    if ($idx -ge 0 -and $idx -lt $script:listArmedDevices.Items.Count) {
                        $selectedItem = $script:listArmedDevices.Items[$idx].ToString()
                        if ($selectedItem -eq "No devices armed to wake the system.") { return }

                        $confirm = Show-YesNoDialog `
                            -Title "Disable Wake Confirmation" `
                            -Message "Are you sure you want to disable wake capabilities for:`r`n`"$selectedItem`"?`r`n`r`nSAMISH will create a backup of this configuration before applying the change.`r`n`r`nTo restore this backup later, you can use the `"Verify & Restore Settings`" button on Page 1, or you will be prompted to restore it if you choose to uninstall SAMISH." `
                            -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning)

                        if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
                            try {
                                Backup-DeviceWakeState -DeviceName $selectedItem
                                powercfg /devicedisablewake $selectedItem 2>$null | Out-Null
                            
                                Write-SetupLog "Disabled wake for '$selectedItem' (backup created)."
                                $script:lblDiagDetail.Text = "Disabled wake for $selectedItem (Backup created)."
                            
                                [void][System.Windows.Forms.MessageBox]::Show(
                                    "Successfully disabled wake for `"$selectedItem`".`r`n`r`nA backup has been created in:`r`n`"$script:DeviceWakeBackupPath`"",
                                    "SAMISH Telemetry Fix",
                                    [System.Windows.Forms.MessageBoxButtons]::OK,
                                    [System.Windows.Forms.MessageBoxIcon]::Information
                                )

                                $script:btnTelemetryRefresh.PerformClick()
                            }
                            catch {
                                [void][System.Windows.Forms.MessageBox]::Show(
                                    "Failed to disable wake for `"$selectedItem`":`r`n$($_.Exception.Message)",
                                    "Error",
                                    [System.Windows.Forms.MessageBoxButtons]::OK,
                                    [System.Windows.Forms.MessageBoxIcon]::Error
                                )
                            }
                        }
                    }
                }
                elseif ($script:btnTelemetryAction.Text -eq "Disable Timer") {
                    $idx = $script:listWakeTimers.SelectedIndex
                    if ($idx -ge 0 -and $idx -lt $script:listWakeTimers.Items.Count) {
                        $selectedItem = $script:listWakeTimers.Items[$idx].ToString()
                        if ($selectedItem -eq "No active wake timers.") { return }

                        if ($selectedItem -match 'NT TASK\\([^\''"]+)') {
                            $fullPath = $Matches[1]
                            $lastSlash = $fullPath.LastIndexOf('\')
                            if ($lastSlash -ge 0) {
                                $taskPath = '\' + $fullPath.Substring(0, $lastSlash) + '\'
                                $taskName = $fullPath.Substring($lastSlash + 1)
                            }
                            else {
                                $taskPath = '\'
                                $taskName = $fullPath
                            }

                            $confirm = Show-YesNoDialog `
                                -Title "Disable Timer Confirmation" `
                                -Message "Are you sure you want to disable the scheduled task:`r`n`"$taskPath$taskName`"?`r`n`r`nSAMISH will create a backup of this configuration before applying the change.`r`n`r`nTo restore this backup later, you can use the `"Verify & Restore Settings`" button on Page 1, or you will be prompted to restore it if you choose to uninstall SAMISH." `
                                -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning)

                            if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
                                try {
                                    Backup-ScheduledTaskState -TaskPath $taskPath -TaskName $taskName
                                    Disable-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction Stop | Out-Null
                                
                                    Write-SetupLog "Disabled scheduled task '$taskPath$taskName' (backup created)."
                                    $script:lblDiagDetail.Text = "Disabled task $taskName (Backup created)."
                                
                                    [void][System.Windows.Forms.MessageBox]::Show(
                                        "Successfully disabled scheduled task `"$taskPath$taskName`".`r`n`r`nA backup has been created in:`r`n`"$script:TaskWakeBackupPath`"",
                                        "SAMISH Telemetry Fix",
                                        [System.Windows.Forms.MessageBoxButtons]::OK,
                                        [System.Windows.Forms.MessageBoxIcon]::Information
                                    )

                                    $script:btnTelemetryRefresh.PerformClick()
                                }
                                catch {
                                    [void][System.Windows.Forms.MessageBox]::Show(
                                        "Failed to disable scheduled task `"$taskPath$taskName`":`r`n$($_.Exception.Message)",
                                        "Error",
                                        [System.Windows.Forms.MessageBoxButtons]::OK,
                                        [System.Windows.Forms.MessageBoxIcon]::Error
                                    )
                                }
                            }
                        }
                    }
                }
                elseif ($script:btnTelemetryAction.Text -eq "Disable Service") {
                    $idx = $script:listWakeTimers.SelectedIndex
                    if ($idx -ge 0 -and $idx -lt $script:listWakeTimers.Items.Count) {
                        $selectedItem = $script:listWakeTimers.Items[$idx].ToString()
                        if ($selectedItem -eq "No active wake timers.") { return }

                        $path = ""
                        $serviceHint = ""
                        if ($selectedItem -match '^Timer set by \[SERVICE\]\s+(.+?)(?:\s+expires at|$)') {
                            $rawPath = $Matches[1].Trim()
                            if ($rawPath -match '^(.+?\.exe)\s*\((.+?)\)$') {
                                $path = $Matches[1].Trim()
                                $serviceHint = $Matches[2].Trim()
                            }
                            else {
                                $path = $rawPath
                            }
                        }

                        if ($path) {
                            $fileName = [System.IO.Path]::GetFileName($path)
                            
                            $svc = $null
                            if ($serviceHint) {
                                $svc = if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
                                    Get-CimInstance Win32_Service | Where-Object { $_.Name -eq $serviceHint -or $_.DisplayName -eq $serviceHint } | Select-Object -First 1
                                } else {
                                    Get-WmiObject Win32_Service | Where-Object { $_.Name -eq $serviceHint -or $_.DisplayName -eq $serviceHint } | Select-Object -First 1
                                }
                            }
                            
                            if (-not $svc) {
                                $svc = if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
                                    Get-CimInstance Win32_Service | Where-Object { $_.PathName -like "*$fileName*" } | Select-Object -First 1
                                } else {
                                    Get-WmiObject Win32_Service | Where-Object { $_.PathName -like "*$fileName*" } | Select-Object -First 1
                                }
                            }

                            if ($svc) {
                                $confirm = Show-YesNoDialog `
                                    -Title "Disable Service Confirmation" `
                                    -Message "Are you sure you want to disable and stop the Windows Service:`r`n`"$($svc.DisplayName) ($($svc.Name))`"?`r`n`r`nThis service currently has an active wake timer set. SAMISH will create a backup of its configuration before disabling it.`r`n`r`nTo restore this backup later, you can use the `"Verify & Restore Settings`" button on Page 1, or you will be prompted to restore it if you choose to uninstall SAMISH." `
                                    -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning)

                                if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
                                    try {
                                        Backup-ServiceState -ServiceName $svc.Name -StartupType $svc.StartMode -State $svc.State

                                        Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction Stop
                                        Stop-Service -Name $svc.Name -Force -ErrorAction Stop

                                        Write-SetupLog "Disabled service '$($svc.Name)' (backup created)."
                                        $script:lblDiagDetail.Text = "Disabled service $($svc.Name) (Backup created)."

                                        [void][System.Windows.Forms.MessageBox]::Show(
                                            "Successfully disabled and stopped the service `"$($svc.DisplayName)`".`r`n`r`nA backup has been created in:`r`n`"$script:ServiceWakeBackupPath`"",
                                            "SAMISH Telemetry Fix",
                                            [System.Windows.Forms.MessageBoxButtons]::OK,
                                            [System.Windows.Forms.MessageBoxIcon]::Information
                                        )

                                        $script:btnTelemetryRefresh.PerformClick()
                                    }
                                    catch {
                                        [void][System.Windows.Forms.MessageBox]::Show(
                                            "Failed to disable the service `"$($svc.Name)`":`r`n$($_.Exception.Message)",
                                            "Error",
                                            [System.Windows.Forms.MessageBoxButtons]::OK,
                                            [System.Windows.Forms.MessageBoxIcon]::Error
                                        )
                                    }
                                }
                            }
                            else {
                                $displayTarget = if ($serviceHint) { "$fileName ($serviceHint)" } else { $fileName }
                                [void][System.Windows.Forms.MessageBox]::Show(
                                    "Could not resolve the Windows Service name automatically for:`r`n`"$displayTarget`"`r`n`r`nPlease manage this service manually via Windows Services (services.msc).",
                                    "Service Resolution Failed",
                                    [System.Windows.Forms.MessageBoxButtons]::OK,
                                    [System.Windows.Forms.MessageBoxIcon]::Warning
                                )
                            }
                        }
                    }
                }
                elseif ($script:btnTelemetryAction.Text -eq "Stop Process") {
                    $idx = $script:listWakeTimers.SelectedIndex
                    if ($idx -ge 0 -and $idx -lt $script:listWakeTimers.Items.Count) {
                        $selectedItem = $script:listWakeTimers.Items[$idx].ToString()
                        if ($selectedItem -eq "No active wake timers.") { return }

                        $path = ""
                        if ($selectedItem -match '^Timer set by \[PROCESS\]\s+(.+?)(?:\s+expires at|$)') {
                            $rawPath = $Matches[1].Trim()
                            if ($rawPath -match '^(.+?\.exe)\s*\((.+?)\)$') {
                                $path = $Matches[1].Trim()
                            }
                            else {
                                $path = $rawPath
                            }
                        }

                        if ($path) {
                            $fileName = [System.IO.Path]::GetFileName($path)
                            $procName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)

                            $confirm = Show-YesNoDialog `
                                -Title "Stop Process Confirmation" `
                                -Message "Are you sure you want to terminate the running process:`r`n`"$procName`"?`r`n`r`nThis process currently has an active wake timer set." `
                                -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning)

                            if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
                                try {
                                    Stop-Process -Name $procName -Force -ErrorAction Stop

                                    Write-SetupLog "Terminated process '$procName'."
                                    $script:lblDiagDetail.Text = "Terminated process $procName."

                                    [void][System.Windows.Forms.MessageBox]::Show(
                                        "Successfully terminated process `"$procName`".",
                                        "SAMISH Telemetry Fix",
                                        [System.Windows.Forms.MessageBoxButtons]::OK,
                                        [System.Windows.Forms.MessageBoxIcon]::Information
                                    )

                                    $script:btnTelemetryRefresh.PerformClick()
                                }
                                catch {
                                    [void][System.Windows.Forms.MessageBox]::Show(
                                        "Failed to terminate process `"$procName`":`r`n$($_.Exception.Message)",
                                        "Error",
                                        [System.Windows.Forms.MessageBoxButtons]::OK,
                                        [System.Windows.Forms.MessageBoxIcon]::Error
                                    )
                                }
                            }
                        }
                    }
                }
                elseif ($script:btnTelemetryAction.Text -eq "Toggle Suspend") {
                    $idx = $script:listHardwareScans.SelectedIndex
                    if ($idx -ge 0 -and $idx -lt $script:listHardwareScans.Items.Count) {
                        $selectedItem = $script:listHardwareScans.Items[$idx].ToString()
                        if ($selectedItem -match "^USB:\s*(.+)$") {
                            $hubName = $Matches[1]
                            $currentVal = Get-UsbSelectiveSuspend
                            if ($null -eq $currentVal) {
                                [void][System.Windows.Forms.MessageBox]::Show(
                                    "Failed to retrieve current USB Selective Suspend status from system power configuration.",
                                    "Error",
                                    [System.Windows.Forms.MessageBoxButtons]::OK,
                                    [System.Windows.Forms.MessageBoxIcon]::Error
                                )
                                return
                            }

                            $currentState = if ($currentVal -eq 1) { "Enabled" } else { "Disabled" }
                            $newState = if ($currentVal -eq 1) { "Disabled" } else { "Enabled" }
                            $newVal = if ($currentVal -eq 1) { 0 } else { 1 }

                            $confirm = Show-YesNoDialog `
                                -Title "Toggle USB Suspend Confirmation" `
                                -Message "USB Selective Suspend is currently $currentState.`r`n`r`nWould you like to change it to $newState now for device `"$hubName`"?`r`n`r`nSAMISH will create a backup of your power plan configuration before applying this change.`r`n`r`nTo restore this backup later, you can use the `"Verify & Restore Settings`" button on Page 1, or you will be prompted to restore it if you choose to uninstall SAMISH." `
                                -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning)

                            if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
                                try {
                                    Backup-UsbSuspendState
                                    powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 $newVal 2>$null | Out-Null
                                    powercfg /setactive SCHEME_CURRENT 2>$null | Out-Null
                                
                                    Write-SetupLog "Toggled USB selective suspend to $newState for device '$hubName' (backup created)."
                                    $script:lblDiagDetail.Text = "USB Suspend: $newState (Backup created)."
                                
                                    [void][System.Windows.Forms.MessageBox]::Show(
                                        "Successfully toggled USB Selective Suspend to $newState for device `"$hubName`".`r`n`r`nA backup of your previous setting ($currentState) has been merged into:`r`n`"$script:PowerPlanBackupPath`"",
                                        "SAMISH Telemetry Fix",
                                        [System.Windows.Forms.MessageBoxButtons]::OK,
                                        [System.Windows.Forms.MessageBoxIcon]::Information
                                    )

                                    $script:btnTelemetryRefresh.PerformClick()
                                }
                                catch {
                                    [void][System.Windows.Forms.MessageBox]::Show(
                                        "Failed to toggle USB Selective Suspend for device `"$hubName`":`r`n$($_.Exception.Message)",
                                        "Error",
                                        [System.Windows.Forms.MessageBoxButtons]::OK,
                                        [System.Windows.Forms.MessageBoxIcon]::Error
                                    )
                                }
                            }
                        }
                    }
                }
            })
    }

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

            # Other lists were just deselected but their handlers can't fire inside the mutex
            Set-ButtonVisualState -Button $script:btnDiagStopAuto -Active $false
            Set-ButtonVisualState -Button $script:btnDiagOpenLocation -Active $false
            Set-ButtonVisualState -Button $script:btnDiagRestore -Active $false

            $idx = $script:listBlockers.SelectedIndex
            $hasValidItem = ($idx -ge 0 -and $idx -lt $script:ActiveBlockersList.Count)

            Set-ButtonVisualState -Button $script:btnDiagAutomate -Active $false
            $script:btnDiagAutomate.Text = "Add to Automated Apps"
            Set-ButtonVisualState -Button $script:btnDiagIgnore -Active $false

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
                Set-ButtonVisualState -Button $script:btnDiagIgnore -Active $false

                # Check if already automated
                $alreadyAutomated = $false
                if ($script:MonitoredApps) {
                    $alreadyAutomated = [bool]($script:MonitoredApps | Where-Object { $_.ProcessName -eq $b.ProcessName })
                }

                if ($alreadyAutomated) {
                    Set-ButtonVisualState -Button $script:btnDiagAutomate -Active $false
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
                    Set-ButtonVisualState -Button $script:btnDiagAutomate -Active $true
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
                Set-ButtonVisualState -Button $script:btnDiagAutomate -Active $false
                $script:btnDiagAutomate.Text = "Add to Automated Apps"
                Set-ButtonVisualState -Button $script:btnDiagIgnore -Active $true
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

            # Other lists were just deselected but their handlers can't fire inside the mutex
            Set-ButtonVisualState -Button $script:btnDiagStopAuto -Active $false
            Set-ButtonVisualState -Button $script:btnDiagOpenLocation -Active $false
            Set-ButtonVisualState -Button $script:btnDiagAutomate -Active $false
            $script:btnDiagAutomate.Text = "Add to Automated Apps"
            Set-ButtonVisualState -Button $script:btnDiagIgnore -Active $false

            # Overridden system blockers cannot be automated; grey out the App Override Settings box
            Set-OperatingModeBoxState -Enabled $false

            $idx = $script:listOverrides.SelectedIndex
            $hasValidItem = ($idx -ge 0 -and $idx -lt $script:SystemOverridesList.Count)
            Set-ButtonVisualState -Button $script:btnDiagRestore -Active $hasValidItem
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

            # Other lists were just deselected but their handlers can't fire inside the mutex
            Set-ButtonVisualState -Button $script:btnDiagAutomate -Active $false
            $script:btnDiagAutomate.Text = "Add to Automated Apps"
            Set-ButtonVisualState -Button $script:btnDiagIgnore -Active $false
            Set-ButtonVisualState -Button $script:btnDiagRestore -Active $false

            $idx = $script:listAutomated.SelectedIndex
            $hasValidItem = ($idx -ge 0 -and $idx -lt $script:MonitoredApps.Count)
            Set-ButtonVisualState -Button $script:btnDiagStopAuto -Active $hasValidItem
            Set-ButtonVisualState -Button $script:btnDiagOpenLocation -Active $hasValidItem
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

                    if ($script:cbDiagAutoRecover) {
                        $autoRecVal = $false
                        if ($app.PSObject.Properties.Match('AutoRecover').Count -gt 0) {
                            $autoRecVal = [bool]$app.AutoRecover
                        }
                        $script:cbDiagAutoRecover.Checked = $autoRecVal
                    }
                }
                finally {
                    $script:diagSyncingControls = $false
                }
            }
            else {
                # Nothing selected - grey the box back out
                $script:diagSyncingControls = $true
                if ($script:cbDiagAutoRecover) { $script:cbDiagAutoRecover.Checked = $false }
                $script:diagSyncingControls = $false
                Set-OperatingModeBoxState -Enabled $false
            }
        })

    # Deselect automated app when clicking empty space in the list
    $script:listAutomated.add_MouseDown({
            param($sender, $e)
            $idx = $sender.IndexFromPoint($e.Location)
            if ($idx -lt 0) {
                $sender.ClearSelected()
            }
        })

    # Deselect blocker when clicking empty space in the list
    $script:listBlockers.add_MouseDown({
            param($sender, $e)
            $idx = $sender.IndexFromPoint($e.Location)
            if ($idx -lt 0) {
                $sender.ClearSelected()
            }
        })

    # Deselect override when clicking empty space in the list
    $script:listOverrides.add_MouseDown({
            param($sender, $e)
            $idx = $sender.IndexFromPoint($e.Location)
            if ($idx -lt 0) {
                $sender.ClearSelected()
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

            Set-ButtonVisualState -Button $script:btnDiagAutomate -Active $false
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

            $msg = "Windows will be told to ignore power requests from:`r`n  $($b.DisplayName) [$($b.BlockerType)]`r`n`r`nThis blocker will no longer prevent sleep or hibernation.`r`n`r`nYou can undo this at any time using the 'Remove System Override' button under the Ignored Blockers list.`r`n`r`nContinue?"

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

        # Refresh test button tooltips and visual state to reflect the new mode
        if (Get-Command Update-TestButtonsTooltips -ErrorAction SilentlyContinue) {
            Update-TestButtonsTooltips
        }
    }

    if ($script:rbDiagGraceful) { $script:rbDiagGraceful.add_CheckedChanged($saveRecoveryMode) }
    if ($script:rbDiagClassic) { $script:rbDiagClassic.add_CheckedChanged($saveRecoveryMode) }
    if ($script:rbDiagPauseMedia) { $script:rbDiagPauseMedia.add_CheckedChanged($saveRecoveryMode) }

    if ($script:cbDiagAutoRecover) {
        $script:cbDiagAutoRecover.add_CheckedChanged({
                if ($script:diagSyncingControls) { return }

                $idx = $script:listAutomated.SelectedIndex
                if ($idx -lt 0 -or $idx -ge $script:MonitoredApps.Count) {
                    $script:diagSyncingControls = $true
                    $script:cbDiagAutoRecover.Checked = $false
                    $script:diagSyncingControls = $false
                    return
                }

                $app = $script:MonitoredApps[$idx]
                $autoRecVal = $script:cbDiagAutoRecover.Checked
                if ($app.PSObject.Properties.Match('AutoRecover').Count -gt 0) {
                    if ($app.AutoRecover -eq $autoRecVal) { return }
                    $app.AutoRecover = $autoRecVal
                }
                else {
                    $app | Add-Member -MemberType NoteProperty -Name "AutoRecover" -Value $autoRecVal -Force
                }
                $script:MonitoredApps[$idx] = $app
                Save-MonitoredAppsToConfig
            
                $statusMsg = if ($autoRecVal) { "Enabled Monitor & Auto-Relaunch" } else { "Disabled Monitor & Auto-Relaunch" }
                Flash-DiagnosticsStatus "$statusMsg for $($app.ProcessName)."
            })
    }

    if ($script:cbAutoRecovery) {
        $script:cbAutoRecovery.add_CheckedChanged({
                Ensure-InstallFolder
                try {
                    $cfg = @{}
                    if (Test-Path -LiteralPath $ConfigPath) {
                        $cfg = (Get-Content -LiteralPath $ConfigPath -Raw) | ConvertFrom-Json
                    }
                    $cfg.EnableAutoRecovery = [bool]$script:cbAutoRecovery.Checked
                    $json = $cfg | ConvertTo-Json -Depth 6
                    if (Get-Command Save-ContentAtomic -ErrorAction SilentlyContinue) {
                        Save-ContentAtomic -Path $ConfigPath -Content $json
                    }
                    else {
                        Set-Content -LiteralPath $ConfigPath -Value $json -Encoding UTF8
                    }
                }
                catch {}
            })
    }

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

                # Refresh test button styling and tooltip to reflect the new wake action
                try {
                    if (Get-Command Update-TestButtonsTooltips -ErrorAction SilentlyContinue) {
                        Update-TestButtonsTooltips
                    }
                } catch {}
            })
    }
}

# Operating Mode Tests -- Event Wiring
# Extracted to Events.DiagnosticsTests.ps1 for file size reduction.
# Contains: Resolve-TestTarget, Update-TestButtonsTooltips, Update-TestGroupState,
#           and all btnTestSleep/btnTestHibernate/btnTestStop event handlers.
$DiagTestsPath = Join-Path $PSScriptRoot "Events.DiagnosticsTests.ps1"
if (Test-Path -LiteralPath $DiagTestsPath) {
    . $DiagTestsPath
}

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




$script:btnTelemetryRefresh.add_Click({
        # ---- System telemetry panel ----
        if ($script:lblTelemetryStates) { $script:lblTelemetryStates.Text = "Querying system telemetry..." }
        if ($script:txtLastWake) { $script:txtLastWake.Text = "" }
        if ($script:listWakeTimers) { $script:listWakeTimers.Items.Clear() }
        if ($script:listArmedDevices) { $script:listArmedDevices.Items.Clear() }
        if ($script:listHardwareScans) { 
            $script:listHardwareScans.Items.Clear()
            $script:listHardwareScans.Items.Add("Running deep WMI hardware scan...") | Out-Null
        }

        try {
            $diag = Get-SystemPowerDiagnostics

            # --- Sleep/Wake History ---
            if ($diag.SleepHistory -and $diag.SleepHistory.Count -gt 0) {
                $tableText = "Wake Time   Duration  Wake Source`r`n"
                $tableText += "---------   --------  -----------`r`n"
                foreach ($h in $diag.SleepHistory) {
                    $formattedTime = "Unknown"
                    if ($h.WakeTime) {
                        try {
                            $dt = [DateTime]::Parse($h.WakeTime)
                            $formattedTime = $dt.ToString("MM-dd HH:mm")
                        }
                        catch { $formattedTime = $h.WakeTime }
                    }
                    $c1 = $formattedTime.PadRight(12).Substring(0, 12)
                    $c2 = $h.Duration.PadRight(10).Substring(0, 10)
                    $c3 = $h.WakeSource
                    $tableText += "$c1$c2$c3`r`n"
                }
                if ($script:txtLastWake) { $script:txtLastWake.Text = $tableText.TrimEnd() }
            }
            elseif ($script:txtLastWake) {
                $script:txtLastWake.Text = $diag.LastWake
            }

            # --- Wake Timers ---
            if ($script:listWakeTimers) {
                if ($diag.WakeTimers.Count -gt 0) {
                    foreach ($timer in $diag.WakeTimers) {
                        $script:listWakeTimers.Items.Add($timer) | Out-Null
                    }
                }
                else {
                    $script:listWakeTimers.Items.Add("No active wake timers.") | Out-Null
                }
            }

            # --- Armed Devices (Hardware panel) ---
            if ($script:listArmedDevices) {
                if ($diag.ArmedDevices.Count -gt 0) {
                    foreach ($dev in $diag.ArmedDevices) {
                        $script:listArmedDevices.Items.Add($dev) | Out-Null
                    }
                }
                else {
                    $script:listArmedDevices.Items.Add("No devices armed to wake the system.") | Out-Null
                }
            }

            # --- Sleep States banner ---
            if ($script:lblTelemetryStates) {
                $script:lblTelemetryStates.Text = "Supported Sleep States: " + ($diag.SleepSupport -join ", ")
            }

            # --- Deep WMI Hardware Scan (USB / PCIe power states) ---
            if ($script:listHardwareScans) {
                $script:listHardwareScans.Items.Clear()
                try {
                    $usbLines = @()
                    $pciLines = @()

                    $usbHubs = Get-WmiObject -Namespace "root\cimv2" -Class "Win32_USBHub" -ErrorAction SilentlyContinue
                    if ($usbHubs) {
                        foreach ($hub in $usbHubs) {
                            $label = if ($hub.Name) { $hub.Name } else { "USB Hub" }
                            $usbLines += "USB: $label"
                        }
                    }

                    $pciDevices = Get-WmiObject -Namespace "root\cimv2" -Class "Win32_PnPEntity" -Filter "ConfigManagerErrorCode=0" -ErrorAction SilentlyContinue |
                    Where-Object { $_.PNPDeviceID -like "PCI\*" } |
                    Select-Object -First 10
                    if ($pciDevices) {
                        foreach ($dev in $pciDevices) {
                            $label = if ($dev.Name) { $dev.Name } else { "PCIe Device" }
                            $pciLines += "PCIe: $label"
                        }
                    }

                    $allLines = @()
                    if ($usbLines.Count -gt 0) { $allLines += $usbLines }
                    if ($pciLines.Count -gt 0) { $allLines += $pciLines }
                    if ($allLines.Count -eq 0) { $allLines += "No USB/PCIe devices detected via WMI." }

                    foreach ($line in $allLines) {
                        $script:listHardwareScans.Items.Add($line) | Out-Null
                    }
                }
                catch {
                    $script:listHardwareScans.Items.Add("WMI scan failed: $($_.Exception.Message)") | Out-Null
                }
            }
        }
        catch {
            if ($script:lblTelemetryStates) { $script:lblTelemetryStates.Text = "Failed to query telemetry: $($_.Exception.Message)" }
        }
    })

# Backup/restore functions (Backup-DeviceWakeState, Restore-DeviceWakeFromBackup, etc.)
# are defined in ConfigBackup.Module.ps1 (loaded earlier via Events-handlers.ps1).

# ---------- Active Sleep Blocker Auto-Refresh Timer ----------
$script:TelemetryAutoRefreshIntervalSec = 10
$script:ActiveBlockerTimer = $null

$form.add_Shown({
        if ($null -eq $script:ActiveBlockerTimer) {
            $script:ActiveBlockerTimer = New-Object System.Windows.Forms.Timer
            $script:ActiveBlockerTimer.Interval = $script:TelemetryAutoRefreshIntervalSec * 1000
            $script:ActiveBlockerTimer.add_Tick({
                    # Only run if we are on the Diagnostics tab (SelectedIndex -eq 1)
                    if ($script:tabControl.SelectedIndex -ne 1) { return }

                    # Only run if no scan is currently in progress
                    if ($null -ne $script:DiagTimer) { return }

                    # Only run if the user has no selection in listBlockers, listOverrides, or listAutomated
                    if ($script:listBlockers.SelectedIndex -ne -1 -or
                        $script:listOverrides.SelectedIndex -ne -1 -or
                        $script:listAutomated.SelectedIndex -ne -1) {
                        return
                    }

                    # Trigger the scan asynchronously and silently
                    Update-SleepDiagnosticsListsAsync -Silent
                })
            $script:ActiveBlockerTimer.Start()
        }
    })


