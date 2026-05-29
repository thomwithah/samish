# ---------- UI.DiagTab.ps1 ----------
# ---------- Operating Mode Tests ----------
# GroupBox is always Enabled so the tooltip is accessible even when children
# are disabled. ForeColor is managed dynamically by Update-TestGroupState.
$testGroup = New-Object System.Windows.Forms.GroupBox
$testGroup.Text = "Operating Mode Tests"
$testGroup.Font = $font
$testGroup.ForeColor = [System.Drawing.Color]::Gray   # greyed until enabled
$testGroup.Size = New-Object System.Drawing.Size($totalWidth, 115)
$testGroup.Location = New-Object System.Drawing.Point(18, 0)   # Place-Below will set Y
$form.Controls.Add($testGroup)
$testGroup.Visible = $false   # v1.1.0: Test controls live on Page 2; hide from base form layer

$tooltip.SetToolTip($testGroup,
    "Test how SAMISH will close and restart your device software or an automated app before sleep occurs.

Select a target from the dropdown, then use the buttons to run a live test.

Tests apply to either the selected device software (from Device Settings) or any app configured in Sleep and Hibernate Diagnostics, but only one at a time.

Test Start verifies the app can be relaunched after a stop test, reproducing what SAMISH does when your system wakes from sleep or hibernate.

This section is available when your device software is running, SAMISH is installed, or automated apps are configured.")

# ----- Test Target label and dropdown -----
$lblTestTarget = New-Object System.Windows.Forms.Label
$lblTestTarget.Text = "Test target:"
$lblTestTarget.AutoSize = $true
$lblTestTarget.Location = New-Object System.Drawing.Point(15, 30)
$testGroup.Controls.Add($lblTestTarget)

$script:ddTestTarget = New-Object System.Windows.Forms.ComboBox
$script:ddTestTarget.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$script:ddTestTarget.Width = 300
$script:ddTestTarget.Location = New-Object System.Drawing.Point(100, 26)
$script:ddTestTarget.Enabled = $false
$testGroup.Controls.Add($script:ddTestTarget)

$tooltip.SetToolTip($script:ddTestTarget,
    "Select which app to test. Device Software refers to the mixer managed by your selected profile. Automated App entries come from apps configured in Sleep and Hibernate Diagnostics.")

# ----- Test buttons -----
$script:btnTestGraceful = New-Object System.Windows.Forms.Button
$script:btnTestGraceful.Text = "Test Graceful"
$script:btnTestGraceful.Font = $font
$script:btnTestGraceful.Size = New-Object System.Drawing.Size(112, 30)
$script:btnTestGraceful.Location = New-Object System.Drawing.Point(15, 70)
$script:btnTestGraceful.Enabled = $true
$testGroup.Controls.Add($script:btnTestGraceful)

$tooltip.SetToolTip($script:btnTestGraceful,
    "Test whether SAMISH can ask this app to close cleanly. Graceful shutdown is safer for unsaved work but may occasionally fail if the app is unresponsive.")

$script:btnTestClassic = New-Object System.Windows.Forms.Button
$script:btnTestClassic.Text = "Test Classic"
$script:btnTestClassic.Font = $font
$script:btnTestClassic.Size = New-Object System.Drawing.Size(112, 30)
$script:btnTestClassic.Location = New-Object System.Drawing.Point(137, 70)
$script:btnTestClassic.Enabled = $true
$testGroup.Controls.Add($script:btnTestClassic)

$tooltip.SetToolTip($script:btnTestClassic,
    "Test whether SAMISH can force-close this app immediately. More reliable than Graceful, but any unsaved work in that app may be lost.")

$script:btnTestStart = New-Object System.Windows.Forms.Button
$script:btnTestStart.Text = "Start Test"
$script:btnTestStart.Font = $font
$script:btnTestStart.Size = New-Object System.Drawing.Size(102, 30)
$script:btnTestStart.Location = New-Object System.Drawing.Point(298, 70)
$script:btnTestStart.Enabled = $true
$testGroup.Controls.Add($script:btnTestStart)

$tooltip.SetToolTip($script:btnTestStart,
    "Test whether SAMISH can relaunch this application or resume its media playback based on its configured wake action.")

$script:btnTestStop = New-Object System.Windows.Forms.Button
$script:btnTestStop.Text = "Stop Test"
$script:btnTestStop.Font = $font
$script:btnTestStop.Size = New-Object System.Drawing.Size(102, 30)
$script:btnTestStop.Location = New-Object System.Drawing.Point(410, 70)
$script:btnTestStop.Enabled = $true
$testGroup.Controls.Add($script:btnTestStop)

$tooltip.SetToolTip($script:btnTestStop,
    "Test whether SAMISH can close this application or pause its media playback based on its configured sleep action.")

# ----- Store top-level reference for event handlers -----
$script:testGroup = $testGroup

# ---- Update-TestGroupState -------------------------------------------
# Evaluates whether the test box should be enabled based on three conditions:
#   1. SAMISH scheduled task is installed
#   2. The selected profile's device software is currently running
#   3. One or more apps are configured for automation in Sleep Diagnostics
# Also rebuilds the target dropdown. Called on load, profile switch, and
# whenever MonitoredApps changes.
function Update-TestGroupState {

    # --- Evaluate activation conditions ---
    $isInstalled = $false
    $deviceRunning = $false
    $hasAutomated = ($script:MonitoredApps -and $script:MonitoredApps.Count -gt 0)

    try { $isInstalled = Test-SamishInstalled } catch {}

    # Resolve the process name from the active profile
    $profileProcName = $null
    try {
        if ($script:ProfileMetaById -and
            $script:ProfileMetaById.ContainsKey($script:ActiveProfileId)) {
            $meta = $script:ProfileMetaById[$script:ActiveProfileId]
            if ($meta.Raw.targets -and $meta.Raw.targets.Count -gt 0) {
                $profileProcName = [string]$meta.Raw.targets[0].processName
            }
        }
    }
    catch {}

    if ($profileProcName) {
        try {
            $deviceRunning = ($null -ne (Get-Process -Name $profileProcName -ErrorAction SilentlyContinue | Select-Object -First 1))
        }
        catch {}
    }

    $shouldEnable = ($isInstalled -or $hasAutomated -or $deviceRunning)

    # --- Enable or disable child controls ---
    foreach ($ctrl in $script:testGroup.Controls) {
        if ($ctrl -ne $script:btnTestStop -and $ctrl -ne $script:btnTestStart -and $ctrl -ne $script:btnTestGraceful -and $ctrl -ne $script:btnTestClassic) {
            if ($ctrl -is [System.Windows.Forms.ComboBox]) {
                try {
                    if ($script:testDropdownFallback) {
                        $ctrl.Enabled = $shouldEnable
                    }
                    else {
                        $ctrl.Enabled = $true
                        $script:testDropdownActive = $shouldEnable
                    }
                }
                catch {
                    $script:testDropdownFallback = $true
                    try { $ctrl.Enabled = $shouldEnable } catch {}
                }
                # Apply theme-appropriate active/inactive colors to maintain flat border thickness consistency
                if ($global:ThemeNeonActive) {
                    $ctrl.BackColor = if ($shouldEnable) { [System.Drawing.Color]::FromArgb(25, 25, 30) } else { [System.Drawing.Color]::FromArgb(45, 45, 50) }
                    $ctrl.ForeColor = if ($shouldEnable) { if ($global:NeonCyan) { $global:NeonCyan } else { [System.Drawing.Color]::FromArgb(0, 245, 212) } } else { [System.Drawing.Color]::Gray }
                }
                else {
                    if ($shouldEnable) {
                        $ctrl.ResetBackColor()
                        $ctrl.ResetForeColor()
                    }
                    else {
                        $ctrl.BackColor = [System.Drawing.SystemColors]::Control
                        $ctrl.ForeColor = [System.Drawing.SystemColors]::GrayText
                    }
                }
            }
            else {
                $ctrl.Enabled = $shouldEnable
            }
        }
    }

    # --- Update GroupBox title color (flash when enabling, grey when disabling) ---
    if ($shouldEnable) {
        # Kill any previous flash timer to prevent race conditions
        if ($script:testGroupFlashTimer) {
            try { $script:testGroupFlashTimer.Stop(); $script:testGroupFlashTimer.Dispose() } catch {}
            $script:testGroupFlashTimer = $null
        }

        # Determine colors safely
        $color1 = if ($global:ThemeNeonActive) { $global:NeonCyan } else { $BrandCyan }
        if ($null -eq $color1) { $color1 = [System.Drawing.Color]::FromArgb(0, 215, 255) }
        $color2 = if ($global:ThemeNeonActive) { $global:NeonPink } else { [System.Drawing.SystemColors]::ControlText }
        if ($null -eq $color2) { $color2 = [System.Drawing.Color]::Black }

        # Triple-flash: Cyan -> final color (6 ticks at 180ms each)
        $script:testGroup.ForeColor = $color1
        try { $script:testGroup.Refresh() } catch {}
        $script:testGroupFlashTick = 0
        $script:testGroupFlashTimer = New-Object System.Windows.Forms.Timer
        $script:testGroupFlashTimer.Interval = 180
        $script:testGroupFlashTimer.Tag = [PSCustomObject]@{
            Color1 = $color1
            Color2 = $color2
        }
        $script:testGroupFlashTimer.add_Tick({
                param($sender, $e)
                $script:testGroupFlashTick++
                $colors = $sender.Tag
                if ($script:testGroupFlashTick % 2 -eq 0) {
                    $script:testGroup.ForeColor = $colors.Color1
                }
                else {
                    $script:testGroup.ForeColor = $colors.Color2
                }
                if ($script:testGroupFlashTick -ge 5) {
                    $script:testGroup.ForeColor = $colors.Color2
                    try {
                        if ($script:testGroupFlashTimer) {
                            $script:testGroupFlashTimer.Stop()
                            $script:testGroupFlashTimer.Dispose()
                            $script:testGroupFlashTimer = $null
                        }
                    }
                    catch {}
                }
            })
        $script:testGroupFlashTimer.Start()
    }
    else {
        # Kill any running flash timer when disabling
        if ($script:testGroupFlashTimer) {
            try { $script:testGroupFlashTimer.Stop(); $script:testGroupFlashTimer.Dispose() } catch {}
            $script:testGroupFlashTimer = $null
        }
        $script:testGroup.ForeColor = if ($global:ThemeNeonActive) { if ($global:NeonPink) { $global:NeonPink } else { [System.Drawing.Color]::FromArgb(255, 0, 102) } } else { [System.Drawing.Color]::Gray }
    }

    # --- Rebuild the target dropdown ---
    $script:ddTestTarget.Items.Clear()

    # Always add device software entry (even if not currently running)
    $displayProfileName = $script:ActiveProfileId
    try {
        if ($script:ProfileMetaById -and $script:ProfileMetaById.ContainsKey($script:ActiveProfileId)) {
            $displayProfileName = $script:ProfileMetaById[$script:ActiveProfileId].DisplayName
        }
    }
    catch {}
    $script:ddTestTarget.Items.Add("Device Software: $displayProfileName") | Out-Null

    # Add one entry per automated app
    if ($script:MonitoredApps) {
        foreach ($app in $script:MonitoredApps) {
            if ($app -and $app.ProcessName) {
                $script:ddTestTarget.Items.Add("Automated App: $($app.ProcessName)") | Out-Null
            }
        }
    }

    if ($script:ddTestTarget.Items.Count -gt 0) {
        $script:ddTestTarget.SelectedIndex = 0
    }

    # Refresh tooltips dynamically if the tooltip function exists
    if (Get-Command Update-TestButtonsTooltips -ErrorAction SilentlyContinue) {
        try { Update-TestButtonsTooltips } catch {}
    }
}


# 4. Page 2: Sleep & Hibernate Diagnostics
$grpBlockers = New-Object System.Windows.Forms.GroupBox
$grpBlockers.Text = "Active Blockers"
$grpBlockers.Size = New-Object System.Drawing.Size(370, 200)
$grpBlockers.Location = New-Object System.Drawing.Point(10, 10)
$tabPage2.Controls.Add($grpBlockers)
$tooltip.SetToolTip($grpBlockers, "System processes, services, or drivers currently blocking Windows from sleep or hibernate.")

$listBlockers = New-Object System.Windows.Forms.ListBox
$listBlockers.Size = New-Object System.Drawing.Size(350, 90)
$listBlockers.Location = New-Object System.Drawing.Point(10, 22)
$listBlockers.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
$listBlockers.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 250)
$grpBlockers.Controls.Add($listBlockers)
$script:listBlockers = $listBlockers

