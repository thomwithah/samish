# ---------- UI ----------
$script:MainFormGdiResources = New-Object System.Collections.Generic.List[System.IDisposable]

function Get-HighQualityScaledImage {
    param(
        [string]$Path,
        [int]$Width,
        [int]$Height
    )
# ---------- TRAY ICON ----------
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

        if (Test-Path -LiteralPath $activePath) {
            $script:IconActive = New-Object System.Drawing.Icon($activePath)
            $script:MainFormGdiResources.Add($script:IconActive)
        }
        if (Test-Path -LiteralPath $disabledPath) {
            $script:IconDisabled = New-Object System.Drawing.Icon($disabledPath)
            $script:MainFormGdiResources.Add($script:IconDisabled)
        }
    } catch {}

    # Ensure we have a visible icon - fall back to built‑in icon if assets missing
    if (-not $script:IconActive) {
        Log-Always "WARN: SAMISH tray active icon not found, using default SystemIcons.Application."
    }
    if (-not $script:IconDisabled) {
        Log-Always "WARN: SAMISH tray disabled icon not found, using default SystemIcons.Application."
    }

    $script:icon.Icon = if ($script:IconActive) { $script:IconActive } else { [System.Drawing.SystemIcons]::Application }
    $script:icon.Visible = $true

    $script:icon.Text = "SAMISH v1.0.7"

    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $toggleItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $toggleItem.Text = "Disable helper"
    $exitItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $exitItem.Text = "Exit"
    [void]$menu.Items.Add($toggleItem)
    [void]$menu.Items.Add($exitItem)
    $script:icon.ContextMenuStrip = $menu

    $script:MenuToggleItem = $toggleItem

    $toggleItem.add_Click({
        Set-HelperEnabled (-not $script:TrayEnabled) "TRAY MENU"
    })

    $exitItem.add_Click({
        try { $script:icon.Visible = $false; $script:icon.Dispose() } catch {}
        try { [System.Windows.Forms.Application]::Exit() } catch {}
    })
}

# Determine if SAMISH is installed to control UI elements
$script:IsSamishInstalled = Test-SamishInstalled
# Grey out Clean Reset button when not installed
if ($script:IsSamishInstalled) {
    $btnCleanReset.Enabled = $true
} else {
    $btnCleanReset.Enabled = $false
    $tooltip.SetToolTip($btnCleanReset, "SAMISH is not installed - clean reset unavailable.")
}
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $original = [System.Drawing.Image]::FromFile($Path)
        $bmp = New-Object System.Drawing.Bitmap($Width, $Height)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g.DrawImage($original, 0, 0, $Width, $Height)
        $g.Dispose()
        $original.Dispose()
        return $bmp
    }
    catch {
        try {
            return [System.Drawing.Image]::FromFile($Path)
        }
        catch {
            return $null
        }
    }
}

$BrandPurple = [System.Drawing.Color]::FromArgb(170, 0, 255) # #AA00FF
$script:BrandPurple = $BrandPurple
$BrandCyan = [System.Drawing.Color]::FromArgb(0, 215, 255) # #00D7FF
$script:BrandCyan = $BrandCyan

$script:MonitoredApps = @()

$form = New-Object System.Windows.Forms.Form
$form.Text = "$ProductName - Setup"
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.AutoScaleMode = "Font"
$form.ClientSize = New-Object System.Drawing.Size(720, 800)

$formIconPath = Join-Path $PackageDir "Assets\128x128.ico"
if (Test-Path -LiteralPath $formIconPath) {
    try {
        $formIcon = New-Object System.Drawing.Icon($formIconPath)
        $script:MainFormGdiResources.Add($formIcon)
        $form.Icon = $formIcon
    }
    catch { }
}

$font = New-Object System.Drawing.Font("Segoe UI", 10)
$script:MainFormGdiResources.Add($font)

$title = New-Object System.Windows.Forms.Label
$title.Text = "$ProductName"
$titleFont = New-Object System.Drawing.Font("Segoe UI", 24, [System.Drawing.FontStyle]::Bold)
$script:MainFormGdiResources.Add($titleFont)
$title.Font = $titleFont
$title.ForeColor = $BrandPurple
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(18, 12)
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = "Streaming Audio Mixer Interface Sleep Helper"
$subtitleFont = New-Object System.Drawing.Font("Segoe UI", 10)
$script:MainFormGdiResources.Add($subtitleFont)
$subtitle.Font = $subtitleFont
$subtitle.ForeColor = $BrandCyan
$subtitle.AutoSize = $true
$subtitle.UseMnemonic = $false
$subtitle.Location = New-Object System.Drawing.Point(20, 60)
$form.Controls.Add($subtitle)

# Logo PictureBox
$logo = New-Object System.Windows.Forms.PictureBox
$logo.Size = New-Object System.Drawing.Size(64, 64)
$logo.Location = New-Object System.Drawing.Point(638, 12)
$logo.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Normal
$logoPath = Join-Path $PackageDir "Assets\SAMISH-SQUARE-STYLIZED.png"
if (Test-Path -LiteralPath $logoPath) {
    $logoImg = Get-HighQualityScaledImage -Path $logoPath -Width 64 -Height 64
    if ($logoImg) {
        $script:MainFormGdiResources.Add($logoImg)
        $logo.Image = $logoImg
    }
}
$form.Controls.Add($logo)

# Separator line under header (matching diagnostics window style)
$mainSep = New-Object System.Windows.Forms.Label
$mainSep.Size = New-Object System.Drawing.Size(684, 2)
$mainSep.Location = New-Object System.Drawing.Point(18, 84)
$mainSep.BackColor = $BrandCyan
$form.Controls.Add($mainSep)

# ---------- Install Mode + Operating Mode (side-by-side) ----------
$topY = 95
$leftX = 18
$totalWidth = 684
$gapX = 18
$halfWidth = [int](($totalWidth - $gapX) / 2)

# ----- Install Mode (LEFT) -----
$modeGroup = New-Object System.Windows.Forms.GroupBox
$modeGroup.Text = "Install Mode"
$modeGroup.Font = $font
$modeGroup.ForeColor = $BrandPurple
$modeGroup.Size = New-Object System.Drawing.Size($halfWidth, 85)
$modeGroup.Location = New-Object System.Drawing.Point($leftX, $topY)
$form.Controls.Add($modeGroup)

$tooltip.SetToolTip($modeGroup,
    "Choose how SAMISH runs.

Hidden mode runs automatically with no visible interface.

Interactive mode enables tray icon and user interface features.")

$rbHidden = New-Object System.Windows.Forms.RadioButton
$rbHidden.Text = "Hidden (recommended) - runs silently"
$rbHidden.Checked = $true
$rbHidden.AutoSize = $true
$rbHidden.Location = New-Object System.Drawing.Point(15, 25)
$modeGroup.Controls.Add($rbHidden)

$rbInteractive = New-Object System.Windows.Forms.RadioButton
$rbInteractive.Text = "Interactive - needed for tray icon"
$rbInteractive.AutoSize = $true
$rbInteractive.Location = New-Object System.Drawing.Point(15, 50)
$modeGroup.Controls.Add($rbInteractive)

$tooltip.SetToolTip($rbHidden,
    "Runs in the background with no visible interface. Starts automatically and operates silently. Recommended for most users.")

$tooltip.SetToolTip($rbInteractive,
    "Enables system tray icon and visual controls.")

# ----- Operating Mode (RIGHT) -----
$opGroup = New-Object System.Windows.Forms.GroupBox
$opGroup.Text = "Operating Mode"
$opGroup.Font = $font
$opGroup.ForeColor = $BrandPurple
$opGroup.Size = New-Object System.Drawing.Size($halfWidth, 85)
$opGroup.Location = New-Object System.Drawing.Point(($leftX + $halfWidth + $gapX), $topY)
$form.Controls.Add($opGroup)

$tooltip.SetToolTip($opGroup,
    "Choose how SAMISH performs shutdown actions.

Graceful attempts a clean shutdown and does not rely on Screen Off timing.

Classic uses power-plan timing and may require compatible power settings.")

$rbOpGraceful = New-Object System.Windows.Forms.RadioButton
$rbOpGraceful.Text = "Graceful (recommended)"
$rbOpGraceful.Checked = $true
$rbOpGraceful.AutoSize = $true
$rbOpGraceful.Location = New-Object System.Drawing.Point(15, 25)
$opGroup.Controls.Add($rbOpGraceful)

$rbOpClassic = New-Object System.Windows.Forms.RadioButton
$rbOpClassic.Text = "Classic (uses force for shutdown actions)"
$rbOpClassic.AutoSize = $true
$rbOpClassic.Location = New-Object System.Drawing.Point(15, 50)
$opGroup.Controls.Add($rbOpClassic)

$tooltip.SetToolTip($rbOpGraceful,
    "Attempts a clean shutdown and does not rely on Screen Off timing")

$tooltip.SetToolTip($rbOpClassic,
    "Uses power-plan timing and forces shutdown actions.")

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
$script:btnTestGraceful.Enabled = $false
$testGroup.Controls.Add($script:btnTestGraceful)

$tooltip.SetToolTip($script:btnTestGraceful,
    "Test whether SAMISH can ask this app to close cleanly. Graceful shutdown is safer for unsaved work but may occasionally fail if the app is unresponsive.")

$script:btnTestClassic = New-Object System.Windows.Forms.Button
$script:btnTestClassic.Text = "Test Classic"
$script:btnTestClassic.Font = $font
$script:btnTestClassic.Size = New-Object System.Drawing.Size(112, 30)
$script:btnTestClassic.Location = New-Object System.Drawing.Point(137, 70)
$script:btnTestClassic.Enabled = $false
$testGroup.Controls.Add($script:btnTestClassic)

$tooltip.SetToolTip($script:btnTestClassic,
    "Test whether SAMISH can force-close this app immediately. More reliable than Graceful, but any unsaved work in that app may be lost.")

$script:btnTestStart = New-Object System.Windows.Forms.Button
$script:btnTestStart.Text = "Start Test"
$script:btnTestStart.Font = $font
$script:btnTestStart.Size = New-Object System.Drawing.Size(102, 30)
$script:btnTestStart.Location = New-Object System.Drawing.Point(298, 70)
$script:btnTestStart.Enabled = $false
$testGroup.Controls.Add($script:btnTestStart)

$tooltip.SetToolTip($script:btnTestStart,
    "Test whether SAMISH can relaunch this application or resume its media playback based on its configured wake action.")

$script:btnTestStop = New-Object System.Windows.Forms.Button
$script:btnTestStop.Text = "Stop Test"
$script:btnTestStop.Font = $font
$script:btnTestStop.Size = New-Object System.Drawing.Size(102, 30)
$script:btnTestStop.Location = New-Object System.Drawing.Point(410, 70)
$script:btnTestStop.Enabled = $false
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
    $isInstalled  = $false
    $deviceRunning = $false
    $hasAutomated  = ($script:MonitoredApps -and $script:MonitoredApps.Count -gt 0)

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
    } catch {}

    if ($profileProcName) {
        try {
            $deviceRunning = ($null -ne (Get-Process -Name $profileProcName -ErrorAction SilentlyContinue | Select-Object -First 1))
        } catch {}
    }

    $shouldEnable = ($isInstalled -or $hasAutomated -or $deviceRunning)

    # --- Enable or disable child controls ---
    foreach ($ctrl in $script:testGroup.Controls) {
        $ctrl.Enabled = $shouldEnable
    }

    # --- Update GroupBox title color (flash when enabling, grey when disabling) ---
    if ($shouldEnable) {
        # Kill any previous flash timer to prevent race conditions
        if ($script:testGroupFlashTimer) {
            try { $script:testGroupFlashTimer.Stop(); $script:testGroupFlashTimer.Dispose() } catch {}
            $script:testGroupFlashTimer = $null
        }

        # Triple-flash: Cyan -> Purple (6 ticks at 180ms each, ends on BrandPurple)
        $script:testGroup.ForeColor = $BrandCyan
        try { $script:testGroup.Refresh() } catch {}
        $script:testGroupFlashTick = 0
        $script:testGroupFlashTimer = New-Object System.Windows.Forms.Timer
        $script:testGroupFlashTimer.Interval = 180
        $script:testGroupFlashTimer.add_Tick({
                $script:testGroupFlashTick++
                if ($script:testGroupFlashTick % 2 -eq 0) {
                    $script:testGroup.ForeColor = $BrandCyan
                } else {
                    $script:testGroup.ForeColor = $BrandPurple
                }
                if ($script:testGroupFlashTick -ge 5) {
                    $script:testGroup.ForeColor = $BrandPurple
                    try {
                        if ($script:testGroupFlashTimer) {
                            $script:testGroupFlashTimer.Stop()
                            $script:testGroupFlashTimer.Dispose()
                            $script:testGroupFlashTimer = $null
                        }
                    } catch {}
                }
            })
        $script:testGroupFlashTimer.Start()
    } else {
        # Kill any running flash timer when disabling
        if ($script:testGroupFlashTimer) {
            try { $script:testGroupFlashTimer.Stop(); $script:testGroupFlashTimer.Dispose() } catch {}
            $script:testGroupFlashTimer = $null
        }
        $script:testGroup.ForeColor = [System.Drawing.Color]::Gray
    }

    # --- Rebuild the target dropdown ---
    $script:ddTestTarget.Items.Clear()

    # Always add device software entry (even if not currently running)
    $displayProfileName = $script:ActiveProfileId
    try {
        if ($script:ProfileMetaById -and $script:ProfileMetaById.ContainsKey($script:ActiveProfileId)) {
            $displayProfileName = $script:ProfileMetaById[$script:ActiveProfileId].DisplayName
        }
    } catch {}
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
}