$btnDiagAutomate = New-Object System.Windows.Forms.Button
$btnDiagAutomate.Text = "Add to Automated Apps"
$btnDiagAutomate.Font = $font
$btnDiagAutomate.Size = New-Object System.Drawing.Size(350, 32)
$btnDiagAutomate.Location = New-Object System.Drawing.Point(10, 118)
$btnDiagAutomate.Enabled = $false
$btnDiagAutomate.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnDiagAutomate.FlatAppearance.BorderSize = 1
$btnDiagAutomate.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$btnDiagAutomate.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnDiagAutomate.BackColor = [System.Drawing.Color]::Transparent
$btnDiagAutomate.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$grpBlockers.Controls.Add($btnDiagAutomate)
$script:btnDiagAutomate = $btnDiagAutomate
$tooltip.SetToolTip($btnDiagAutomate, "Configure SAMISH to automatically manage this application before sleep or hibernation, and restart it when the system wakes.")

$lblBlockerHint = New-Object System.Windows.Forms.Label
$lblBlockerHint.Text = "Tip: To discover and automate a browser/media app, open it and play media, then click Scan."
$lblBlockerHint.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
$lblBlockerHint.ForeColor = [System.Drawing.Color]::DimGray
$lblBlockerHint.Size = New-Object System.Drawing.Size(350, 36)
$lblBlockerHint.Location = New-Object System.Drawing.Point(10, 154)
$grpBlockers.Controls.Add($lblBlockerHint)
$tooltip.SetToolTip($lblBlockerHint, "To configure a browser or media app for SAMISH management:`n1. Open the application (e.g., Spotify, Chrome) and play media to generate an active audio wake-lock.`n2. Click 'Scan Blockers' to discover the application in the Active Blockers list.`n3. Select the application and click 'Add to Automated Apps' to automate it.")