# ---------- General Settings ----------
$cfgGroup = New-Object System.Windows.Forms.GroupBox
$cfgGroup.Text = "General Settings"
$cfgGroup.Font = $font
$cfgGroup.ForeColor = $BrandPurple
$cfgGroup.Size = New-Object System.Drawing.Size($totalWidth, 250)
$cfgGroup.Location = New-Object System.Drawing.Point(18, 0)
$form.Controls.Add($cfgGroup)

# ----- TOOLTIP: GENERAL SETTINGS GROUP -----
$tooltip.SetToolTip($cfgGroup,
    "Configure logging, tray icon, and hotkey behavior.")

$cbLogging = New-Object System.Windows.Forms.CheckBox
$script:cbLogging = $cbLogging
$cbLogging.Text = "Enable Logging"
$cbLogging.AutoSize = $true
$cbLogging.Location = New-Object System.Drawing.Point(15, 30)
$cfgGroup.Controls.Add($cbLogging)

$lblLogInterval = New-Object System.Windows.Forms.Label
$lblLogInterval.Text = "Log interval:"
$lblLogInterval.AutoSize = $true
$lblLogInterval.Location = New-Object System.Drawing.Point(35, 62)
$cfgGroup.Controls.Add($lblLogInterval)

$ddLogInterval = New-Object System.Windows.Forms.ComboBox
$ddLogInterval.DropDownStyle = "DropDownList"
$ddLogInterval.Items.AddRange(@("Verbose (every loop)", "Every 30 seconds", "Every 60 seconds", "Custom seconds..."))
$ddLogInterval.SelectedIndex = 1
$ddLogInterval.Location = New-Object System.Drawing.Point(125, 58)
$ddLogInterval.Width = 160
$cfgGroup.Controls.Add($ddLogInterval)

$tbLogCustom = New-Object System.Windows.Forms.TextBox
$tbLogCustom.Location = New-Object System.Drawing.Point(365, 58)
$tbLogCustom.Width = 80
$tbLogCustom.Enabled = $false
$tbLogCustom.Text = "30"
$cfgGroup.Controls.Add($tbLogCustom)

$lblLogCustom = New-Object System.Windows.Forms.Label
$lblLogCustom.Text = "sec"
$lblLogCustom.AutoSize = $true
$lblLogCustom.Location = New-Object System.Drawing.Point(450, 62)
$cfgGroup.Controls.Add($lblLogCustom)

$cbTray = New-Object System.Windows.Forms.CheckBox
$cbTray.Text = "Enable Tray Icon (Interactive mode only)"
$cbTray.AutoSize = $true
$cbTray.Location = New-Object System.Drawing.Point(15, 182)
$cfgGroup.Controls.Add($cbTray)

$cbHotkey = New-Object System.Windows.Forms.CheckBox
$cbHotkey.Text = "Enable Hotkey Toggle"
$cbHotkey.AutoSize = $true
$cbHotkey.Location = New-Object System.Drawing.Point(15, 98)
$cfgGroup.Controls.Add($cbHotkey)

$lblHotkey = New-Object System.Windows.Forms.Label
$lblHotkey.Text = "Hotkey:"
$lblHotkey.AutoSize = $true
$lblHotkey.Location = New-Object System.Drawing.Point(35, 130)
$cfgGroup.Controls.Add($lblHotkey)

$ddHotkey = New-Object System.Windows.Forms.ComboBox
$ddHotkey.DropDownStyle = "DropDownList"
$ddHotkey.Items.AddRange(@("ScrollLock", "PauseBreak", "F12", "Custom"))
$ddHotkey.SelectedItem = "ScrollLock"
$ddHotkey.Location = New-Object System.Drawing.Point(125, 126)
$ddHotkey.Width = 160
$cfgGroup.Controls.Add($ddHotkey)

$lblCustomKey = New-Object System.Windows.Forms.Label
$lblCustomKey.Text = "Custom:"
$lblCustomKey.AutoSize = $true
$lblCustomKey.Location = New-Object System.Drawing.Point(305, 130)
$cfgGroup.Controls.Add($lblCustomKey)

$tbCustomKey = New-Object System.Windows.Forms.TextBox
$tbCustomKey.Location = New-Object System.Drawing.Point(365, 126)
$tbCustomKey.Width = 80
$tbCustomKey.Enabled = $false
$tbCustomKey.Text = "F8"
$cfgGroup.Controls.Add($tbCustomKey)

$lblCustomHint = New-Object System.Windows.Forms.Label
$lblCustomHint.Text = "Examples: F8, K, 7, 0x91"
$lblCustomHint.AutoSize = $true
$lblCustomHint.Location = New-Object System.Drawing.Point(365, 152)
$cfgGroup.Controls.Add($lblCustomHint)

# ----- TOOLTIPS: GENERAL SETTINGS -----
$tooltip.SetToolTip($cbLogging,
    "Writes activity to a log file that you can open from the Tools section.")
$tooltip.SetToolTip($ddLogInterval,
    "Controls how often activity is written to the log.")
$tooltip.SetToolTip($tbLogCustom,
    "Enter a custom logging interval in seconds.")
$tooltip.SetToolTip($cbTray,
    "Shows a system tray icon for quick access. Requires Interactive mode.")
$tooltip.SetToolTip($cbHotkey,
    "Allows a keyboard shortcut to toggle SAMISH on or off.")
$tooltip.SetToolTip($ddHotkey,
    "Select which key will be used as the toggle hotkey.")
$tooltip.SetToolTip($tbCustomKey,
    "Enter a custom key. Examples: F8, K, 7, or 0x91.")

# ---------- Device Settings (Profiles) ----------
$deviceGroup = New-Object System.Windows.Forms.GroupBox
$deviceGroup.Text = "Device Settings"
$deviceGroup.Font = $font
$deviceGroup.ForeColor = $BrandPurple
$deviceGroup.Size = New-Object System.Drawing.Size($totalWidth, 160)
$deviceGroup.Location = New-Object System.Drawing.Point(18, 0)
$form.Controls.Add($deviceGroup)