$grpOverrides = New-Object System.Windows.Forms.GroupBox
$grpOverrides.Text = "Ignored Blockers"
$grpOverrides.Size = New-Object System.Drawing.Size(370, 175)
$grpOverrides.Location = New-Object System.Drawing.Point(10, 220)
$tabPage2.Controls.Add($grpOverrides)
$tooltip.SetToolTip($grpOverrides, "Configured system overrides to let Windows ignore specific sleep blockers.")

$listOverrides = New-Object System.Windows.Forms.ListBox
$listOverrides.Size = New-Object System.Drawing.Size(350, 105)
$listOverrides.Location = New-Object System.Drawing.Point(10, 22)
$listOverrides.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
$listOverrides.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 250)
$grpOverrides.Controls.Add($listOverrides)
$script:listOverrides = $listOverrides

$btnDiagRestore = New-Object System.Windows.Forms.Button
$btnDiagRestore.Text = "Remove System Override"
$btnDiagRestore.Size = New-Object System.Drawing.Size(350, 32)
$btnDiagRestore.Location = New-Object System.Drawing.Point(10, 134)
$btnDiagRestore.Enabled = $false
$btnDiagRestore.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnDiagRestore.FlatAppearance.BorderSize = 1
$btnDiagRestore.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$btnDiagRestore.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnDiagRestore.BackColor = [System.Drawing.Color]::Transparent
$btnDiagRestore.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$grpOverrides.Controls.Add($btnDiagRestore)
$script:btnDiagRestore = $btnDiagRestore
$tooltip.SetToolTip($btnDiagRestore, "Remove the override and let this item's power requests once again affect sleep and hibernation behaviour.")

$btnDiagScan = New-Object System.Windows.Forms.Button
$btnDiagScan.Name = "btnDiagScan"
$btnDiagScan.Text = "Scan Blockers"
$btnDiagScan.Font = $font
$btnDiagScan.Size = New-Object System.Drawing.Size(112, 36)
$btnDiagScan.Location = New-Object System.Drawing.Point(10, 410)
$btnDiagScan.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnDiagScan.FlatAppearance.BorderSize = 1
$btnDiagScan.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$btnDiagScan.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnDiagScan.BackColor = [System.Drawing.Color]::Transparent
$btnDiagScan.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$tabPage2.Controls.Add($btnDiagScan)
$script:btnDiagScan = $btnDiagScan
$tooltip.SetToolTip($btnDiagScan, "Scan Windows for all active power requests currently preventing sleep or hibernation.")

$btnDiagIgnore = New-Object System.Windows.Forms.Button
$btnDiagIgnore.Name = "btnDiagIgnore"
$btnDiagIgnore.Text = "Ignore Blocker"
$btnDiagIgnore.Font = $font
$btnDiagIgnore.Size = New-Object System.Drawing.Size(248, 36)
$btnDiagIgnore.Location = New-Object System.Drawing.Point(132, 410)
$btnDiagIgnore.Enabled = $false
$btnDiagIgnore.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnDiagIgnore.FlatAppearance.BorderSize = 1
$btnDiagIgnore.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$btnDiagIgnore.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnDiagIgnore.BackColor = [System.Drawing.Color]::Transparent
$btnDiagIgnore.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$tabPage2.Controls.Add($btnDiagIgnore)
$script:btnDiagIgnore = $btnDiagIgnore
$tooltip.SetToolTip($btnDiagIgnore, "Tell Windows to ignore this blocker's power request so it no longer prevents sleep or hibernation.")
# Right Column
$grpAutomated = New-Object System.Windows.Forms.GroupBox
$grpAutomated.Text = "SAMISH Automated Apps"
$grpAutomated.Size = New-Object System.Drawing.Size(370, 200)
$grpAutomated.Location = New-Object System.Drawing.Point(395, 10)
$tabPage2.Controls.Add($grpAutomated)
$tooltip.SetToolTip($grpAutomated, "Applications automated by SAMISH to be closed before sleep and restarted on wake.")

$listAutomated = New-Object System.Windows.Forms.ListBox
$listAutomated.Size = New-Object System.Drawing.Size(350, 100)
$listAutomated.Location = New-Object System.Drawing.Point(10, 22)
$listAutomated.IntegralHeight = $false
$listAutomated.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
$listAutomated.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 250)
$grpAutomated.Controls.Add($listAutomated)
$script:listAutomated = $listAutomated
 
$btnDiagStopAuto = New-Object System.Windows.Forms.Button
$btnDiagStopAuto.Text = "Deactivate Automation"
$btnDiagStopAuto.Font = $font
$btnDiagStopAuto.Size = New-Object System.Drawing.Size(170, 32)
$btnDiagStopAuto.Location = New-Object System.Drawing.Point(10, 159)
$btnDiagStopAuto.Enabled = $false
$btnDiagStopAuto.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnDiagStopAuto.FlatAppearance.BorderSize = 1
$btnDiagStopAuto.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$btnDiagStopAuto.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnDiagStopAuto.BackColor = [System.Drawing.Color]::Transparent
$btnDiagStopAuto.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$grpAutomated.Controls.Add($btnDiagStopAuto)
$script:btnDiagStopAuto = $btnDiagStopAuto
$tooltip.SetToolTip($btnDiagStopAuto, "Remove this application from SAMISH automation.")
 
$btnDiagOpenLocation = New-Object System.Windows.Forms.Button
$btnDiagOpenLocation.Text = "Open Installation Folder"
$btnDiagOpenLocation.Font = $font
$btnDiagOpenLocation.Size = New-Object System.Drawing.Size(170, 32)
$btnDiagOpenLocation.Location = New-Object System.Drawing.Point(190, 159)
$btnDiagOpenLocation.Enabled = $false
$btnDiagOpenLocation.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnDiagOpenLocation.FlatAppearance.BorderSize = 1
$btnDiagOpenLocation.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$btnDiagOpenLocation.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnDiagOpenLocation.BackColor = [System.Drawing.Color]::Transparent
$btnDiagOpenLocation.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$grpAutomated.Controls.Add($btnDiagOpenLocation)
$script:btnDiagOpenLocation = $btnDiagOpenLocation
$tooltip.SetToolTip($btnDiagOpenLocation, "Open the installation folder for this application in Windows File Explorer.")

$grpOperatingMode = New-Object System.Windows.Forms.GroupBox
$grpOperatingMode.Text = "App Override Settings"
$grpOperatingMode.Size = New-Object System.Drawing.Size(370, 175)
$grpOperatingMode.Location = New-Object System.Drawing.Point(395, 220)
$tabPage2.Controls.Add($grpOperatingMode)
$tooltip.SetToolTip($grpOperatingMode, "Configure operating mode and wake actions for the selected automated application.")

$lblBeforeSleep = New-Object System.Windows.Forms.Label
$lblBeforeSleep.Text = "Before Sleep/Hibernate:"
$lblBeforeSleep.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblBeforeSleep.ForeColor = $BrandPurple
$lblBeforeSleep.AutoSize = $true
$lblBeforeSleep.Location = New-Object System.Drawing.Point(10, 20)
$grpOperatingMode.Controls.Add($lblBeforeSleep)

$rbGraceful = New-Object System.Windows.Forms.RadioButton
$rbGraceful.Text = "Close App (Graceful)"
$rbGraceful.AutoSize = $true
$rbGraceful.Location = New-Object System.Drawing.Point(10, 42)
$grpOperatingMode.Controls.Add($rbGraceful)
$script:rbDiagGraceful = $rbGraceful
$tooltip.SetToolTip($rbGraceful, "Graceful: Asks the application to close itself cleanly before sleep or hibernation, allowing it to save open files.")

$rbClassic = New-Object System.Windows.Forms.RadioButton
$rbClassic.Text = "Close App (Classic)"
$rbClassic.AutoSize = $true
$rbClassic.Location = New-Object System.Drawing.Point(10, 66)
$grpOperatingMode.Controls.Add($rbClassic)
$script:rbDiagClassic = $rbClassic
$tooltip.SetToolTip($rbClassic, "Classic: Immediately terminates the application before sleep or hibernation. More reliable, but unsaved work may be lost.")

$rbPauseMedia = New-Object System.Windows.Forms.RadioButton
$rbPauseMedia.Text = "Keep App Open (Media Control)"
$rbPauseMedia.AutoSize = $true
$rbPauseMedia.Location = New-Object System.Drawing.Point(10, 90)
$grpOperatingMode.Controls.Add($rbPauseMedia)
$script:rbDiagPauseMedia = $rbPauseMedia
$tooltip.SetToolTip($rbPauseMedia, "Keep App Open: Pauses the application's media playback (via Windows SMTC) before sleep or hibernation instead of closing the application. This is ideal for web browsers to prevent losing open tabs.")

$cbDiagAutoRecover = New-Object System.Windows.Forms.CheckBox
$cbDiagAutoRecover.Text = "Monitor & Auto-Relaunch"
$cbDiagAutoRecover.AutoSize = $true
$cbDiagAutoRecover.Location = New-Object System.Drawing.Point(185, 66)
$grpOperatingMode.Controls.Add($cbDiagAutoRecover)
$script:cbDiagAutoRecover = $cbDiagAutoRecover
$tooltip.SetToolTip($cbDiagAutoRecover, "Actively monitors this application while the PC is awake, automatically relaunching it and restoring its state if it crashes or exits unexpectedly.")

$lblOnWake = New-Object System.Windows.Forms.Label
$lblOnWake.Text = "On Wake/Resume:"
$lblOnWake.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblOnWake.ForeColor = $BrandPurple
$lblOnWake.AutoSize = $true
$lblOnWake.Location = New-Object System.Drawing.Point(10, 118)
$grpOperatingMode.Controls.Add($lblOnWake)
$tooltip.SetToolTip($lblOnWake, "Choose what action SAMISH will perform when the system wakes: Smart Restore restores the pre-sleep state; Always Play forces playback; Always Pause keeps media paused; Keep Closed prevents app restart; Reopen Only restarts the app but keeps media paused.")