$tooltip.SetToolTip($deviceGroup,
    "Select which device profile SAMISH should manage.

Today, SAMISH uses one active profile at a time.
Multi-device simultaneous support will be added later.")

# Profiles list container
$profilesPanel = New-Object System.Windows.Forms.Panel
$profilesPanel.Location = New-Object System.Drawing.Point(15, 25)
$profilesPanel.Size = New-Object System.Drawing.Size(320, 120)
$profilesPanel.AutoScroll = $true
$deviceGroup.Controls.Add($profilesPanel)

# Details panel
$detailsPanel = New-Object System.Windows.Forms.Panel
$detailsPanel.Location = New-Object System.Drawing.Point(350, 25)
$detailsPanel.Size = New-Object System.Drawing.Size(315, 120)
$deviceGroup.Controls.Add($detailsPanel)

$lblDetailsTitle = New-Object System.Windows.Forms.Label
$lblDetailsTitle.Text = "Selected Profile"
$lblDetailsTitle.AutoSize = $true
$lblDetailsTitleFont = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$script:MainFormGdiResources.Add($lblDetailsTitleFont)
$lblDetailsTitle.Font = $lblDetailsTitleFont
$lblDetailsTitle.Location = New-Object System.Drawing.Point(0, 0)
$detailsPanel.Controls.Add($lblDetailsTitle)

$lblProc = New-Object System.Windows.Forms.Label
$lblProc.Text = "Process: (unknown)"
$lblProc.AutoSize = $true
$lblProc.Location = New-Object System.Drawing.Point(0, 25)
$detailsPanel.Controls.Add($lblProc)

$lblPath = New-Object System.Windows.Forms.Label
$lblPath.Text = "Path: (unknown)"
$lblPath.AutoSize = $true
$lblPath.MaximumSize = New-Object System.Drawing.Size(310, 0)
$lblPath.Location = New-Object System.Drawing.Point(0, 45)
$detailsPanel.Controls.Add($lblPath)

$lblCaps = New-Object System.Windows.Forms.Label
$lblCaps.Text = "Supports: (unknown)"
$lblCaps.AutoSize = $true
$lblCaps.Location = New-Object System.Drawing.Point(0, 85)
$detailsPanel.Controls.Add($lblCaps)

function Set-ProfileDetails {
    param($profileObj)

    if (-not $profileObj) {
        $lblProc.Text = "Process: (unknown)"
        $lblPath.Text = "Path: (unknown)"
        $lblCaps.Text = "Supports: (unknown)"
        return
    }

    try {
        $p = $profileObj.Raw
        $t = $null
        if ($p.targets -and $p.targets.Count -gt 0) { $t = $p.targets[0] }

        $proc = $(if ($t -and $t.processName) { [string]$t.processName } else { "(unknown)" })
        $path = $(if ($t -and $t.defaultExePath) { [string]$t.defaultExePath } else { "(unknown)" })

        $g = $(if ($t -and $t.supportsGraceful) { "Graceful" } else { "" })
        $c = $(if ($t -and $t.supportsClassic) { "Classic" } else { "" })
        $caps = ($g, $c | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ", "
        if ([string]::IsNullOrWhiteSpace($caps)) { $caps = "(unknown)" }

        $lblProc.Text = "Process: $proc"
        $lblPath.Text = "Path: $path"
        $lblCaps.Text = "Supports: $caps"
    }
    catch {
        $lblProc.Text = "Process: (unknown)"
        $lblPath.Text = "Path: (unknown)"
        $lblCaps.Text = "Supports: (unknown)"
    }
}

function Build-ProfilesUI {
    $profilesPanel.Controls.Clear()
    $script:ProfileMetaById = @{}

    try {
        # Use shared helpers (single source of truth)
        $profiles = Get-AvailableProfiles
        if (-not $profiles -or $profiles.Count -eq 0) {
            $lbl = New-Object System.Windows.Forms.Label
            $lbl.Text = "No profiles found."
            $lbl.AutoSize = $true
            $lbl.Location = [System.Drawing.Point]::new(0, 0)
            $profilesPanel.Controls.Add($lbl)
            Set-ProfileDetails $null
            return
        }

        Load-ProfileSelectionFromConfigIntoSetup

        # If ActiveProfileId isn't present in available profiles, fall back to first
        if (-not ($profiles | Where-Object { $_.Id -eq $script:ActiveProfileId })) {
            $script:ActiveProfileId = $profiles[0].Id
            $script:ProfilesEnabled = @($script:ActiveProfileId)
        }

        foreach ($p in $profiles) { $script:ProfileMetaById[$p.Id] = $p }

        [int]$y = 0
        foreach ($p in $profiles) {

            # Enabled checkbox (future multi-device): interactive for tooltip/click, but not toggleable
            $cbEnabled = New-Object System.Windows.Forms.CheckBox
            $cbEnabled.Location = [System.Drawing.Point]::new(0, [int]($y + 6))
            $cbEnabled.Size = New-Object System.Drawing.Size(15, 15)
            $cbEnabled.Tag = $p.Id
            $cbEnabled.Checked = ($p.Id -eq $script:ActiveProfileId)
            $cbEnabled.Enabled = $true
            $cbEnabled.AutoCheck = $false
            $profilesPanel.Controls.Add($cbEnabled)

            $tooltip.SetToolTip($cbEnabled, "Multi-device simultaneous support coming later.")

            $cbEnabled.add_Click({
                    [System.Windows.Forms.MessageBox]::Show(
                        "Multi-device simultaneous support is coming later. For now, SAMISH uses one active device profile at a time.",
                        "Coming Later",
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Information
                    ) | Out-Null
                })

            # Active radio (single-target today) â€” all radios share same parent ($profilesPanel)
            $rb = New-Object System.Windows.Forms.RadioButton
            $rb.Text = $p.DisplayName
            $rb.AutoSize = $true
            $rb.Location = [System.Drawing.Point]::new(20, [int]($y + 4))
            $rb.Tag = $p.Id
            $rb.Checked = ($script:ActiveProfileId -eq $p.Id)
            $profilesPanel.Controls.Add($rb)

            $rb.add_CheckedChanged({
                    if (-not $this.Checked) { return }

                    $selectedId = [string]$this.Tag
                    $script:ActiveProfileId = $selectedId
                    $script:ProfilesEnabled = @($selectedId)

                    if ($script:ProfileMetaById.ContainsKey($selectedId)) {
                        Set-ProfileDetails $script:ProfileMetaById[$selectedId]
                    }
                    else {
                        Set-ProfileDetails $null
                    }

                    foreach ($ctl in $profilesPanel.Controls) {
                        if ($ctl -is [System.Windows.Forms.CheckBox]) {
                            $tagId = [string]$ctl.Tag
                            $ctl.Checked = ($tagId -eq $script:ActiveProfileId)
                        }
                    }

                    # Keep the test group dropdown and enabled state in sync
                    # when the user switches profiles.
                    if (Get-Command Update-TestGroupState -ErrorAction SilentlyContinue) {
                        try { Update-TestGroupState } catch {}
                    }
                })

            $y += 28
        }

        # Initialize details
        if ($script:ProfileMetaById.ContainsKey($script:ActiveProfileId)) {
            Set-ProfileDetails $script:ProfileMetaById[$script:ActiveProfileId]
        }
        else {
            Set-ProfileDetails $profiles[0]
        }

    }
    catch {
        $profilesPanel.Controls.Clear()

        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = "Profiles UI error:`r`n" + $_.Exception.Message
        $lbl.AutoSize = $true
        $lbl.MaximumSize = New-Object System.Drawing.Size(($profilesPanel.Width - 10), 0)
        $lbl.Location = [System.Drawing.Point]::new(0, 0)
        $profilesPanel.Controls.Add($lbl)

        Set-ProfileDetails $null
    }
}

# Build profiles UI on launch, then set initial test group state.
Build-ProfilesUI

# Initialise test group state after profiles are loaded so the dropdown
# reflects the correct device software name from the start.
if (Get-Command Update-TestGroupState -ErrorAction SilentlyContinue) {
    try { Update-TestGroupState } catch {}
}

# ---------- Status / Activity ----------
$statusGroup = New-Object System.Windows.Forms.GroupBox
$statusGroup.Text = "Status / Activity"
$statusGroup.Font = $font
$statusGroup.ForeColor = $BrandPurple
$statusGroup.Size = New-Object System.Drawing.Size($totalWidth, 155)
$statusGroup.Location = New-Object System.Drawing.Point(18, 0)
$form.Controls.Add($statusGroup)

# ----- TOOLTIP: STATUS / ACTIVITY -----
$tooltip.SetToolTip($statusGroup,
    "Displays SAMISH status, diagnostics, and recent activity messages.")

$statusBox = New-Object System.Windows.Forms.TextBox
$statusBox.Multiline = $true
$statusBox.ReadOnly = $true
$statusBox.ScrollBars = "Vertical"
$statusBox.WordWrap = $true
$statusBox.BorderStyle = "FixedSingle"
$statusBoxFont = New-Object System.Drawing.Font("Consolas", 9)
$script:MainFormGdiResources.Add($statusBoxFont)
$statusBox.Font = $statusBoxFont
$statusBox.Size = New-Object System.Drawing.Size(650, 110)
$statusBox.Location = New-Object System.Drawing.Point(15, 30)
$statusGroup.Controls.Add($statusBox)

$script:StatusColorLine = New-Object System.Windows.Forms.Panel
$script:StatusColorLine.Size = New-Object System.Drawing.Size(650, 3)
$script:StatusColorLine.Location = New-Object System.Drawing.Point(15, 142)
$script:StatusColorLine.BackColor = $BrandCyan
$statusGroup.Controls.Add($script:StatusColorLine)

# ----- Live Log (Status Box takeover) -----
$script:IsLiveLogMode = $false
$script:IsLiveLogPaused = $false
$script:LiveLogPath = $null
$script:LiveLogTimer = $null
$script:LiveLogPosition = 0

# Save/restore UI state
$script:SavedStatusGroupText = $null
$script:SavedStatusText = ""
$script:SavedStatusBack = $null
$script:SavedStatusFore = $null
$script:SavedStatusFont = $null

# Tuning
$script:LiveLogMaxChars = 200000   # keep last ~200k chars in the status box
$script:DeferredStatusUpdates = @()   # queue of status updates captured during Live Log mode
$script:DeferredStatusLatest = $null # latest status update captured during Live Log mode

function Update-StatusGroupLiveHeader {
    if (-not $statusGroup) { return }

    if (-not $script:SavedStatusGroupText) {
        $script:SavedStatusGroupText = $statusGroup.Text
    }

    if (-not $script:IsLiveLogMode) {
        $statusGroup.Text = $script:SavedStatusGroupText
        return
    }

    if ($script:IsLiveLogPaused) {
        $statusGroup.Text = "|| LIVE LOG || PAUSED ||"
    }
    else {
        $statusGroup.Text = "|| LIVE LOG ||"
    }
}

function Show-LiveLogControls([bool]$Visible) {
    if ($script:btnLivePause) { $script:btnLivePause.Visible = $Visible }
    if ($script:btnLiveCopy) { $script:btnLiveCopy.Visible = $Visible }
    if ($script:btnLiveClear) { $script:btnLiveClear.Visible = $Visible }
}

function Read-LogTailText {
    param(
        [string]$Path,
        [int]$MaxChars = 200000
    )

    if (-not (Test-Path -LiteralPath $Path)) { return "" }

    $fs = $null
    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)

        # Best-effort: read enough bytes from end to fill MaxChars (UTF-8 worst case ~4 bytes/char)
        $bytesToRead = [Math]::Min([int64]$fs.Length, [int64]($MaxChars * 4))
        $startPos = [Math]::Max([int64]0, [int64]($fs.Length - $bytesToRead))
        $fs.Seek($startPos, [System.IO.SeekOrigin]::Begin) | Out-Null

        $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $true)
        $text = $sr.ReadToEnd()

        if ($text.Length -gt $MaxChars) {
            $text = $text.Substring($text.Length - $MaxChars)
        }

        return $text
    }
    catch {
        return ""
    }
    finally {
        if ($fs) { $fs.Dispose() }
    }
}