$ddOnWakeAction = New-Object System.Windows.Forms.ComboBox
$ddOnWakeAction.Name = "ddOnWakeAction"
$ddOnWakeAction.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$ddOnWakeAction.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
$ddOnWakeAction.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$ddOnWakeAction.Size = New-Object System.Drawing.Size(330, 24)
$ddOnWakeAction.Location = New-Object System.Drawing.Point(10, 145)
$ddOnWakeAction.Items.Add("- Select App -") | Out-Null
$ddOnWakeAction.SelectedIndex = 0
$grpOperatingMode.Controls.Add($ddOnWakeAction)
$script:ddDiagOnWakeAction = $ddOnWakeAction
$script:pnlDiagOnWakeBorder = $null
$tooltip.SetToolTip($ddOnWakeAction, "Choose what action SAMISH will perform when the system wakes.")

# Wake-dropdown interaction state.
# We keep ddOnWakeAction.Enabled=$true permanently so the OS never renders the
# "disabled" chrome (which causes a thicker/lighter border in neon mode).
# A flag + SelectionChangeCommitted hook guards against unintended interaction.
$script:wakeDropdownActive = $false   # true when an automated app is selected
$script:wakeDropdownFallback = $false   # true if hook registration fails; reverts to Enabled toggling

try {
    $ddOnWakeAction.add_SelectionChangeCommitted({
            try {
                if (-not $script:wakeDropdownActive) {
                    # Revert any selection made while the dropdown is logically inactive
                    $script:ddDiagOnWakeAction.SelectedIndex = 0
                }
            }
            catch {
                $errPath = if ($global:PackageDir) { "$global:PackageDir\SAMISH_ERROR.txt" } else { "C:\Scripts\GOOGLE-ANTI-GRAVITY\SAMISH\SAMISH_ERROR.txt" }
                Out-File -FilePath $errPath -Append `
                    -InputObject "[$(Get-Date -Format 'HH:mm:ss')] WakeDropdown revert error: $($_.Exception.Message)"
                # Fail forward: selection stays changed but is harmless â€” next app-selection event resets it
            }
        })
}
catch {
    $errPath = if ($global:PackageDir) { "$global:PackageDir\SAMISH_ERROR.txt" } else { "C:\Scripts\GOOGLE-ANTI-GRAVITY\SAMISH\SAMISH_ERROR.txt" }
    Out-File -FilePath $errPath -Append `
        -InputObject "[$(Get-Date -Format 'HH:mm:ss')] WakeDropdown hook registration failed: $($_.Exception.Message)"
    # Safety net: signal Set-OperatingModeBoxState to use Enabled toggling instead
    $script:wakeDropdownFallback = $true
    try { $ddOnWakeAction.Enabled = $false } catch {}
}

# Bottom Action Row (Page 2 Right Column)
$btnDiagAdvanced = New-Object System.Windows.Forms.Button
$btnDiagAdvanced.Name = "btnDiagAdvanced"
$btnDiagAdvanced.Text = "Diagnostics >>"
$btnDiagAdvanced.Font = $font
$btnDiagAdvanced.Size = New-Object System.Drawing.Size(370, 36)
$btnDiagAdvanced.Location = New-Object System.Drawing.Point(395, 410)
$btnDiagAdvanced.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnDiagAdvanced.FlatAppearance.BorderSize = 1
$btnDiagAdvanced.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$btnDiagAdvanced.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnDiagAdvanced.BackColor = [System.Drawing.Color]::Transparent
$btnDiagAdvanced.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$tabPage2.Controls.Add($btnDiagAdvanced)
$script:btnDiagAdvanced = $btnDiagAdvanced
$tooltip.SetToolTip($btnDiagAdvanced, "Open or close the advanced system sleep telemetry and testing drawer.")


# Page 2 Drawer Vertical Separator Line
$diagDrawerSep = New-Object System.Windows.Forms.Label
$diagDrawerSep.Name = "diagDrawerSep"
$diagDrawerSep.Size = New-Object System.Drawing.Size(2, 443)
$diagDrawerSep.Location = New-Object System.Drawing.Point(777, 10)
$diagDrawerSep.BackColor = $BrandPurple
$diagDrawerSep.Visible = $false
$tabPage2.Controls.Add($diagDrawerSep)
$script:diagDrawerSep = $diagDrawerSep

# 5. Page 2 Slide-Out Drawer: "Sleep & Wake Diagnostics"
$grpAdvancedDiag = New-Object System.Windows.Forms.Panel
$grpAdvancedDiag.Name = "grpAdvancedDiag"
$grpAdvancedDiag.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
$grpAdvancedDiag.Size = New-Object System.Drawing.Size(370, 436)
$grpAdvancedDiag.Location = New-Object System.Drawing.Point(790, 10)
$grpAdvancedDiag.Visible = $false
$grpAdvancedDiag.add_Paint({
        param($sender, $e)
        $color = if ($global:ThemeNeonActive) { if ($global:NeonBackground) { $global:NeonBackground } else { [System.Drawing.Color]::FromArgb(15, 15, 18) } } else { [System.Drawing.Color]::FromArgb(240, 240, 240) }
        if ($null -eq $color) { $color = [System.Drawing.Color]::FromArgb(240, 240, 240) }
        $brush = New-Object System.Drawing.SolidBrush($color)
        $e.Graphics.FillRectangle($brush, $sender.ClientRectangle)
        $brush.Dispose()
    })
$tabPage2.Controls.Add($grpAdvancedDiag)
$script:grpAdvancedDiag = $grpAdvancedDiag

# Operating Mode Tests GroupBox
$grpTest = New-Object System.Windows.Forms.GroupBox
$grpTest.Text = "Operating Mode Tests"
$grpTest.Size = New-Object System.Drawing.Size(370, 122)
$grpTest.Location = New-Object System.Drawing.Point(0, 0)
$grpAdvancedDiag.Controls.Add($grpTest)
$script:testGroup = $grpTest
$tooltip.SetToolTip($grpTest, "Perform interactive test actions on the selected sleep blocker target.")

$ddTestTarget = New-Object System.Windows.Forms.ComboBox
$ddTestTarget.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$ddTestTarget.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
$ddTestTarget.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$ddTestTarget.Size = New-Object System.Drawing.Size(340, 24)
$ddTestTarget.Location = New-Object System.Drawing.Point(15, 20)
$ddTestTarget.Enabled = $true
$grpTest.Controls.Add($ddTestTarget)
$script:ddTestTarget = $ddTestTarget
$tooltip.SetToolTip($ddTestTarget, "Select which configured application or device profile driver to test.")

# Operating Mode Tests dropdown interaction state
$script:testDropdownActive = $false
$script:testDropdownFallback = $false

try {
    $ddTestTarget.add_SelectionChangeCommitted({
            try {
                if (-not $script:testDropdownActive) {
                    # Revert any selection made while the dropdown is logically inactive
                    $script:ddTestTarget.SelectedIndex = 0
                }
            }
            catch {
                $errPath = if ($global:PackageDir) { "$global:PackageDir\SAMISH_ERROR.txt" } else { "C:\Scripts\GOOGLE-ANTI-GRAVITY\SAMISH\SAMISH_ERROR.txt" }
                Out-File -FilePath $errPath -Append `
                    -InputObject "[$(Get-Date -Format 'HH:mm:ss')] TestDropdown revert error: $($_.Exception.Message)"
            }
        })
}
catch {
    $errPath = if ($global:PackageDir) { "$global:PackageDir\SAMISH_ERROR.txt" } else { "C:\Scripts\GOOGLE-ANTI-GRAVITY\SAMISH\SAMISH_ERROR.txt" }
    Out-File -FilePath $errPath -Append `
        -InputObject "[$(Get-Date -Format 'HH:mm:ss')] TestDropdown hook registration failed: $($_.Exception.Message)"
    $script:testDropdownFallback = $true
    try { $ddTestTarget.Enabled = $false } catch {}
}

$btnTestSleep = New-Object System.Windows.Forms.Button
$btnTestSleep.Text = "Test Sleep/Hibernate"
$btnTestSleep.Size = New-Object System.Drawing.Size(165, 30)
$btnTestSleep.Location = New-Object System.Drawing.Point(15, 48)
$btnTestSleep.Enabled = $true
$btnTestSleep.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnTestSleep.FlatAppearance.BorderSize = 1
$btnTestSleep.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$btnTestSleep.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnTestSleep.BackColor = [System.Drawing.Color]::Transparent
$btnTestSleep.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$grpTest.Controls.Add($btnTestSleep)
$script:btnTestStop = $btnTestSleep
$tooltip.SetToolTip($btnTestSleep, "Test whether SAMISH can close this application or pause its media playback based on its configured sleep action.")

$btnTestWake = New-Object System.Windows.Forms.Button
$btnTestWake.Text = "Test Wake/Resume"
$btnTestWake.Size = New-Object System.Drawing.Size(165, 30)
$btnTestWake.Location = New-Object System.Drawing.Point(190, 48)
$btnTestWake.Enabled = $true
$btnTestWake.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnTestWake.FlatAppearance.BorderSize = 1
$btnTestWake.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$btnTestWake.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnTestWake.BackColor = [System.Drawing.Color]::Transparent
$btnTestWake.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$grpTest.Controls.Add($btnTestWake)
$script:btnTestStart = $btnTestWake
$tooltip.SetToolTip($btnTestWake, "Test whether SAMISH can launch this application and/or restore its media playback status based on its configured wake action.")

$btnTestGraceful = New-Object System.Windows.Forms.Button
$btnTestGraceful.Text = "Test Graceful Close"
$btnTestGraceful.Size = New-Object System.Drawing.Size(165, 30)
$btnTestGraceful.Location = New-Object System.Drawing.Point(15, 84)
$btnTestGraceful.Enabled = $true
$btnTestGraceful.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnTestGraceful.FlatAppearance.BorderSize = 1
$btnTestGraceful.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$btnTestGraceful.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnTestGraceful.BackColor = [System.Drawing.Color]::Transparent
$btnTestGraceful.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$grpTest.Controls.Add($btnTestGraceful)
$script:btnTestGraceful = $btnTestGraceful
$tooltip.SetToolTip($btnTestGraceful, "Test close app (graceful) behavior, asking the application to close cleanly.")

$btnTestForce = New-Object System.Windows.Forms.Button
$btnTestForce.Text = "Test Force Close"
$btnTestForce.Size = New-Object System.Drawing.Size(165, 30)
$btnTestForce.Location = New-Object System.Drawing.Point(190, 84)
$btnTestForce.Enabled = $true
$btnTestForce.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnTestForce.FlatAppearance.BorderSize = 1
$btnTestForce.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$btnTestForce.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnTestForce.BackColor = [System.Drawing.Color]::Transparent
$btnTestForce.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$grpTest.Controls.Add($btnTestForce)
$script:btnTestClassic = $btnTestForce
$tooltip.SetToolTip($btnTestForce, "Test close app (classic) behavior, forcing immediate process termination.")

# ---------------------------------------------------------------
# Drawer-Level Tab System for Telemetry (mirrors Page 1 style)
# Tab 1: System Telemetry  |  Tab 2: Hardware Telemetry
# ---------------------------------------------------------------

# --- Top-Level Drawer Tab Buttons (at Y=132, inside grpAdvancedDiag) ---
$btnDrawer2TabSystem = New-Object System.Windows.Forms.Button
$btnDrawer2TabSystem.Name = "btnDrawer2TabSystem"
$btnDrawer2TabSystem.Text = "System Telemetry"
$btnDrawer2TabSystem.Font = $boldFont
$btnDrawer2TabSystem.Size = New-Object System.Drawing.Size(175, 22)
$btnDrawer2TabSystem.Location = New-Object System.Drawing.Point(5, 132)
$btnDrawer2TabSystem.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnDrawer2TabSystem.FlatAppearance.BorderSize = 0
$btnDrawer2TabSystem.BackColor = [System.Drawing.SystemColors]::Control
$btnDrawer2TabSystem.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnDrawer2TabSystem.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$grpAdvancedDiag.Controls.Add($btnDrawer2TabSystem)
$script:btnDrawer2TabSystem = $btnDrawer2TabSystem
$tooltip.SetToolTip($btnDrawer2TabSystem, "View Sleep/Wake history and active wake timers - software-level events that affect sleep behaviour.")

$btnDrawer2TabHardware = New-Object System.Windows.Forms.Button
$btnDrawer2TabHardware.Name = "btnDrawer2TabHardware"
$btnDrawer2TabHardware.Text = "Hardware Telemetry"
$btnDrawer2TabHardware.Font = $font
$btnDrawer2TabHardware.Size = New-Object System.Drawing.Size(175, 22)
$btnDrawer2TabHardware.Location = New-Object System.Drawing.Point(190, 132)
$btnDrawer2TabHardware.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnDrawer2TabHardware.FlatAppearance.BorderSize = 0
$btnDrawer2TabHardware.BackColor = [System.Drawing.SystemColors]::Control
$btnDrawer2TabHardware.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
$btnDrawer2TabHardware.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$grpAdvancedDiag.Controls.Add($btnDrawer2TabHardware)
$script:btnDrawer2TabHardware = $btnDrawer2TabHardware
$tooltip.SetToolTip($btnDrawer2TabHardware, "Deep scan: USB/PCIe root hubs and armed devices that may block or interrupt sleep. Powered by WMI.")

# Purple active-tab indicator line (starts under "System Telemetry")
$drawer2TabIndicator = New-Object System.Windows.Forms.Label
$drawer2TabIndicator.Name = "drawer2TabIndicator"
$drawer2TabIndicator.Size = New-Object System.Drawing.Size(175, 2)
$drawer2TabIndicator.Location = New-Object System.Drawing.Point(5, 154)
$drawer2TabIndicator.BackColor = $BrandPurple
$grpAdvancedDiag.Controls.Add($drawer2TabIndicator)
$script:drawer2TabIndicator = $drawer2TabIndicator

# Cyan separator line spanning the full drawer width
$drawer2TabSep = New-Object System.Windows.Forms.Label
$drawer2TabSep.Name = "drawer2TabSep"
$drawer2TabSep.Size = New-Object System.Drawing.Size(370, 2)
$drawer2TabSep.Location = New-Object System.Drawing.Point(0, 157)
$drawer2TabSep.BackColor = $BrandCyan
$grpAdvancedDiag.Controls.Add($drawer2TabSep)
$script:drawer2TabSep = $drawer2TabSep
$drawer2TabIndicator.BringToFront()

# ---------------------------------------------------------------
# TAB 1 PANEL: System Telemetry (Sleep/Wake History + Wake Timers)
# ---------------------------------------------------------------
$pnlTelemetrySystem = New-Object System.Windows.Forms.Panel
$pnlTelemetrySystem.Name = "pnlTelemetrySystem"
$pnlTelemetrySystem.Size = New-Object System.Drawing.Size(370, 235)
$pnlTelemetrySystem.Location = New-Object System.Drawing.Point(0, 159)
$pnlTelemetrySystem.BackColor = [System.Drawing.Color]::Transparent
$grpAdvancedDiag.Controls.Add($pnlTelemetrySystem)
$script:pnlTelemetrySystem = $pnlTelemetrySystem

# Supported sleep states banner
$lblTelemetryStates = New-Object System.Windows.Forms.Label
$lblTelemetryStates.Text = "Querying sleep states..."
$lblTelemetryStates.AutoSize = $false
$lblTelemetryStates.Size = New-Object System.Drawing.Size(350, 26)
$lblTelemetryStates.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblTelemetryStates.ForeColor = $BrandPurple
$lblTelemetryStates.Location = New-Object System.Drawing.Point(10, 4)
$pnlTelemetrySystem.Controls.Add($lblTelemetryStates)
$script:lblTelemetryStates = $lblTelemetryStates
$tooltip.SetToolTip($lblTelemetryStates, "Sleep states supported by your system hardware (e.g. S3 Standby, S4 Hibernate).")

# Sleep/Wake History label + textbox
$lblLastWakeTitle = New-Object System.Windows.Forms.Label
$lblLastWakeTitle.Text = "Sleep/Wake History (Last 5 Cycles):"
$lblLastWakeTitle.AutoSize = $true
$lblLastWakeTitle.Location = New-Object System.Drawing.Point(10, 35)
$pnlTelemetrySystem.Controls.Add($lblLastWakeTitle)
$tooltip.SetToolTip($lblLastWakeTitle, "A recent history of sleep and wake events including wake source, time, and duration.")

$txtLastWake = New-Object System.Windows.Forms.TextBox
$txtLastWake.Name = "txtLastWake"
$txtLastWake.Multiline = $true
$txtLastWake.ScrollBars = "Vertical"
$txtLastWake.ReadOnly = $true
$txtLastWake.Size = New-Object System.Drawing.Size(350, 72)
$txtLastWake.Location = New-Object System.Drawing.Point(10, 58)
$txtLastWake.Font = New-Object System.Drawing.Font("Consolas", 8.5)
$txtLastWake.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 250)
$pnlTelemetrySystem.Controls.Add($txtLastWake)
$script:txtLastWake = $txtLastWake
$tooltip.SetToolTip($txtLastWake, "The driver, device, or scheduled task that caused each recent wake from sleep.")

# Wake Timers label + textbox
$lblWakeTimersTitle = New-Object System.Windows.Forms.Label
$lblWakeTimersTitle.Text = "Active Wake Timers:"
$lblWakeTimersTitle.AutoSize = $true
$lblWakeTimersTitle.Location = New-Object System.Drawing.Point(10, 138)
$pnlTelemetrySystem.Controls.Add($lblWakeTimersTitle)
$tooltip.SetToolTip($lblWakeTimersTitle, "Software tasks and scheduled jobs that are currently armed to wake the PC from sleep.")

$listWakeTimers = New-Object System.Windows.Forms.ListBox
$listWakeTimers.Name = "listWakeTimers"
$listWakeTimers.Size = New-Object System.Drawing.Size(350, 69)
$listWakeTimers.Location = New-Object System.Drawing.Point(10, 157)
$listWakeTimers.Font = New-Object System.Drawing.Font("Consolas", 8.5)
$listWakeTimers.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 250)
$listWakeTimers.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
$listWakeTimers.ItemHeight = 16
$listWakeTimers.IntegralHeight = $false
$pnlTelemetrySystem.Controls.Add($listWakeTimers)
$script:listWakeTimers = $listWakeTimers
$tooltip.SetToolTip($listWakeTimers, "Lists active system wake timers - scheduled software tasks that can wake the PC from sleep automatically.")

# ---------------------------------------------------------------
# TAB 2 PANEL: Hardware Telemetry (Armed Devices + WMI Hardware Scans)
# ---------------------------------------------------------------
$pnlTelemetryHardware = New-Object System.Windows.Forms.Panel
$pnlTelemetryHardware.Name = "pnlTelemetryHardware"
$pnlTelemetryHardware.Size = New-Object System.Drawing.Size(370, 235)
$pnlTelemetryHardware.Location = New-Object System.Drawing.Point(0, 159)
$pnlTelemetryHardware.BackColor = [System.Drawing.Color]::Transparent
$pnlTelemetryHardware.Visible = $false
$grpAdvancedDiag.Controls.Add($pnlTelemetryHardware)
$script:pnlTelemetryHardware = $pnlTelemetryHardware

# Armed Devices label + listbox
$lblArmedDevicesTitle = New-Object System.Windows.Forms.Label
$lblArmedDevicesTitle.Text = "Armed Devices (Can Wake PC):"
$lblArmedDevicesTitle.AutoSize = $true
$lblArmedDevicesTitle.Location = New-Object System.Drawing.Point(10, 38)
$pnlTelemetryHardware.Controls.Add($lblArmedDevicesTitle)
$tooltip.SetToolTip($lblArmedDevicesTitle, "Hardware devices (e.g. keyboard, mouse, network adapter) that are configured to wake the PC from sleep.")

$listArmedDevices = New-Object System.Windows.Forms.ListBox
$listArmedDevices.Name = "listArmedDevices"
$listArmedDevices.Size = New-Object System.Drawing.Size(350, 72)
$listArmedDevices.Location = New-Object System.Drawing.Point(10, 58)
$listArmedDevices.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 250)
$listArmedDevices.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
$listArmedDevices.ItemHeight = 16
$listArmedDevices.IntegralHeight = $false
$pnlTelemetryHardware.Controls.Add($listArmedDevices)
$script:listArmedDevices = $listArmedDevices
$tooltip.SetToolTip($listArmedDevices, "Lists hardware devices armed to wake the PC. Manage these via Device Manager > Power Management properties.")

# Deep WMI Hardware Scans label + textbox
$lblHardwareScansTitle = New-Object System.Windows.Forms.Label
$lblHardwareScansTitle.Text = "USB & PCIe Power State Scan (WMI):"
$lblHardwareScansTitle.UseMnemonic = $false
$lblHardwareScansTitle.AutoSize = $true
$lblHardwareScansTitle.Location = New-Object System.Drawing.Point(10, 138)
$pnlTelemetryHardware.Controls.Add($lblHardwareScansTitle)
$tooltip.SetToolTip($lblHardwareScansTitle, "Deep WMI scan: checks which USB root hubs and PCIe devices are preventing the system from entering a low-power state.")

$listHardwareScans = New-Object System.Windows.Forms.ListBox
$listHardwareScans.Name = "listHardwareScans"
$listHardwareScans.Size = New-Object System.Drawing.Size(350, 69)
$listHardwareScans.Location = New-Object System.Drawing.Point(10, 157)
$listHardwareScans.Font = New-Object System.Drawing.Font("Consolas", 8.5)
$listHardwareScans.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 250)
$listHardwareScans.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
$listHardwareScans.ItemHeight = 16
$listHardwareScans.IntegralHeight = $false
$listHardwareScans.Items.Add("Click 'Refresh Telemetry' to run a deep hardware scan.") | Out-Null
$pnlTelemetryHardware.Controls.Add($listHardwareScans)
$script:listHardwareScans = $listHardwareScans
$tooltip.SetToolTip($listHardwareScans, "Shows USB root hubs and PCIe devices. Audio drivers (e.g. GoXLR, BEACN) that hold USB active can prevent deep sleep C-states.")

# ---------------------------------------------------------------
# Refresh Button (anchored to bottom of grpAdvancedDiag)
# ---------------------------------------------------------------




# Redesigned refresh button, externalized to the drawer panel
$btnTelemetryRefresh = New-Object System.Windows.Forms.Button
$btnTelemetryRefresh.Text = "Refresh Telemetry"
$btnTelemetryRefresh.Font = $font
$btnTelemetryRefresh.Size = New-Object System.Drawing.Size(175, 36)
$btnTelemetryRefresh.Location = New-Object System.Drawing.Point(5, 400)
$btnTelemetryRefresh.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnTelemetryRefresh.FlatAppearance.BorderSize = 1
$btnTelemetryRefresh.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$btnTelemetryRefresh.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnTelemetryRefresh.BackColor = [System.Drawing.Color]::Transparent
$btnTelemetryRefresh.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$grpAdvancedDiag.Controls.Add($btnTelemetryRefresh)
$script:btnTelemetryRefresh = $btnTelemetryRefresh
$tooltip.SetToolTip($btnTelemetryRefresh, "Query and refresh active sleep blockers, system overrides, and wake diagnostics.")

# Dynamic telemetry action button
$btnTelemetryAction = New-Object System.Windows.Forms.Button
$btnTelemetryAction.Text = "Select Item..."
$btnTelemetryAction.Font = $font
$btnTelemetryAction.Size = New-Object System.Drawing.Size(175, 36)
$btnTelemetryAction.Location = New-Object System.Drawing.Point(190, 400)
$btnTelemetryAction.Enabled = $false
$btnTelemetryAction.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnTelemetryAction.FlatAppearance.BorderSize = 1
$btnTelemetryAction.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$btnTelemetryAction.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnTelemetryAction.BackColor = [System.Drawing.Color]::Transparent
$btnTelemetryAction.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$grpAdvancedDiag.Controls.Add($btnTelemetryAction)
$script:btnTelemetryAction = $btnTelemetryAction
$tooltip.SetToolTip($btnTelemetryAction, "Select an active device, timer, or USB scan result to perform a management action.")


# 6. Global Status Label (Page 2 Bottom Info Bar)
$lblDiagDetail = New-Object System.Windows.Forms.Label
$lblDiagDetail.Name = "lblDiagDetail"
$lblDiagDetail.Text = "Select an item from the Active Blockers list to see details, or click Scan Blockers."
$lblDiagDetail.AutoSize = $false
$lblDiagDetail.Size = New-Object System.Drawing.Size(760, 36)
$lblDiagDetail.Location = New-Object System.Drawing.Point(10, 452)
$lblDiagDetail.ForeColor = [System.Drawing.Color]::DimGray
$tabPage2.Controls.Add($lblDiagDetail)
$script:lblDiagDetail = $lblDiagDetail