function Append-LiveLogChunk {
    param([string]$Path)

    if (-not $script:IsLiveLogMode) { return }
    if ($script:IsLiveLogPaused) { return }
    if (-not (Test-Path -LiteralPath $Path)) { return }

    $fs = $null
    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)

        # Handle truncation/rotation
        if ($script:LiveLogPosition -gt $fs.Length) { $script:LiveLogPosition = 0 }

        $fs.Seek($script:LiveLogPosition, [System.IO.SeekOrigin]::Begin) | Out-Null
        $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $true)
        $newText = $sr.ReadToEnd()
        $script:LiveLogPosition = $fs.Position

        if (-not [string]::IsNullOrEmpty($newText)) {
            $statusBox.AppendText($newText)

            # Hard cap for responsiveness
            $maxChars = $script:LiveLogMaxChars
            if ($statusBox.TextLength -gt $maxChars) {
                $statusBox.Text = $statusBox.Text.Substring($statusBox.TextLength - $maxChars)
                $statusBox.SelectionStart = $statusBox.TextLength
                $statusBox.ScrollToCaret()
            }
        }
    }
    catch {
        # Best effort only
    }
    finally {
        if ($fs) { $fs.Dispose() }
    }
}

function Enter-LiveLogMode {
    $path = Get-VerifiedPreferredLogPathOrShowMessageBox
    if (-not $path) { return }

    $script:IsLiveLogMode = $true
    $script:IsLiveLogPaused = $false
    $script:LiveLogPath = $path

    # Save current UI state
    $script:SavedStatusText = $statusBox.Text
    $script:SavedStatusBack = $statusBox.BackColor
    $script:SavedStatusFore = $statusBox.ForeColor
    $script:SavedStatusFont = $statusBox.Font

    # Dark live theme (matches your earlier live-theme concept) 
    $statusBox.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 35)
    $statusBox.ForeColor = [System.Drawing.Color]::Gainsboro
    if (-not $script:LiveLogFont) {
        $script:LiveLogFont = New-Object System.Drawing.Font("Consolas", 9)
        $script:MainFormGdiResources.Add($script:LiveLogFont)
    }
    $statusBox.Font = $script:LiveLogFont

    if ($script:StatusColorLine) {
        $script:StatusColorLine.BackColor = $BrandPurple
    }

    # Show live-only controls
    Show-LiveLogControls $true
    Update-StatusGroupLiveHeader

    # Load tail up to limit, then start streaming from end
    $tail = Read-LogTailText -Path $path -MaxChars $script:LiveLogMaxChars

    $statusBox.Clear()
    if (-not [string]::IsNullOrEmpty($tail)) {
        $statusBox.AppendText($tail)
        if (-not $tail.EndsWith("`n")) { $statusBox.AppendText("`r`n") }
    }

    # Stream from end going forward
    try {
        $fi = Get-Item -LiteralPath $path
        $script:LiveLogPosition = [int64]$fi.Length
    }
    catch {
        $script:LiveLogPosition = 0
    }

    # Timer
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 350
    $timer.Add_Tick({
            Append-LiveLogChunk -Path $script:LiveLogPath
        })
    $script:LiveLogTimer = $timer
    $timer.Start()

    $btnLiveLog.Text = "Exit Live Log"
}

function Exit-LiveLogMode {
    $script:IsLiveLogMode = $false
    $script:IsLiveLogPaused = $false

    try {
        if ($script:LiveLogTimer) {
            $script:LiveLogTimer.Stop()
            $script:LiveLogTimer.Dispose()
            $script:LiveLogTimer = $null
        }
    }
    catch { }

    # Hide live-only controls
    Show-LiveLogControls $false

    if ($script:StatusColorLine) {
        $script:StatusColorLine.BackColor = $BrandCyan
    }

    # Restore appearance and content
    if ($script:SavedStatusBack) { $statusBox.BackColor = $script:SavedStatusBack }
    if ($script:SavedStatusFore) { $statusBox.ForeColor = $script:SavedStatusFore }
    if ($script:SavedStatusFont) { $statusBox.Font = $script:SavedStatusFont }

    $statusBox.Text = $script:SavedStatusText

    $btnLiveLog.Text = "Live Log"
    Update-StatusGroupLiveHeader
}

function Toggle-LiveLogPause {
    if (-not $script:IsLiveLogMode) { return }
    $script:IsLiveLogPaused = -not $script:IsLiveLogPaused
    Update-StatusGroupLiveHeader
}

# Live-only controls (hidden unless Live Log mode)
$script:btnLivePause = New-Object System.Windows.Forms.Button
$script:btnLivePause.Text = "Pause"
$script:btnLivePause.Size = New-Object System.Drawing.Size(70, 24)
$script:btnLivePause.Visible = $false
$script:btnLivePause.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$script:btnLivePause.BackColor = $BrandCyan
$script:btnLivePause.ForeColor = [System.Drawing.SystemColors]::ControlText
$script:btnLivePause.FlatAppearance.BorderSize = 0
$statusGroup.Controls.Add($script:btnLivePause)

$script:btnLiveCopy = New-Object System.Windows.Forms.Button
$script:btnLiveCopy.Text = "Copy"
$script:btnLiveCopy.Size = New-Object System.Drawing.Size(70, 24)
$script:btnLiveCopy.Visible = $false
$script:btnLiveCopy.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$script:btnLiveCopy.BackColor = $BrandCyan
$script:btnLiveCopy.ForeColor = [System.Drawing.SystemColors]::ControlText
$script:btnLiveCopy.FlatAppearance.BorderSize = 0
$statusGroup.Controls.Add($script:btnLiveCopy)

$script:btnLiveClear = New-Object System.Windows.Forms.Button
$script:btnLiveClear.Text = "Clear"
$script:btnLiveClear.Size = New-Object System.Drawing.Size(70, 24)
$script:btnLiveClear.Visible = $false
$script:btnLiveClear.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$script:btnLiveClear.BackColor = $BrandCyan
$script:btnLiveClear.ForeColor = [System.Drawing.SystemColors]::ControlText
$script:btnLiveClear.FlatAppearance.BorderSize = 0
$statusGroup.Controls.Add($script:btnLiveClear)

# Position them top-right inside the Status group
$btnY = 09
$rightPad = 15
$gap = 6

$script:btnLiveClear.Location = New-Object System.Drawing.Point(
    ($statusGroup.Width - $rightPad - $script:btnLiveClear.Width),
    $btnY
)
$script:btnLiveCopy.Location = New-Object System.Drawing.Point(
    ($script:btnLiveClear.Location.X - $gap - $script:btnLiveCopy.Width),
    $btnY
)
$script:btnLivePause.Location = New-Object System.Drawing.Point(
    ($script:btnLiveCopy.Location.X - $gap - $script:btnLivePause.Width),
    $btnY
)

# Wire actions
$script:btnLivePause.add_Click({
        Toggle-LiveLogPause
        $script:btnLivePause.Text = $(if ($script:IsLiveLogPaused) { "Resume" } else { "Pause" })
    })

$script:btnLiveCopy.add_Click({
        try {
            $textToCopy = $statusBox.SelectedText
            if ([string]::IsNullOrEmpty($textToCopy)) { $textToCopy = $statusBox.Text }
            if (-not [string]::IsNullOrEmpty($textToCopy)) {
                [System.Windows.Forms.Clipboard]::SetText($textToCopy)
            }
        }
        catch { }
    })

$script:btnLiveClear.add_Click({
        if (-not $script:IsLiveLogMode) { return }

        # Clear view but keep streaming from "now"
        $statusBox.Clear()

        try {
            $fi = Get-Item -LiteralPath $script:LiveLogPath
            $script:LiveLogPosition = [int64]$fi.Length
        }
        catch {
            $script:LiveLogPosition = 0
        }
    })

function Apply-UIFromConfigIfPresent {
    $script:IsApplyingConfig = $true
    try {
        if (-not (Test-Path -LiteralPath $ConfigPath)) { return }

        $cfg = (Get-Content -LiteralPath $ConfigPath -Raw) | ConvertFrom-Json

        # Load MonitoredApps from config
        if ($cfg.PSObject.Properties.Name -contains "MonitoredApps" -and $cfg.MonitoredApps) {
            $script:MonitoredApps = @(foreach ($app in $cfg.MonitoredApps) {
                if ($null -eq $app.PSObject.Properties['OnWakeAction']) {
                    $onWake = "Smart"
                    if ($app.PSObject.Properties['NoRestartOnWake'] -and $app.NoRestartOnWake) {
                        $onWake = "KeepClosed"
                    }
                    elseif ($app.PSObject.Properties['ForcePlayOnWake'] -and $app.ForcePlayOnWake) {
                        $onWake = "Play"
                    }
                    $app | Add-Member -MemberType NoteProperty -Name "OnWakeAction" -Value $onWake -Force
                }
                $app
            })
        }
        else {
            $script:MonitoredApps = @()
        }

        # --- Determine installed mode from tasks OR config intent ---
        $hiddenTaskExists = $false
        $interactiveTaskExists = $false
        try { $hiddenTaskExists = Task-Exists -TaskNameWithSlash $TaskHidden } catch {}
        try { $interactiveTaskExists = Task-Exists -TaskNameWithSlash $TaskInteractive } catch {}

        if ($interactiveTaskExists) {
            $rbInteractive.Checked = $true
        }
        elseif ($hiddenTaskExists) {
            $rbHidden.Checked = $true
        }
        else {
            if (
                ($cfg.PSObject.Properties.Name -contains "EnableTrayIcon" -and $cfg.EnableTrayIcon) -or
                ($cfg.PSObject.Properties.Name -contains "EnableHotkey" -and $cfg.EnableHotkey)
            ) {
                $rbInteractive.Checked = $true
            }
            else {
                $rbHidden.Checked = $true
            }
        }

        # --- Operating Mode radios ---
        if ($cfg.PSObject.Properties.Name -contains "OperatingMode") {
            if ($cfg.OperatingMode -eq "Classic") {
                $rbOpClassic.Checked = $true
            }
            else {
                $rbOpGraceful.Checked = $true
            }
        }

        # --- Logging ---
        if ($cfg.PSObject.Properties.Name -contains "EnableLogging") {
            $cbLogging.Checked = [bool]$cfg.EnableLogging
        }

        if ($cfg.PSObject.Properties.Name -contains "LogEverySeconds") {
            $val = 30
            try {
                $rawVal = "$($cfg.LogEverySeconds)"
                $val = Parse-LogEverySecondsOrThrow -RawText $rawVal -ContextLabel "Saved Log interval"
            }
            catch {
                $val = 30
                try {
                    Show-WarningDialog `
                        -Title "SAMISH Configuration Warning" `
                        -Message ("Your saved log interval is invalid or out of range and has been reset to 30 seconds.`r`n`r`nDetails: " + $_.Exception.Message)
                }
                catch {}
            }

            if ($val -eq 0) {
                $ddLogInterval.SelectedItem = "Verbose (every loop)"
                $tbLogCustom.Text = "0"
                $tbLogCustom.Enabled = $false
            }
            elseif ($val -eq 30) {
                $ddLogInterval.SelectedItem = "Every 30 seconds"
                $tbLogCustom.Text = "30"
                $tbLogCustom.Enabled = $false
            }
            elseif ($val -eq 60) {
                $ddLogInterval.SelectedItem = "Every 60 seconds"
                $tbLogCustom.Text = "60"
                $tbLogCustom.Enabled = $false
            }
            else {
                $ddLogInterval.SelectedItem = "Custom seconds..."
                $tbLogCustom.Text = "$val"
                $tbLogCustom.Enabled = $true
            }
        }

        # --- Tray / Hotkey ---
        if ($cfg.PSObject.Properties.Name -contains "EnableTrayIcon") {
            $cbTray.Checked = [bool]$cfg.EnableTrayIcon
        }

        if ($cfg.PSObject.Properties.Name -contains "EnableHotkey") {
            $cbHotkey.Checked = [bool]$cfg.EnableHotkey
        }

        # --- Hotkey mode ---
        if ($cfg.PSObject.Properties.Name -contains "HotkeyMode") {
            $ddHotkey.SelectedItem = [string]$cfg.HotkeyMode
        }

        # --- Custom hotkey textbox reverse-map (VK -> friendly) ---
        if (
            ($cfg.PSObject.Properties.Name -contains "HotkeyMode") -and
            ($cfg.HotkeyMode -eq "Custom") -and
            ($cfg.PSObject.Properties.Name -contains "CustomHotkeyVirtualKey")
        ) {
            $vk = [int]$cfg.CustomHotkeyVirtualKey
            $friendlyKey = $null
            try {
                $friendlyKey = ([System.Windows.Forms.Keys]$vk).ToString()
            }
            catch {
                $friendlyKey = "0x{0:X}" -f $vk
            }
            $tbCustomKey.Text = $friendlyKey
        }

        # --- Apply enable/disable states WITHOUT clobbering values ---
        if ($rbHidden.Checked) {
            $cbTray.Enabled = $false
        }
        else {
            $cbTray.Enabled = $true
        }

        $isCustomHotkey = $false
        if ($ddHotkey.SelectedItem) {
            $isCustomHotkey = ($ddHotkey.SelectedItem.ToString() -eq "Custom")
        }
        $tbCustomKey.Enabled = $isCustomHotkey

        # Refresh the test group now that MonitoredApps and profile data are loaded.
        if (Get-Command Update-TestGroupState -ErrorAction SilentlyContinue) {
            Update-TestGroupState
        }
    }
    catch {
        # Best effort only
    }
    finally {
        $script:IsApplyingConfig = $false
    }
}

# ----- Power plan read-only warning templates (DRY) -----

function Get-PowerPlanBlockTextForUi {
    # Returns exactly the same "Power Plan:" block that diagnostics shows (if available),
    # otherwise best-effort builds the same lines using powercfg reads + friendly formatter.
    try {
        $scheme = Get-ActiveSchemeGuid
        if (-not $scheme) { return "" }

        if (Get-Command Get-PowerPlanDiagnosticsText -ErrorAction SilentlyContinue) {
            # Ideal: reuse the same formatting as diagnostics
            return (Get-PowerPlanDiagnosticsText -SchemeGuid $scheme)
        }

        # Fallback: build the same label format manually
        $displayOff = Get-PowerSettingSecondsAC -SchemeGuid $scheme -SubGuid $SUB_VIDEO -SettingGuid $VIDEOIDLE
        $sleepIdle = Get-PowerSettingSecondsAC -SchemeGuid $scheme -SubGuid $SUB_SLEEP -SettingGuid $STANDBYIDLE
        $hibIdle = Get-PowerSettingSecondsAC -SchemeGuid $scheme -SubGuid $SUB_SLEEP -SettingGuid $HIBERNATEIDLE

        $fmt = {
            param($sec)
            if ($null -eq $sec) { return "Unknown" }
            if (Get-Command Format-SecondsToFriendly -ErrorAction SilentlyContinue) {
                return (Format-SecondsToFriendly -Seconds ([int]$sec))
            }
            if ([int]$sec -eq 0) { return "Disabled" }
            return "$sec seconds"
        }

        $lines = @(
            "Power Plan:",
            ("Screen Off = " + (& $fmt $displayOff)),
            ("Sleep = " + (& $fmt $sleepIdle)),
            ("Hibernate = " + (& $fmt $hibIdle))
        )

        return ($lines -join "`r`n")
    }
    catch {
        return ""
    }
}

function Get-Warn_PowerPlanIncompat_NotInstalled {
    return @(
        "Your current power plan may not be compatible with SAMISH Classic.",
        "",
        "Classic works best when Screen Off occurs at least 60 seconds before Sleep/Hibernate.",
        "",
        "After installation, you can use ""Power Plan: Check / Restore"" to optimize your system if needed.",
        ""
    )
}

function Get-Warn_PowerPlanIncompat_ClassicInstalled {
    # Mirrors the diagnostics "Power Plan:" block exactly (same labels/spacing).
    $lines = @(
        "Your current power plan may prevent SAMISH Classic from functioning as intended.",
        "",
        "No changes are made automatically.",
        ""
    )

    $pp = Get-PowerPlanBlockTextForUi
    if (-not [string]::IsNullOrWhiteSpace($pp)) {
        $lines += ($pp -split "`r?`n")
        $lines += ""
    }

    $lines += "Classic works best when Screen Off occurs at least 60 seconds before Sleep/Hibernate."
    $lines += ""
    $lines += "To resolve this, run ""Power Plan: Check / Restore""."
    $lines += ""

    return $lines
}

function Get-Warn_PowerPlanIncompat_GracefulInstalled {
    return @(
        "Your current power plan is not compatible with SAMISH Classic.",
        "",
        "This does not affect Graceful mode.",
        "",
        "Classic works best when Screen Off occurs at least 60 seconds before Sleep/Hibernate.",
        "",
        "If you switch to Classic mode, run ""Power Plan: Check / Restore"" to ensure proper behavior.",
        ""
    )
}

function Get-PowerPlanReadOnlyWarnings {

    $warnings = @()

    # 1) Backup validity warning
    try {
        if (Get-Command Get-PowerPlanBackupInfo -ErrorAction SilentlyContinue) {
            $b = Get-PowerPlanBackupInfo
            if ($b.Exists -and -not $b.IsValid) {
                $warnings += "A power plan backup file was found, but it appears to be invalid or corrupted."
                $warnings += ""
                $warnings += "SAMISH cannot restore this backup."
                $warnings += ""
                $warnings += "You may delete the backup file and create a new one by applying a power plan fix."
                $warnings += ""
            }
        }
    }
    catch {
        Write-SetupLog ("Read-only backup warning check failed: " + $_.Exception.Message)
    }

    # 2) Compatibility warning (uses OperatingMode, NOT inference)
    try {
        $scheme = Get-ActiveSchemeGuid
        if (-not $scheme) { return $warnings }

        $displayOff = Get-PowerSettingSecondsAC -SchemeGuid $scheme -SubGuid $SUB_VIDEO -SettingGuid $VIDEOIDLE
        $sleepIdle = Get-PowerSettingSecondsAC -SchemeGuid $scheme -SubGuid $SUB_SLEEP -SettingGuid $STANDBYIDLE
        $hibIdle = Get-PowerSettingSecondsAC -SchemeGuid $scheme -SubGuid $SUB_SLEEP -SettingGuid $HIBERNATEIDLE

        if ($null -eq $displayOff -or $null -eq $sleepIdle -or $null -eq $hibIdle) {
            return $warnings
        }

        $t = Test-PowerPlanCompatibility `
            -DisplayOffSeconds $displayOff `
            -SleepIdleSeconds $sleepIdle `
            -HibernateIdleSeconds $hibIdle `
            -GapSeconds $MinGapSeconds

        if (-not $t -or $t.Compatible) {
            return $warnings
        }

        $configExists = Test-Path -LiteralPath $ConfigPath
        $operatingMode = $null

        if ($configExists) {
            try {
                $cfg = (Get-Content -LiteralPath $ConfigPath -Raw) | ConvertFrom-Json
                if ($cfg.PSObject.Properties.Name -contains "OperatingMode") {
                    $operatingMode = $cfg.OperatingMode
                }
            }
            catch { }
        }

        if (-not $configExists) {
            $warnings += (Get-Warn_PowerPlanIncompat_NotInstalled)
        }
        elseif ($operatingMode -ieq "Classic") {
            $warnings += (Get-Warn_PowerPlanIncompat_ClassicInstalled)
        }
        elseif ($operatingMode -ieq "Graceful") {
            $warnings += (Get-Warn_PowerPlanIncompat_GracefulInstalled)
        }
        else {
            # Fallback if OperatingMode is missing/unknown but config exists
            $warnings += (Get-Warn_PowerPlanIncompat_NotInstalled)
        }

    }
    catch {
        Write-SetupLog ("Read-only power plan warning check failed: " + $_.Exception.Message)
    }

    return $warnings
}
function Handle-PowerPlanPromptIfNeeded {
    param(
        $result,
        [bool]$AutoMode
    )

    if (-not $result) { return $null }
    if (-not $result.NeedsPrompt) { return $result }

    $icon = [System.Windows.Forms.MessageBoxIcon]::Question

    try {
        switch ($result.PromptIcon) {
            "Warning" { $icon = [System.Windows.Forms.MessageBoxIcon]::Warning }
            "Information" { $icon = [System.Windows.Forms.MessageBoxIcon]::Information }
            "Error" { $icon = [System.Windows.Forms.MessageBoxIcon]::Error }
        }
    }
    catch {}

    $res = [System.Windows.Forms.MessageBox]::Show(
        $result.PromptText,
        $result.PromptTitle,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        $icon
    )

    $accepted = ($res -eq [System.Windows.Forms.DialogResult]::Yes)

    switch ($result.PromptId) {

        "CompatFix" {
            return Apply-PowerPlanFixWithBackup `
                -PromptUser:$true `
                -AutoMode:$AutoMode `
                -UserAcceptedBaseline $null `
                -UserAcceptedCompatFix $accepted
        }

        "CompatFixMinEdge" {
            return Apply-PowerPlanFixWithBackup `
                -PromptUser:$true `
                -AutoMode:$AutoMode `
                -UserAcceptedBaseline $null `
                -UserAcceptedCompatFix $accepted
        }

        "TempBaseline" {
            return Apply-PowerPlanFixWithBackup `
                -PromptUser:$true `
                -AutoMode:$AutoMode `
                -UserAcceptedBaseline $accepted
        }

        "RestoreBackup" {
            if ($accepted) {
                return Restore-PowerPlanFromBackup
            }
            else {
                # âœ… Continue path (no dead-end)
                return Apply-PowerPlanFixWithBackup -PromptUser:$true -AutoMode:$AutoMode
            }
        }

        default {
            return (Get-UnknownPowerPlanPromptStatus -PromptId $result.PromptId)
        }
    }
}

# ---------- Tools ----------
$toolsGroup = New-Object System.Windows.Forms.GroupBox
$toolsGroup.Text = "Tools"
$toolsGroup.Font = $font
$toolsGroup.ForeColor = $BrandPurple
$toolsGroup.Size = New-Object System.Drawing.Size($totalWidth, 125)
$toolsGroup.Location = New-Object System.Drawing.Point(18, 0)
$form.Controls.Add($toolsGroup)

# ----- TOOLTIP: TOOLS GROUP -----
$tooltip.SetToolTip($toolsGroup,
    "Utility tools for checking status, managing logs, and maintaining SAMISH.")

# ----- CREATE BUTTONS (NO LOCATION YET) -----

$btnPowerPlan = New-Object System.Windows.Forms.Button
$btnPowerPlan.Text = "Power Plan: Check / Restore"
$btnPowerPlan.Font = $font
$btnPowerPlan.Size = New-Object System.Drawing.Size(200, 32)
$toolsGroup.Controls.Add($btnPowerPlan)

$btnOpenTS = New-Object System.Windows.Forms.Button
$btnOpenTS.Text = "Open Task Scheduler"
$btnOpenTS.Font = $font
$btnOpenTS.Size = New-Object System.Drawing.Size(200, 32)
$toolsGroup.Controls.Add($btnOpenTS)

$btnCleanReset = New-Object System.Windows.Forms.Button
$btnCleanReset.Text = "Clean Reset"
$btnCleanReset.Font = $font
$btnCleanReset.Size = New-Object System.Drawing.Size(110, 32)
$toolsGroup.Controls.Add($btnCleanReset)

$btnReadSetup = New-Object System.Windows.Forms.Button
$btnReadSetup.Text = "Read Setup"
$btnReadSetup.Font = $font
$btnReadSetup.Size = New-Object System.Drawing.Size(142, 32)
$toolsGroup.Controls.Add($btnReadSetup)

$btnOpenLog = New-Object System.Windows.Forms.Button
$btnOpenLog.Text = "Open Log"
$btnOpenLog.Font = $font
$btnOpenLog.Size = New-Object System.Drawing.Size(110, 32)
$toolsGroup.Controls.Add($btnOpenLog)

$btnLiveLog = New-Object System.Windows.Forms.Button
$btnLiveLog.Text = "Live Log"
$btnLiveLog.Font = $font
$btnLiveLog.Size = New-Object System.Drawing.Size(110, 32)
$toolsGroup.Controls.Add($btnLiveLog)

$btnSleepDiag = New-Object System.Windows.Forms.Button
$btnSleepDiag.Text = "Sleep Diagnostics"
$btnSleepDiag.Font = $font
$btnSleepDiag.Size = New-Object System.Drawing.Size(136, 32)
$toolsGroup.Controls.Add($btnSleepDiag)

# ----- POSITION BUTTONS -----

# Row 1 (System Tools) - Y = 30
$btnPowerPlan.Location = New-Object System.Drawing.Point(18, 30)
$btnOpenTS.Location = New-Object System.Drawing.Point((18 + 200 + $gapX), 30)
$btnCleanReset.Location = New-Object System.Drawing.Point((18 + 200 + $gapX + 200 + $gapX), 30)

# Row 2 (Log Diagnostics) - Y = 78
$btnReadSetup.Location = New-Object System.Drawing.Point(18, 78)
$btnOpenLog.Location = New-Object System.Drawing.Point((18 + 142 + $gapX), 78)
$btnLiveLog.Location = New-Object System.Drawing.Point((18 + 142 + $gapX + 110 + $gapX), 78)
$btnSleepDiag.Location = New-Object System.Drawing.Point((18 + 142 + $gapX + 110 + $gapX + 110 + $gapX), 78)

# ----- TOOLTIPS -----
$tooltip.SetToolTip($btnPowerPlan, "Check and fix or restore your power plan.")
$tooltip.SetToolTip($btnOpenTS, "Open Windows Task Scheduler to view or manage SAMISH tasks.")
$tooltip.SetToolTip($btnCleanReset, "Stops all running SAMISH instances.

SAMISH will restart automatically in the currently installed mode (Hidden or Interactive).")
$tooltip.SetToolTip($btnReadSetup, "View current configuration and SAMISH status.")
$tooltip.SetToolTip($btnLiveLog, "Watch the log file in real time.")
$tooltip.SetToolTip($btnOpenLog, "Open the log file.")
$tooltip.SetToolTip($btnSleepDiag, "Scan for sleep-blocking items and applications. Configure settings to allow sleep when items/applications are present.")

# ---------- Main buttons ----------
$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = "Install / Update"
$btnInstall.Font = $font
$btnInstall.Size = New-Object System.Drawing.Size(160, 36)
$btnInstall.Location = New-Object System.Drawing.Point(18, 0)
$form.Controls.Add($btnInstall)

$btnUninstall = New-Object System.Windows.Forms.Button
$btnUninstall.Text = "Uninstall"
$btnUninstall.Font = $font
$btnUninstall.Size = New-Object System.Drawing.Size(110, 36)
$btnUninstall.Location = New-Object System.Drawing.Point(188, 0)
$form.Controls.Add($btnUninstall)

$tooltip.SetToolTip($btnInstall, "Install or update SAMISH using the selected settings.")
$tooltip.SetToolTip($btnUninstall, "Remove SAMISH scheduled tasks and stop it from running.")

# ---------- Apply Place-Below stacking ----------
# testGroup sits between the side-by-side mode boxes and General Settings.
Place-Below $modeGroup    $testGroup   12
Place-Below $testGroup    $cfgGroup    12
Place-Below $cfgGroup     $deviceGroup 12
Place-Below $deviceGroup  $statusGroup 12
Place-Below $statusGroup  $toolsGroup  12

# Align bottom row buttons to the left margin
$bottomY = ($toolsGroup.Location.Y + $toolsGroup.Height + 16)

$btnInstall.Location = New-Object System.Drawing.Point(18, $bottomY)
$btnUninstall.Location = New-Object System.Drawing.Point((18 + 160 + $gapX), $bottomY)

# ---------- Recursive Styling Reset for Main Window ----------
function Reset-MainFormChildControls {
    param($container)
    foreach ($ctrl in $container.Controls) {
        if ($ctrl.Name -ne "statusBox") {
            $ctrl.Font = $font
        }
        $ctrl.ForeColor = [System.Drawing.SystemColors]::ControlText
        if ($ctrl.Controls.Count -gt 0) {
            Reset-MainFormChildControls $ctrl
        }
    }
}

$boldFont = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$script:MainFormGdiResources.Add($boldFont)
foreach ($grp in @($modeGroup, $opGroup, $cfgGroup, $deviceGroup, $statusGroup, $toolsGroup)) {
    $grp.Font = $boldFont
    $grp.ForeColor = $BrandPurple
    Reset-MainFormChildControls $grp
}

# Style the dynamic test group box and reset its child control forecolors to match others
$testGroup.Font = $boldFont
Reset-MainFormChildControls $testGroup

# ---------- Bottom Metadata ----------
$bottomMetadata = New-Object System.Windows.Forms.Label
$bottomMetadata.Text = "$ProductName $ProductVersion  |  $AuthorLine"
$bottomMetadataFont = New-Object System.Drawing.Font("Segoe UI", 9)
$script:MainFormGdiResources.Add($bottomMetadataFont)
$bottomMetadata.Font = $bottomMetadataFont
$bottomMetadata.ForeColor = $BrandCyan
$bottomMetadata.AutoSize = $false
$bottomMetadata.Size = New-Object System.Drawing.Size(300, 20)
$bottomMetadata.TextAlign = [System.Drawing.ContentAlignment]::TopRight
# Calculate X to right-align with the tools group right edge using fixed width
$metadataX = ($toolsGroup.Location.X + $toolsGroup.Width) - 300
$bottomMetadata.Location = New-Object System.Drawing.Point($metadataX, ($bottomY + $btnInstall.Height + 12))
$form.Controls.Add($bottomMetadata)

$form.ClientSize = New-Object System.Drawing.Size($form.ClientSize.Width, ($bottomY + $btnInstall.Height + 40))

function Show-SleepDiagnosticsDialog {
    $diagGdiResources = New-Object System.Collections.Generic.List[System.IDisposable]
    $diagForm = $null
    try {
        # ---- Window shell ----
        $diagForm = New-Object System.Windows.Forms.Form
        $diagForm.Text = "Sleep & Hibernate Diagnostics"
        $diagForm.StartPosition = "CenterParent"
        $diagForm.FormBorderStyle = "FixedDialog"
        $diagForm.MaximizeBox = $false
        $diagForm.MinimizeBox = $false
        $diagForm.ClientSize = New-Object System.Drawing.Size(720, 693)
        if ($form.Icon) { $diagForm.Icon = $form.Icon }

        $diagTip = New-Object System.Windows.Forms.ToolTip
        $diagTip.AutoPopDelay = 8000
        $diagTip.InitialDelay = 400
        $diagTip.ReshowDelay = 200

        # ---- SAMISH branding header ----
        $diagTitle = New-Object System.Windows.Forms.Label
        $diagTitle.Text = "SAMISH"
        $diagTitleFont = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
        $diagGdiResources.Add($diagTitleFont)
        $diagTitle.Font = $diagTitleFont
        $diagTitle.ForeColor = $BrandPurple
        $diagTitle.AutoSize = $true
        $diagTitle.Location = New-Object System.Drawing.Point(16, 12)
        $diagForm.Controls.Add($diagTitle)

        $diagSubtitle = New-Object System.Windows.Forms.Label
        $diagSubtitle.Text = "Sleep & Hibernate Diagnostics"
        $diagSubtitleFont = New-Object System.Drawing.Font("Segoe UI", 10)
        $diagGdiResources.Add($diagSubtitleFont)
        $diagSubtitle.Font = $diagSubtitleFont
        $diagSubtitle.ForeColor = $BrandCyan
        $diagSubtitle.AutoSize = $true
        $diagSubtitle.UseMnemonic = $false
        $diagSubtitle.Location = New-Object System.Drawing.Point(18, 52)
        $diagForm.Controls.Add($diagSubtitle)

        # Logo top-right
        $diagLogo = New-Object System.Windows.Forms.PictureBox
        $diagLogo.Size = New-Object System.Drawing.Size(52, 52)
        $diagLogo.Location = New-Object System.Drawing.Point(652, 12)
        $diagLogo.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Normal
        $logoPath = Join-Path $PackageDir "Assets\SAMISH-SQUARE-STYLIZED.png"
        if (Test-Path -LiteralPath $logoPath) {
            $diagLogoImage = Get-HighQualityScaledImage -Path $logoPath -Width 52 -Height 52
            if ($diagLogoImage) {
                $diagGdiResources.Add($diagLogoImage)
                $diagLogo.Image = $diagLogoImage
            }
        }
        $diagForm.Controls.Add($diagLogo)

        # Separator line under header
        $diagSep = New-Object System.Windows.Forms.Label
        $diagSep.Size = New-Object System.Drawing.Size(688, 2)
        $diagSep.Location = New-Object System.Drawing.Point(16, 78)
        $diagSep.BackColor = $BrandCyan
        $diagForm.Controls.Add($diagSep)

        # Info text
        $infoLabel = New-Object System.Windows.Forms.Label
        $infoLabel.Text = "Windows cannot sleep or hibernate if applications, audio drivers, or services hold active power requests. Use this tool to identify and resolve blockers, or configure SAMISH to automatically manage them for you."
        $infoLabelFont = New-Object System.Drawing.Font("Segoe UI", 9)
        $diagGdiResources.Add($infoLabelFont)
        $infoLabel.Font = $infoLabelFont
        $infoLabel.Size = New-Object System.Drawing.Size(688, 40)
        $infoLabel.Location = New-Object System.Drawing.Point(16, 88)
        $diagForm.Controls.Add($infoLabel)

        # =============================================
        # LEFT COLUMN - Active Blockers + System Overrides
        # =============================================
        $leftX = 16
        $colW = 330

        # --- Active Blockers group ---
        $grpBlockers = New-Object System.Windows.Forms.GroupBox
        $grpBlockers.Text = "Active Blockers"
        $grpBlockersFont = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $diagGdiResources.Add($grpBlockersFont)
        $grpBlockers.Font = $grpBlockersFont
        $grpBlockers.ForeColor = $BrandPurple
        $grpBlockers.Size = New-Object System.Drawing.Size($colW, 210)
        $grpBlockers.Location = New-Object System.Drawing.Point($leftX, 136)
        $diagForm.Controls.Add($grpBlockers)
        $diagTip.SetToolTip($grpBlockers, "Applications, drivers, and services currently holding a power request that prevents sleep or hibernation.")

        $script:listBlockers = New-Object System.Windows.Forms.ListBox
        $script:listBlockers.Font = $font
        $script:listBlockers.Size = New-Object System.Drawing.Size(310, 136)
        $script:listBlockers.Location = New-Object System.Drawing.Point(10, 25)
        $script:listBlockers.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
        $grpBlockers.Controls.Add($script:listBlockers)

        $lblBlockerHint = New-Object System.Windows.Forms.Label
        $lblBlockerHint.Text = "Tip: To automate a silent or closed browser/media app, open it and play some media, then click Scan."
        $lblBlockerHintFont = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
        $diagGdiResources.Add($lblBlockerHintFont)
        $lblBlockerHint.Font = $lblBlockerHintFont
        $lblBlockerHint.ForeColor = [System.Drawing.Color]::DimGray
        $lblBlockerHint.Size = New-Object System.Drawing.Size(310, 34)
        $lblBlockerHint.Location = New-Object System.Drawing.Point(10, 168)
        $grpBlockers.Controls.Add($lblBlockerHint)

        # Blocker action buttons row (resized, renamed and positioned with 18px spacing)
        $btnDiagScan = New-Object System.Windows.Forms.Button
        $btnDiagScan.Text = "Scan"
        $btnDiagScan.Font = $font
        $btnDiagScan.Size = New-Object System.Drawing.Size(98, 30)
        $btnDiagScan.Location = New-Object System.Drawing.Point($leftX, 354)
        $diagForm.Controls.Add($btnDiagScan)
        $diagTip.SetToolTip($btnDiagScan, "Scan Windows for all active power requests that are currently preventing sleep or hibernation.")

        $btnDiagIgnore = New-Object System.Windows.Forms.Button
        $btnDiagIgnore.Text = "Ignore"
        $btnDiagIgnore.Font = $font
        $btnDiagIgnore.Size = New-Object System.Drawing.Size(98, 30)
        $btnDiagIgnore.Location = New-Object System.Drawing.Point(($leftX + 116), 354)
        $btnDiagIgnore.Enabled = $false
        $diagForm.Controls.Add($btnDiagIgnore)
        $diagTip.SetToolTip($btnDiagIgnore, "Tell Windows to ignore this blocker's power request so it no longer prevents sleep or hibernation. This works for drivers and services as well as apps.")

        $btnDiagAutomate = New-Object System.Windows.Forms.Button
        $btnDiagAutomate.Text = "Automate"
        $btnDiagAutomate.Font = $font
        $btnDiagAutomate.Size = New-Object System.Drawing.Size(98, 30)
        $btnDiagAutomate.Location = New-Object System.Drawing.Point(($leftX + 232), 354)
        $btnDiagAutomate.Enabled = $false
        $diagForm.Controls.Add($btnDiagAutomate)
        $diagTip.SetToolTip($btnDiagAutomate, "Configure SAMISH to automatically close this application before sleep or hibernation, and restart it when the system wakes - using the operating mode you select below.")

        # --- System Overrides group ---
        $grpOverrides = New-Object System.Windows.Forms.GroupBox
        $grpOverrides.Text = "Ignored Blockers (System Overrides)"
        $grpOverridesFont = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $diagGdiResources.Add($grpOverridesFont)
        $grpOverrides.Font = $grpOverridesFont
        $grpOverrides.ForeColor = $BrandPurple
        $grpOverrides.Size = New-Object System.Drawing.Size($colW, 218)
        $grpOverrides.Location = New-Object System.Drawing.Point($leftX, 396)
        $diagForm.Controls.Add($grpOverrides)
        $diagTip.SetToolTip($grpOverrides, "Blockers currently configured to be ignored by Windows - they will not prevent sleep or hibernation.")

        $script:listOverrides = New-Object System.Windows.Forms.ListBox
        $script:listOverrides.Font = $font
        $script:listOverrides.Size = New-Object System.Drawing.Size(310, 110)
        $script:listOverrides.Location = New-Object System.Drawing.Point(10, 25)
        $grpOverrides.Controls.Add($script:listOverrides)

        # Placed inside overrides box to avoid covering details text
        $btnDiagRestore = New-Object System.Windows.Forms.Button
        $btnDiagRestore.Text = "Restore"
        $btnDiagRestore.Font = $font
        $btnDiagRestore.ForeColor = [System.Drawing.SystemColors]::ControlText
        $btnDiagRestore.Size = New-Object System.Drawing.Size(150, 30)
        $btnDiagRestore.Location = New-Object System.Drawing.Point(10, 178)
        $btnDiagRestore.Enabled = $false
        $grpOverrides.Controls.Add($btnDiagRestore)
        $diagTip.SetToolTip($btnDiagRestore, "Remove the override and let this item's power requests once again affect sleep and hibernation behaviour.")

        # =============================================
        # RIGHT COLUMN - Automated Apps + Operating Mode
        # =============================================
        $rightX = 362
        $colW2 = 342

        # --- Automated Apps group ---
        $grpAutomated = New-Object System.Windows.Forms.GroupBox
        $grpAutomated.Text = "SAMISH Automated Apps"
        $grpAutomatedFont = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $diagGdiResources.Add($grpAutomatedFont)
        $grpAutomated.Font = $grpAutomatedFont
        $grpAutomated.ForeColor = $BrandPurple
        $grpAutomated.Size = New-Object System.Drawing.Size($colW2, 210)
        $grpAutomated.Location = New-Object System.Drawing.Point($rightX, 136)
        $diagForm.Controls.Add($grpAutomated)
        $diagTip.SetToolTip($grpAutomated, "Applications that SAMISH will automatically close before sleep or hibernation, and restart on wake.")

        $script:listAutomated = New-Object System.Windows.Forms.ListBox
        $script:listAutomated.Font = $font
        $script:listAutomated.Size = New-Object System.Drawing.Size(322, 170)
        $script:listAutomated.Location = New-Object System.Drawing.Point(10, 25)
        $grpAutomated.Controls.Add($script:listAutomated)

        $btnDiagStopAuto = New-Object System.Windows.Forms.Button
        $btnDiagStopAuto.Text = "Stop Automating"
        $btnDiagStopAuto.Font = $font
        $btnDiagStopAuto.Size = New-Object System.Drawing.Size(150, 30)
        $btnDiagStopAuto.Location = New-Object System.Drawing.Point($rightX, 354)
        $btnDiagStopAuto.Enabled = $false
        $diagForm.Controls.Add($btnDiagStopAuto)
        $diagTip.SetToolTip($btnDiagStopAuto, "Remove this application from SAMISH automation. It will no longer be closed before sleep or hibernation, or restarted on wake.")

        $btnDiagOpenLocation = New-Object System.Windows.Forms.Button
        $btnDiagOpenLocation.Text = "Open Location"
        $btnDiagOpenLocation.Font = $font
        $btnDiagOpenLocation.Size = New-Object System.Drawing.Size(150, 30)
        # Aligned right-side of Open Location with right-side of Automated Apps group
        $btnDiagOpenLocation.Location = New-Object System.Drawing.Point(($rightX + $colW2 - 150), 354)
        $btnDiagOpenLocation.Enabled = $false
        $diagForm.Controls.Add($btnDiagOpenLocation)
        $diagTip.SetToolTip($btnDiagOpenLocation, "Open the installation folder for this application in Windows File Explorer.")

        # --- Operating Mode group ---
        $grpOperatingMode = New-Object System.Windows.Forms.GroupBox
        $grpOperatingMode.Text = "Operating Mode"
        $grpOperatingModeFont = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $diagGdiResources.Add($grpOperatingModeFont)
        $grpOperatingMode.Font = $grpOperatingModeFont
        $grpOperatingMode.ForeColor = $BrandPurple
        $grpOperatingMode.Size = New-Object System.Drawing.Size($colW2, 218)
        $grpOperatingMode.Location = New-Object System.Drawing.Point($rightX, 396)
        $diagForm.Controls.Add($grpOperatingMode)
        $diagTip.SetToolTip($grpOperatingMode, "Choose how SAMISH recovers this application before sleep and when the system wakes. Select an application from the lists to configure these options.")

        # "Before Sleep:" label
        $lblBeforeSleep = New-Object System.Windows.Forms.Label
        $lblBeforeSleep.Text = "Before Sleep:"
        $lblBeforeSleepFont = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $diagGdiResources.Add($lblBeforeSleepFont)
        $lblBeforeSleep.Font = $lblBeforeSleepFont
        $lblBeforeSleep.ForeColor = $BrandPurple
        $lblBeforeSleep.AutoSize = $true
        $lblBeforeSleep.Location = New-Object System.Drawing.Point(12, 22)
        $grpOperatingMode.Controls.Add($lblBeforeSleep)

        # Radios
        $rbGraceful = New-Object System.Windows.Forms.RadioButton
        $rbGraceful.Text = "Close App (Graceful)"
        $rbGraceful.Font = $font
        $rbGraceful.ForeColor = [System.Drawing.SystemColors]::ControlText
        $rbGraceful.Checked = $true
        $rbGraceful.AutoSize = $true
        $rbGraceful.Location = New-Object System.Drawing.Point(12, 46)
        $grpOperatingMode.Controls.Add($rbGraceful)
        $diagTip.SetToolTip($rbGraceful, "Close App (Graceful): Asks the application to close itself cleanly before sleep or hibernation, allowing it to save open files.")

        $rbClassic = New-Object System.Windows.Forms.RadioButton
        $rbClassic.Text = "Close App (Classic)"
        $rbClassic.Font = $font
        $rbClassic.ForeColor = [System.Drawing.SystemColors]::ControlText
        $rbClassic.AutoSize = $true
        $rbClassic.Location = New-Object System.Drawing.Point(12, 70)
        $grpOperatingMode.Controls.Add($rbClassic)
        $diagTip.SetToolTip($rbClassic, "Close App (Classic): Immediately terminates the application before sleep or hibernation. More reliable, but unsaved work may be lost.")

        $rbPauseMedia = New-Object System.Windows.Forms.RadioButton
        $rbPauseMedia.Text = "Keep App Open (Media Control)"
        $rbPauseMedia.Font = $font
        $rbPauseMedia.ForeColor = [System.Drawing.SystemColors]::ControlText
        $rbPauseMedia.AutoSize = $true
        $rbPauseMedia.Location = New-Object System.Drawing.Point(12, 94)
        $grpOperatingMode.Controls.Add($rbPauseMedia)
        $diagTip.SetToolTip($rbPauseMedia, "Keep App Open (Media Control): Pauses the application's media playback (via Windows SMTC) before sleep or hibernation instead of closing the application. This is ideal for web browsers to prevent losing open tabs.")

        # "On Wake Action:" label
        $lblOnWake = New-Object System.Windows.Forms.Label
        $lblOnWake.Text = "On Wake Action:"
        $lblOnWakeFont = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $diagGdiResources.Add($lblOnWakeFont)
        $lblOnWake.Font = $lblOnWakeFont
        $lblOnWake.ForeColor = $BrandPurple
        $lblOnWake.AutoSize = $true
        $lblOnWake.Location = New-Object System.Drawing.Point(12, 128)
        $grpOperatingMode.Controls.Add($lblOnWake)
        $diagTip.SetToolTip($lblOnWake, "Choose what action SAMISH will perform when the system wakes: Smart Restore restores the pre-sleep state; Always Play forces playback; Always Pause keeps media paused; Keep Closed prevents app restart; Reopen Only restarts the app but keeps media paused.")

        # Dropdown ComboBox
        $ddOnWakeAction = New-Object System.Windows.Forms.ComboBox
        $ddOnWakeAction.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $ddOnWakeAction.Font = $font
        $ddOnWakeAction.Size = New-Object System.Drawing.Size(310, 24)
        $ddOnWakeAction.Location = New-Object System.Drawing.Point(12, 152)
        $grpOperatingMode.Controls.Add($ddOnWakeAction)
        $diagTip.SetToolTip($ddOnWakeAction, "Choose what action SAMISH will perform when the system wakes.")

        # ---- Detail / status bar ----
        $script:lblDiagDetail = New-Object System.Windows.Forms.Label
        $script:lblDiagDetail.Text = "Select an item from the Active Blockers list to see details, or click Scan Blockers."
        $lblDiagDetailFont = New-Object System.Drawing.Font("Segoe UI", 8.5)
        $diagGdiResources.Add($lblDiagDetailFont)
        $script:lblDiagDetail.Font = $lblDiagDetailFont
        $script:lblDiagDetail.ForeColor = [System.Drawing.Color]::DimGray
        $script:lblDiagDetail.AutoSize = $false
        $script:lblDiagDetail.Size = New-Object System.Drawing.Size(688, 40)
        $script:lblDiagDetail.Location = New-Object System.Drawing.Point(16, 628)
        $diagForm.Controls.Add($script:lblDiagDetail)

        # ---- Store references for event handler module ----
        $script:diagForm = $diagForm
        $script:btnDiagScan = $btnDiagScan
        $script:btnDiagAutomate = $btnDiagAutomate
        $script:btnDiagIgnore = $btnDiagIgnore
        $script:btnDiagRestore = $btnDiagRestore
        $script:btnDiagStopAuto = $btnDiagStopAuto
        $script:btnDiagOpenLocation = $btnDiagOpenLocation
        $script:rbDiagGraceful = $rbGraceful
        $script:rbDiagClassic = $rbClassic
        $script:rbDiagPauseMedia = $rbPauseMedia
        $script:ddDiagOnWakeAction = $ddOnWakeAction
        $script:grpDiagOperatingMode = $grpOperatingMode
        $script:diagTip = $diagTip

        # ---- Set initial greyed-out state for Operating Mode box ----
        # GroupBox itself stays Enabled so its tooltip remains hoverable.
        # Only its child controls are disabled, and the title is manually greyed.
        $grpOperatingMode.ForeColor = [System.Drawing.Color]::Gray
        foreach ($ctrl in $grpOperatingMode.Controls) { $ctrl.Enabled = $false }

        # ---- Delegate wiring to event-handlers module ----
        if (Get-Command Init-SleepDiagnosticsEventHandlers -ErrorAction SilentlyContinue) {
            Init-SleepDiagnosticsEventHandlers
        }

        [void]$diagForm.ShowDialog()
    }
    finally {
        # Clean up local GDI resources specifically allocated for this dialog run
        foreach ($res in $diagGdiResources) {
            if ($res) {
                try { $res.Dispose() } catch {}
            }
        }
        $diagGdiResources.Clear()

        # Clean up any active timers to prevent background resource leaks
        if ($script:lblDiagDetailFlashTimer) {
            try {
                $script:lblDiagDetailFlashTimer.Stop()
                $script:lblDiagDetailFlashTimer.Dispose()
            } catch {}
            $script:lblDiagDetailFlashTimer = $null
        }
        if ($script:diagFlashTimer) {
            try {
                $script:diagFlashTimer.Stop()
                $script:diagFlashTimer.Dispose()
            } catch {}
            $script:diagFlashTimer = $null
        }
        if ($script:PathTimer) {
            try {
                $script:PathTimer.Stop()
                $script:PathTimer.Dispose()
            } catch {}
            $script:PathTimer = $null
        }
        if ($script:DiagTimer) {
            try {
                $script:DiagTimer.Stop()
                $script:DiagTimer.Dispose()
            } catch {}
            $script:DiagTimer = $null
        }

        # Clean up form
        if ($diagForm) {
            try { $diagForm.Dispose() } catch {}
        }
    }
}
