# ---------- UI ----------
$script:MainFormGdiResources = New-Object System.Collections.Generic.List[System.IDisposable]

# ---------- TOOLTIP WORD-WRAP HELPER ----------
function Format-WrappedText {
    param(
        [string]$Text,
        [int]$MaxLineLength = 70
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    $paragraphs = $Text -split "`r?`n"
    $wrappedParagraphs = @()
    foreach ($para in $paragraphs) {
        if ([string]::IsNullOrWhiteSpace($para)) {
            $wrappedParagraphs += ""
            continue
        }
        $words = $para -split "\s+"
        $currentLine = ""
        $wrappedLines = @()
        foreach ($word in $words) {
            if ([string]::IsNullOrEmpty($currentLine)) {
                $currentLine = $word
            }
            elseif (($currentLine.Length + 1 + $word.Length) -le $MaxLineLength) {
                $currentLine += " " + $word
            }
            else {
                $wrappedLines += $currentLine
                $currentLine = $word
            }
        }
        if (-not [string]::IsNullOrEmpty($currentLine)) {
            $wrappedLines += $currentLine
        }
        $wrappedParagraphs += ($wrappedLines -join "`r`n")
    }
    return ($wrappedParagraphs -join "`r`n")
}

# Wrap the global $tooltip object in a PSCustomObject that intercepts SetToolTip calls
if ($tooltip -and $tooltip -is [System.Windows.Forms.ToolTip]) {
    $realTooltip = $tooltip
    $tooltipWrapper = [PSCustomObject]@{
        RealTooltip = $realTooltip
    }
    $tooltipWrapper | Add-Member -MemberType ScriptMethod -Name "SetToolTip" -Value {
        param($control, $text)
        $wrapped = Format-WrappedText -Text $text -MaxLineLength 70
        $this.RealTooltip.SetToolTip($control, $wrapped)
    }
    # Update the global and script-level references
    $tooltip = $tooltipWrapper
    $script:tooltip = $tooltipWrapper
}


function Get-HighQualityScaledImage {
    param(
        [string]$Path,
        [int]$Width,
        [int]$Height
    )
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
$form.ClientSize = New-Object System.Drawing.Size(800, 640)

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
$boldFont = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$script:MainFormGdiResources.Add($boldFont)

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
$logo.Location = New-Object System.Drawing.Point(718, 12)
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
$script:logo = $logo

# Separator line under header (matching diagnostics window style)
$mainSep = New-Object System.Windows.Forms.Label
$mainSep.Size = New-Object System.Drawing.Size(764, 2)
$mainSep.Location = New-Object System.Drawing.Point(18, 84)
$mainSep.BackColor = $BrandCyan
$form.Controls.Add($mainSep)
$script:mainSep = $mainSep

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
        $ctrl.Enabled = $shouldEnable
    }

    # --- Update GroupBox title color (flash when enabling, grey when disabling) ---
    if ($shouldEnable) {
        # Kill any previous flash timer to prevent race conditions
        if ($script:testGroupFlashTimer) {
            try { $script:testGroupFlashTimer.Stop(); $script:testGroupFlashTimer.Dispose() } catch {}
            $script:testGroupFlashTimer = $null
        }

        # Triple-flash: Cyan -> ControlText (6 ticks at 180ms each, ends on ControlText)
        $script:testGroup.ForeColor = $BrandCyan
        try { $script:testGroup.Refresh() } catch {}
        $script:testGroupFlashTick = 0
        $script:testGroupFlashTimer = New-Object System.Windows.Forms.Timer
        $script:testGroupFlashTimer.Interval = 180
        $script:testGroupFlashTimer.add_Tick({
                $script:testGroupFlashTick++
                if ($script:testGroupFlashTick % 2 -eq 0) {
                    $script:testGroup.ForeColor = $BrandCyan
                }
                else {
                    $script:testGroup.ForeColor = [System.Drawing.SystemColors]::ControlText
                }
                if ($script:testGroupFlashTick -ge 5) {
                    $script:testGroup.ForeColor = [System.Drawing.SystemColors]::ControlText
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
$lblLogInterval.Text = "Interval:"
$lblLogInterval.AutoSize = $true
$lblLogInterval.Location = New-Object System.Drawing.Point(35, 62)
$cfgGroup.Controls.Add($lblLogInterval)

$ddLogInterval = New-Object System.Windows.Forms.ComboBox
$ddLogInterval.DropDownStyle = "DropDownList"
$ddLogInterval.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
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
$ddHotkey.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
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
$lblProc.Location = New-Object System.Drawing.Point(0, 18)
$detailsPanel.Controls.Add($lblProc)
$lblPath = New-Object System.Windows.Forms.Label
$lblPath.Text = "Path: (unknown)"
$lblPath.AutoSize = $true
$lblPath.MaximumSize = New-Object System.Drawing.Size(340, 0)
$lblPath.Location = New-Object System.Drawing.Point(0, 36)
$detailsPanel.Controls.Add($lblPath)

$lblCaps = New-Object System.Windows.Forms.Label
$lblCaps.Text = "Supports: (unknown)"
$lblCaps.AutoSize = $true
$lblCaps.Location = New-Object System.Drawing.Point(0, 68)
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

            # Active radio (single-target today) — all radios share same parent ($profilesPanel)
            $rb = New-Object System.Windows.Forms.RadioButton
            $rb.Text = $p.DisplayName
            $rb.AutoSize = $true
            $rb.Location = [System.Drawing.Point]::new(20, [int]($y + 4))
            $rb.Tag = $p.Id
            $rb.Checked = ($script:ActiveProfileId -eq $p.Id)
            $profilesPanel.Controls.Add($rb)

            if ($p.Id -eq "BEACN") {
                $tooltip.SetToolTip($rb, "To set up the recommended configuration for BEACN:`n1. Select the BEACN profile under Device Settings.`n2. Select Hidden install mode (runs silently in the background).`n3. Select Graceful operating mode (cleanly shuts down the BEACN app).`n4. Click 'Install / Update' to install the background task.`n5. Approve the Power Plan Fix if prompted to ensure proper screen-off timing.")
            }
            elseif ($p.Id -eq "DEMO") {
                $tooltip.SetToolTip($rb, "Demo Device (UI Test):`nUse this profile to test the SAMISH user interface, simulated sleep blocker scans, and wake/resume action simulation. This profile also serves as a developer template to model custom device adapter modules from.")
            }

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



# ----- Live Log Helpers -----
$script:IsLiveLogMode = $false
$script:IsLiveLogPaused = $false
$script:LiveLogPath = $null
$script:LiveLogTimer = $null
$script:LiveLogPosition = 0
$script:LiveLogMaxChars = 100000

function Read-LogTailText {
    param(
        [string]$Path,
        [int]$MaxChars = 100000
    )

    if (-not (Test-Path -LiteralPath $Path)) { return "" }

    $fs = $null
    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
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
                # ✅ Continue path (no dead-end)
                return Apply-PowerPlanFixWithBackup -PromptUser:$true -AutoMode:$AutoMode
            }
        }

        default {
            return (Get-UnknownPowerPlanPromptStatus -PromptId $result.PromptId)
        }
    }
}

# =====================================================================
# DASHBOARD LAYOUT & CONTROLS RESTRUCTURING (SAMISH v1.1.0)
# =====================================================================

# Create Custom Flat Navigation Buttons at the top of the form
$btnTabSetup = New-Object System.Windows.Forms.Button
$btnTabSetup.Text = "1. Setup && Install"
$btnTabSetup.Font = $boldFont
$btnTabSetup.Size = New-Object System.Drawing.Size(145, 30)
$btnTabSetup.Location = New-Object System.Drawing.Point(330, 48)
$btnTabSetup.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnTabSetup.FlatAppearance.BorderSize = 1
$btnTabSetup.BackColor = [System.Drawing.SystemColors]::Control
$btnTabSetup.ForeColor = $BrandPurple
$btnTabSetup.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$form.Controls.Add($btnTabSetup)
$script:btnTabSetup = $btnTabSetup
$tooltip.SetToolTip($btnTabSetup, "Configure install mode, operating mode, and device profiles.")

$btnTabDiag = New-Object System.Windows.Forms.Button
$btnTabDiag.Text = "2. Sleep Automation"
$btnTabDiag.Font = $font
$btnTabDiag.Size = New-Object System.Drawing.Size(180, 30)
$btnTabDiag.Location = New-Object System.Drawing.Point(485, 48)
$btnTabDiag.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnTabDiag.FlatAppearance.BorderSize = 1
$btnTabDiag.BackColor = [System.Drawing.SystemColors]::Control
$btnTabDiag.ForeColor = [System.Drawing.Color]::DimGray
$btnTabDiag.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$form.Controls.Add($btnTabDiag)
$script:btnTabDiag = $btnTabDiag
$tooltip.SetToolTip($btnTabDiag, "Scan for system sleep blockers, manage overrides, and test app wake actions.")

# Create borderless TabControl
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Location = New-Object System.Drawing.Point(10, 95)
$tabControl.Size = New-Object System.Drawing.Size(780, 490)
$tabControl.SizeMode = [System.Windows.Forms.TabSizeMode]::Fixed
$tabControl.ItemSize = New-Object System.Drawing.Size(0, 1)
$tabControl.Appearance = [System.Windows.Forms.TabAppearance]::FlatButtons
$form.Controls.Add($tabControl)
$script:tabControl = $tabControl

$tabPage1 = New-Object System.Windows.Forms.TabPage
$tabPage1.Text = "Setup"
$tabPage1.BackColor = [System.Drawing.SystemColors]::Control
$tabControl.TabPages.Add($tabPage1)
$script:tabPage1 = $tabPage1

$tabPage2 = New-Object System.Windows.Forms.TabPage
$tabPage2.Text = "Diagnostics"
$tabPage2.BackColor = [System.Drawing.SystemColors]::Control
$tabControl.TabPages.Add($tabPage2)
$script:tabPage2 = $tabPage2

# v1.1.0: Install/Uninstall buttons (creation code; repositioned to tabPage1 below)
$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = "Install / Update"
$btnInstall.Font = $font
$btnInstall.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$script:btnInstall = $btnInstall

$btnUninstall = New-Object System.Windows.Forms.Button
$btnUninstall.Text = "Uninstall"
$btnUninstall.Font = $font
$btnUninstall.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$script:btnUninstall = $btnUninstall

# 1. Parent controls to Page 1
$tabPage1.Controls.Add($modeGroup)
$tabPage1.Controls.Add($opGroup)
$tabPage1.Controls.Add($cfgGroup)
$tabPage1.Controls.Add($deviceGroup)
$tabPage1.Controls.Add($statusGroup)
$tabPage1.Controls.Add($btnInstall)
$tabPage1.Controls.Add($btnUninstall)

# 2. Page 1 Layout Repositioning
# Left Column
$modeGroup.Size = New-Object System.Drawing.Size(370, 85)
$modeGroup.Location = New-Object System.Drawing.Point(10, 10)

$opGroup.Size = New-Object System.Drawing.Size(370, 85)
$opGroup.Location = New-Object System.Drawing.Point(10, 105)

$cfgGroup.Size = New-Object System.Drawing.Size(370, 195)
$cfgGroup.Location = New-Object System.Drawing.Point(10, 200)

# Reposition cfgGroup children
$lblLogInterval.Location = New-Object System.Drawing.Point(25, 60)
$ddLogInterval.Location = New-Object System.Drawing.Point(85, 56)
$ddLogInterval.Width = 135
$tbLogCustom.Location = New-Object System.Drawing.Point(230, 56)
$tbLogCustom.Width = 50
$lblLogCustom.Location = New-Object System.Drawing.Point(285, 60)

$cbHotkey.Location = New-Object System.Drawing.Point(15, 92)
$lblHotkey.Location = New-Object System.Drawing.Point(25, 122)
$ddHotkey.Location = New-Object System.Drawing.Point(85, 118)
$ddHotkey.Width = 135
$lblCustomKey.Location = New-Object System.Drawing.Point(230, 122)
$tbCustomKey.Location = New-Object System.Drawing.Point(285, 118)
$tbCustomKey.Width = 75
$lblCustomHint.Location = New-Object System.Drawing.Point(85, 142)

$cbTray.Location = New-Object System.Drawing.Point(15, 164)

# Action Row Page 1 Left
$btnInstall.Size = New-Object System.Drawing.Size(160, 36)
$btnInstall.Location = New-Object System.Drawing.Point(10, 410)
$tooltip.SetToolTip($btnInstall, "Install or update SAMISH using the selected settings.")

$btnUninstall.Size = New-Object System.Drawing.Size(110, 36)
$btnUninstall.Location = New-Object System.Drawing.Point(180, 410)
$tooltip.SetToolTip($btnUninstall, "Remove SAMISH. To temporarily stop SAMISH from launching on boot, click Uninstall. You will have the option to save your profiles and configuration settings to be automatically reapplied on reinstall.")

# Right Column
$deviceGroup.Size = New-Object System.Drawing.Size(370, 210)
$deviceGroup.Location = New-Object System.Drawing.Point(395, 10)

$profilesPanel.Location = New-Object System.Drawing.Point(10, 20)
$profilesPanel.Size = New-Object System.Drawing.Size(350, 85)

$detailsPanel.Location = New-Object System.Drawing.Point(10, 110)
$detailsPanel.Size = New-Object System.Drawing.Size(350, 90)

$statusGroup.Size = New-Object System.Drawing.Size(370, 165)
$statusGroup.Location = New-Object System.Drawing.Point(395, 230)

$statusBox.Location = New-Object System.Drawing.Point(10, 25)
$statusBox.Size = New-Object System.Drawing.Size(350, 127)



# Action Row Page 1 Right (Advanced Tools Toggle)
$btnToolsAdvanced = New-Object System.Windows.Forms.Button
$btnToolsAdvanced.Text = "Advanced Tools >>"
$btnToolsAdvanced.Font = $font
$btnToolsAdvanced.Size = New-Object System.Drawing.Size(350, 36)
$btnToolsAdvanced.Location = New-Object System.Drawing.Point(405, 410)
$tabPage1.Controls.Add($btnToolsAdvanced)
$script:btnToolsAdvanced = $btnToolsAdvanced
$tooltip.SetToolTip($btnToolsAdvanced, "Open or close the advanced utility and log monitoring tools drawer.")

# 3. Page 1 Slide-Out Drawer: "Advanced Tools & Utilities"
$grpAdvancedTools = New-Object System.Windows.Forms.GroupBox
$grpAdvancedTools.Text = "Advanced Tools && Utilities"
$grpAdvancedTools.Font = $font
$grpAdvancedTools.Size = New-Object System.Drawing.Size(360, 385)
$grpAdvancedTools.Location = New-Object System.Drawing.Point(790, 10)
$tabPage1.Controls.Add($grpAdvancedTools)
$script:grpAdvancedTools = $grpAdvancedTools
$tooltip.SetToolTip($grpAdvancedTools, "Advanced utility tools and live background service monitoring.")

# Create Sub-Tabs for Advanced Tools (Tools vs. Live Log)
$btnSubTabTools = New-Object System.Windows.Forms.Button
$btnSubTabTools.Name = "btnSubTabTools"
$btnSubTabTools.Text = "Tools"
$btnSubTabTools.Font = $boldFont
$btnSubTabTools.Size = New-Object System.Drawing.Size(75, 24)
$btnSubTabTools.Location = New-Object System.Drawing.Point(190, 16)
$btnSubTabTools.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnSubTabTools.FlatAppearance.BorderSize = 1
$btnSubTabTools.BackColor = [System.Drawing.SystemColors]::Control
$btnSubTabTools.ForeColor = $BrandPurple
$btnSubTabTools.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$btnSubTabTools.Visible = $false
$grpAdvancedTools.Controls.Add($btnSubTabTools)
$btnSubTabTools.BringToFront()
$script:btnSubTabTools = $btnSubTabTools
$tooltip.SetToolTip($btnSubTabTools, "View advanced setup actions and utilities.")

$btnSubTabLive = New-Object System.Windows.Forms.Button
$btnSubTabLive.Name = "btnSubTabLive"
$btnSubTabLive.Text = "Live Log"
$btnSubTabLive.Font = $font
$btnSubTabLive.Size = New-Object System.Drawing.Size(75, 24)
$btnSubTabLive.Location = New-Object System.Drawing.Point(270, 16)
$btnSubTabLive.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnSubTabLive.FlatAppearance.BorderSize = 1
$btnSubTabLive.BackColor = [System.Drawing.SystemColors]::Control
$btnSubTabLive.ForeColor = [System.Drawing.Color]::DimGray
$btnSubTabLive.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
# Create Sub-Tabs for Advanced Tools (Tools vs. Live Log)
$btnSubTabLive.Visible = $false
$grpAdvancedTools.Controls.Add($btnSubTabLive)
$btnSubTabLive.BringToFront()
$script:btnSubTabLive = $btnSubTabLive
$tooltip.SetToolTip($btnSubTabLive, "Monitor the live SAMISH activity and background service logs.")

# Sub-Separator line under the sub-tab buttons (mirroring the main separator)
$subSep = New-Object System.Windows.Forms.Label
$subSep.Size = New-Object System.Drawing.Size(330, 2)
$subSep.Location = New-Object System.Drawing.Point(15, 45)
$subSep.BackColor = $BrandCyan
$grpAdvancedTools.Controls.Add($subSep)
$script:subSep = $subSep

# Create/Move tool buttons into Page 1 Drawer
$btnPowerPlan = New-Object System.Windows.Forms.Button
$btnPowerPlan.Text = "Verify Power Plan"
$btnPowerPlan.Font = $font
$btnPowerPlan.Size = New-Object System.Drawing.Size(330, 32)
$btnPowerPlan.Location = New-Object System.Drawing.Point(15, 60)
$grpAdvancedTools.Controls.Add($btnPowerPlan)
$script:btnPowerPlan = $btnPowerPlan
$tooltip.SetToolTip($btnPowerPlan, "Verify and configure your system power plan settings for SAMISH compatibility.")

$btnOpenTS = New-Object System.Windows.Forms.Button
$btnOpenTS.Text = "Open Windows Task Scheduler"
$btnOpenTS.Font = $font
$btnOpenTS.Size = New-Object System.Drawing.Size(330, 32)
$btnOpenTS.Location = New-Object System.Drawing.Point(15, 105)
$grpAdvancedTools.Controls.Add($btnOpenTS)
$script:btnOpenTS = $btnOpenTS
$tooltip.SetToolTip($btnOpenTS, "Open Windows Task Scheduler to view or manage SAMISH tasks.")

$btnCleanReset = New-Object System.Windows.Forms.Button
$btnCleanReset.Text = "Restart SAMISH Service"
$btnCleanReset.Font = $font
$btnCleanReset.Size = New-Object System.Drawing.Size(330, 32)
$btnCleanReset.Location = New-Object System.Drawing.Point(15, 150)
$grpAdvancedTools.Controls.Add($btnCleanReset)
$script:btnCleanReset = $btnCleanReset
$tooltip.SetToolTip($btnCleanReset, "Restart background service and check for errors (safely preserves configuration).")

$btnReadSetup = New-Object System.Windows.Forms.Button
$btnReadSetup.Text = "Check Install Status"
$btnReadSetup.Font = $font
$btnReadSetup.Size = New-Object System.Drawing.Size(330, 32)
$btnReadSetup.Location = New-Object System.Drawing.Point(15, 195)
$grpAdvancedTools.Controls.Add($btnReadSetup)
$script:btnReadSetup = $btnReadSetup
$tooltip.SetToolTip($btnReadSetup, "Query and print the active installation status and current settings.")

$btnOpenLog = New-Object System.Windows.Forms.Button
$btnOpenLog.Text = "Open Setup Log"
$btnOpenLog.Font = $font
$btnOpenLog.Size = New-Object System.Drawing.Size(330, 32)
$btnOpenLog.Location = New-Object System.Drawing.Point(15, 240)
$grpAdvancedTools.Controls.Add($btnOpenLog)
$script:btnOpenLog = $btnOpenLog
$tooltip.SetToolTip($btnOpenLog, "Open the main SAMISH text log in your default editor.")

# Create the dedicated Live Log console textbox inside the Page 1 Drawer (hidden initially)
$txtLiveLog = New-Object System.Windows.Forms.TextBox
$txtLiveLog.Name = "txtLiveLog"
$txtLiveLog.Multiline = $true
$txtLiveLog.ScrollBars = "Vertical"
$txtLiveLog.ReadOnly = $true
$txtLiveLog.Size = New-Object System.Drawing.Size(330, 279)
$txtLiveLog.Location = New-Object System.Drawing.Point(15, 55)
$txtLiveLog.Visible = $false
$txtLiveLog.BackColor = [System.Drawing.Color]::FromArgb(10, 10, 14)
$txtLiveLog.ForeColor = $BrandCyan
$grpAdvancedTools.Controls.Add($txtLiveLog)
$script:txtLiveLog = $txtLiveLog

$liveLogSep = New-Object System.Windows.Forms.Label
$liveLogSep.Name = "liveLogSep"
$liveLogSep.Size = New-Object System.Drawing.Size(330, 2)
$liveLogSep.Location = New-Object System.Drawing.Point(15, 334)
$liveLogSep.BackColor = $BrandPurple
$liveLogSep.Visible = $false
$grpAdvancedTools.Controls.Add($liveLogSep)
$script:liveLogSep = $liveLogSep

# Create the live log control buttons inside the Page 1 Drawer (hidden initially)
$btnLivePause = New-Object System.Windows.Forms.Button
$btnLivePause.Text = "Pause"
$btnLivePause.Size = New-Object System.Drawing.Size(90, 28)
$btnLivePause.Location = New-Object System.Drawing.Point(15, 344)
$btnLivePause.Visible = $false
$grpAdvancedTools.Controls.Add($btnLivePause)
$script:btnLivePause = $btnLivePause
$tooltip.SetToolTip($btnLivePause, "Pause or resume the live log stream")

$btnLiveCopy = New-Object System.Windows.Forms.Button
$btnLiveCopy.Text = "Copy"
$btnLiveCopy.Size = New-Object System.Drawing.Size(90, 28)
$btnLiveCopy.Location = New-Object System.Drawing.Point(135, 344)
$btnLiveCopy.Visible = $false
$grpAdvancedTools.Controls.Add($btnLiveCopy)
$script:btnLiveCopy = $btnLiveCopy
$tooltip.SetToolTip($btnLiveCopy, "Copy all visible log text to the clipboard")

$btnLiveClear = New-Object System.Windows.Forms.Button
$btnLiveClear.Text = "Clear"
$btnLiveClear.Size = New-Object System.Drawing.Size(90, 28)
$btnLiveClear.Location = New-Object System.Drawing.Point(255, 344)
$btnLiveClear.Visible = $false
$grpAdvancedTools.Controls.Add($btnLiveClear)
$script:btnLiveClear = $btnLiveClear
$tooltip.SetToolTip($btnLiveClear, "Clear the log display (does not delete the log file)")


# 4. Page 2: Sleep & Hibernate Diagnostics
$grpBlockers = New-Object System.Windows.Forms.GroupBox
$grpBlockers.Text = "Active Blockers"
$grpBlockers.Size = New-Object System.Drawing.Size(355, 200)
$grpBlockers.Location = New-Object System.Drawing.Point(10, 10)
$tabPage2.Controls.Add($grpBlockers)
$tooltip.SetToolTip($grpBlockers, "System processes, services, or drivers currently blocking Windows from sleep or hibernate.")

$listBlockers = New-Object System.Windows.Forms.ListBox
$listBlockers.Size = New-Object System.Drawing.Size(335, 90)
$listBlockers.Location = New-Object System.Drawing.Point(10, 22)
$listBlockers.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
$grpBlockers.Controls.Add($listBlockers)
$script:listBlockers = $listBlockers

$btnDiagAutomate = New-Object System.Windows.Forms.Button
$btnDiagAutomate.Text = "Add to Automated Apps"
$btnDiagAutomate.Font = $font
$btnDiagAutomate.Size = New-Object System.Drawing.Size(335, 32)
$btnDiagAutomate.Location = New-Object System.Drawing.Point(10, 118)
$btnDiagAutomate.Enabled = $false
$grpBlockers.Controls.Add($btnDiagAutomate)
$script:btnDiagAutomate = $btnDiagAutomate
$tooltip.SetToolTip($btnDiagAutomate, "Configure SAMISH to automatically manage this application before sleep or hibernation, and restart it when the system wakes.")

$lblBlockerHint = New-Object System.Windows.Forms.Label
$lblBlockerHint.Text = "Tip: To discover and automate a browser/media app, open it and play media, then click Scan."
$lblBlockerHint.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
$lblBlockerHint.ForeColor = [System.Drawing.Color]::DimGray
$lblBlockerHint.Size = New-Object System.Drawing.Size(335, 36)
$lblBlockerHint.Location = New-Object System.Drawing.Point(10, 154)
$grpBlockers.Controls.Add($lblBlockerHint)
$tooltip.SetToolTip($lblBlockerHint, "To configure a browser or media app for SAMISH management:`n1. Open the application (e.g., Spotify, Chrome) and play media to generate an active audio wake-lock.`n2. Click 'Scan Blockers' to discover the application in the Active Blockers list.`n3. Select the application and click 'Add to Automated Apps' to automate it.")

$grpOverrides = New-Object System.Windows.Forms.GroupBox
$grpOverrides.Text = "Ignored Blockers"
$grpOverrides.Size = New-Object System.Drawing.Size(355, 175)
$grpOverrides.Location = New-Object System.Drawing.Point(10, 220)
$tabPage2.Controls.Add($grpOverrides)
$tooltip.SetToolTip($grpOverrides, "Configured system overrides to let Windows ignore specific sleep blockers.")

$listOverrides = New-Object System.Windows.Forms.ListBox
$listOverrides.Size = New-Object System.Drawing.Size(335, 105)
$listOverrides.Location = New-Object System.Drawing.Point(10, 22)
$listOverrides.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
$grpOverrides.Controls.Add($listOverrides)
$script:listOverrides = $listOverrides

$btnDiagRestore = New-Object System.Windows.Forms.Button
$btnDiagRestore.Text = "Remove System Override"
$btnDiagRestore.Size = New-Object System.Drawing.Size(335, 32)
$btnDiagRestore.Location = New-Object System.Drawing.Point(10, 134)
$btnDiagRestore.Enabled = $false
$grpOverrides.Controls.Add($btnDiagRestore)
$script:btnDiagRestore = $btnDiagRestore
$tooltip.SetToolTip($btnDiagRestore, "Remove the override and let this item's power requests once again affect sleep and hibernation behaviour.")

$btnDiagScan = New-Object System.Windows.Forms.Button
$btnDiagScan.Text = "Scan Blockers"
$btnDiagScan.Font = $font
$btnDiagScan.Size = New-Object System.Drawing.Size(112, 36)
$btnDiagScan.Location = New-Object System.Drawing.Point(10, 410)
$tabPage2.Controls.Add($btnDiagScan)
$script:btnDiagScan = $btnDiagScan
$tooltip.SetToolTip($btnDiagScan, "Scan Windows for all active power requests currently preventing sleep or hibernation.")

$btnDiagIgnore = New-Object System.Windows.Forms.Button
$btnDiagIgnore.Text = "Ignore Blocker"
$btnDiagIgnore.Font = $font
$btnDiagIgnore.Size = New-Object System.Drawing.Size(237, 36)
$btnDiagIgnore.Location = New-Object System.Drawing.Point(128, 410)
$btnDiagIgnore.Enabled = $false
$tabPage2.Controls.Add($btnDiagIgnore)
$script:btnDiagIgnore = $btnDiagIgnore
$tooltip.SetToolTip($btnDiagIgnore, "Tell Windows to ignore this blocker's power request so it no longer prevents sleep or hibernation.")

# Right Column
$grpAutomated = New-Object System.Windows.Forms.GroupBox
$grpAutomated.Text = "SAMISH Automated Apps"
$grpAutomated.Size = New-Object System.Drawing.Size(375, 175)
$grpAutomated.Location = New-Object System.Drawing.Point(395, 10)
$tabPage2.Controls.Add($grpAutomated)
$tooltip.SetToolTip($grpAutomated, "Applications automated by SAMISH to be closed before sleep and restarted on wake.")

$listAutomated = New-Object System.Windows.Forms.ListBox
$listAutomated.Size = New-Object System.Drawing.Size(355, 105)
$listAutomated.Location = New-Object System.Drawing.Point(10, 22)
$listAutomated.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
$grpAutomated.Controls.Add($listAutomated)
$script:listAutomated = $listAutomated
 
$btnDiagStopAuto = New-Object System.Windows.Forms.Button
$btnDiagStopAuto.Text = "Remove from Automation"
$btnDiagStopAuto.Font = $font
$btnDiagStopAuto.Size = New-Object System.Drawing.Size(170, 32)
$btnDiagStopAuto.Location = New-Object System.Drawing.Point(10, 134)
$btnDiagStopAuto.Enabled = $false
$grpAutomated.Controls.Add($btnDiagStopAuto)
$script:btnDiagStopAuto = $btnDiagStopAuto
$tooltip.SetToolTip($btnDiagStopAuto, "Remove this application from SAMISH automation.")
 
$btnDiagOpenLocation = New-Object System.Windows.Forms.Button
$btnDiagOpenLocation.Text = "Open Installation Folder"
$btnDiagOpenLocation.Font = $font
$btnDiagOpenLocation.Size = New-Object System.Drawing.Size(170, 32)
$btnDiagOpenLocation.Location = New-Object System.Drawing.Point(195, 134)
$btnDiagOpenLocation.Enabled = $false
$grpAutomated.Controls.Add($btnDiagOpenLocation)
$script:btnDiagOpenLocation = $btnDiagOpenLocation
$tooltip.SetToolTip($btnDiagOpenLocation, "Open the installation folder for this application in Windows File Explorer.")

$grpOperatingMode = New-Object System.Windows.Forms.GroupBox
$grpOperatingMode.Text = "Operating Mode"
$grpOperatingMode.Size = New-Object System.Drawing.Size(375, 200)
$grpOperatingMode.Location = New-Object System.Drawing.Point(395, 195)
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

$lblOnWake = New-Object System.Windows.Forms.Label
$lblOnWake.Text = "On Wake/Resume:"
$lblOnWake.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblOnWake.ForeColor = $BrandPurple
$lblOnWake.AutoSize = $true
$lblOnWake.Location = New-Object System.Drawing.Point(10, 141)
$grpOperatingMode.Controls.Add($lblOnWake)
$tooltip.SetToolTip($lblOnWake, "Choose what action SAMISH will perform when the system wakes: Smart Restore restores the pre-sleep state; Always Play forces playback; Always Pause keeps media paused; Keep Closed prevents app restart; Reopen Only restarts the app but keeps media paused.")

$ddOnWakeAction = New-Object System.Windows.Forms.ComboBox
$ddOnWakeAction.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$ddOnWakeAction.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
$ddOnWakeAction.Size = New-Object System.Drawing.Size(355, 24)
$ddOnWakeAction.Location = New-Object System.Drawing.Point(10, 166)
$grpOperatingMode.Controls.Add($ddOnWakeAction)
$script:ddDiagOnWakeAction = $ddOnWakeAction
$tooltip.SetToolTip($ddOnWakeAction, "Choose what action SAMISH will perform when the system wakes.")

# Bottom Action Row (Page 2 Right Column)
$btnDiagAdvanced = New-Object System.Windows.Forms.Button
$btnDiagAdvanced.Text = "Diagnostics >>"
$btnDiagAdvanced.Font = $font
$btnDiagAdvanced.Size = New-Object System.Drawing.Size(375, 36)
$btnDiagAdvanced.Location = New-Object System.Drawing.Point(395, 410)
$tabPage2.Controls.Add($btnDiagAdvanced)
$script:btnDiagAdvanced = $btnDiagAdvanced
$tooltip.SetToolTip($btnDiagAdvanced, "Open or close the advanced system sleep telemetry and testing drawer.")


# 5. Page 2 Slide-Out Drawer: "Sleep & Wake Diagnostics"
$grpAdvancedDiag = New-Object System.Windows.Forms.Panel
$grpAdvancedDiag.Size = New-Object System.Drawing.Size(360, 436)
$grpAdvancedDiag.Location = New-Object System.Drawing.Point(790, 10)
$tabPage2.Controls.Add($grpAdvancedDiag)
$script:grpAdvancedDiag = $grpAdvancedDiag

# Operating Mode Tests GroupBox
$grpTest = New-Object System.Windows.Forms.GroupBox
$grpTest.Text = "Operating Mode Tests"
$grpTest.Size = New-Object System.Drawing.Size(340, 175)
$grpTest.Location = New-Object System.Drawing.Point(10, 0)
$grpAdvancedDiag.Controls.Add($grpTest)
$script:testGroup = $grpTest
$tooltip.SetToolTip($grpTest, "Perform interactive test actions on the selected sleep blocker target.")

$ddTestTarget = New-Object System.Windows.Forms.ComboBox
$ddTestTarget.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$ddTestTarget.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
$ddTestTarget.Size = New-Object System.Drawing.Size(310, 24)
$ddTestTarget.Location = New-Object System.Drawing.Point(15, 22)
$ddTestTarget.Enabled = $false
$grpTest.Controls.Add($ddTestTarget)
$script:ddTestTarget = $ddTestTarget
$tooltip.SetToolTip($ddTestTarget, "Select which configured application or device profile driver to test.")

$btnTestSleep = New-Object System.Windows.Forms.Button
$btnTestSleep.Text = "Test Sleep/Hibernate"
$btnTestSleep.Size = New-Object System.Drawing.Size(148, 32)
$btnTestSleep.Location = New-Object System.Drawing.Point(15, 85)
$btnTestSleep.Enabled = $false
$grpTest.Controls.Add($btnTestSleep)
$script:btnTestStop = $btnTestSleep
$tooltip.SetToolTip($btnTestSleep, "Test whether SAMISH can close this application or pause its media playback based on its configured sleep action.")

$btnTestWake = New-Object System.Windows.Forms.Button
$btnTestWake.Text = "Test Wake/Resume"
$btnTestWake.Size = New-Object System.Drawing.Size(148, 32)
$btnTestWake.Location = New-Object System.Drawing.Point(177, 85)
$btnTestWake.Enabled = $false
$grpTest.Controls.Add($btnTestWake)
$script:btnTestStart = $btnTestWake
$tooltip.SetToolTip($btnTestWake, "Test whether SAMISH can launch this application and/or restore its media playback status based on its configured wake action.")

$btnTestGraceful = New-Object System.Windows.Forms.Button
$btnTestGraceful.Text = "Test Graceful Close"
$btnTestGraceful.Size = New-Object System.Drawing.Size(148, 32)
$btnTestGraceful.Location = New-Object System.Drawing.Point(15, 134)
$btnTestGraceful.Enabled = $false
$grpTest.Controls.Add($btnTestGraceful)
$script:btnTestGraceful = $btnTestGraceful
$tooltip.SetToolTip($btnTestGraceful, "Test close app (graceful) behavior, forcing a WM_CLOSE command to ask the application to close cleanly.")

$btnTestForce = New-Object System.Windows.Forms.Button
$btnTestForce.Text = "Test Force Close"
$btnTestForce.Size = New-Object System.Drawing.Size(148, 32)
$btnTestForce.Location = New-Object System.Drawing.Point(177, 134)
$btnTestForce.Enabled = $false
$grpTest.Controls.Add($btnTestForce)
$script:btnTestClassic = $btnTestForce
$tooltip.SetToolTip($btnTestForce, "Test close app (classic) behavior, forcing immediate process termination.")

# System Sleep & Wake Telemetry GroupBox
$grpTelemetry = New-Object System.Windows.Forms.GroupBox
$grpTelemetry.Text = "System Sleep && Wake Analysis"
$grpTelemetry.Size = New-Object System.Drawing.Size(340, 200)
$grpTelemetry.Location = New-Object System.Drawing.Point(10, 185)
$grpAdvancedDiag.Controls.Add($grpTelemetry)
$tooltip.SetToolTip($grpTelemetry, "Analyze active wake timers, armed hardware devices, and supported system sleep states.")

$lblTelemetryStates = New-Object System.Windows.Forms.Label
$lblTelemetryStates.Text = "Querying sleep states..."
$lblTelemetryStates.AutoSize = $false
$lblTelemetryStates.Size = New-Object System.Drawing.Size(310, 18)
$lblTelemetryStates.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblTelemetryStates.ForeColor = $BrandPurple
$lblTelemetryStates.Location = New-Object System.Drawing.Point(15, 22)
$grpTelemetry.Controls.Add($lblTelemetryStates)
$script:lblTelemetryStates = $lblTelemetryStates
$tooltip.SetToolTip($lblTelemetryStates, "Sleep states supported by your system's hardware configuration.")

$lblLastWakeTitle = New-Object System.Windows.Forms.Label
$lblLastWakeTitle.Text = "Last Wake Source:"
$lblLastWakeTitle.AutoSize = $true
$lblLastWakeTitle.Location = New-Object System.Drawing.Point(15, 42)
$grpTelemetry.Controls.Add($lblLastWakeTitle)

$txtLastWake = New-Object System.Windows.Forms.TextBox
$txtLastWake.Multiline = $true
$txtLastWake.ScrollBars = "Vertical"
$txtLastWake.ReadOnly = $true
$txtLastWake.Size = New-Object System.Drawing.Size(310, 36)
$txtLastWake.Location = New-Object System.Drawing.Point(15, 60)
$txtLastWake.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 250)
$grpTelemetry.Controls.Add($txtLastWake)
$script:txtLastWake = $txtLastWake
$tooltip.SetToolTip($txtLastWake, "The driver, device, or component that woke your system from the last sleep cycle.")

# Nested TabControl inside Telemetry box for Timers and Armed Devices
$tabTelemetryDetails = New-Object System.Windows.Forms.TabControl
$tabTelemetryDetails.Size = New-Object System.Drawing.Size(310, 90)
$tabTelemetryDetails.Location = New-Object System.Drawing.Point(15, 100)
$tooltip.SetToolTip($tabTelemetryDetails, "Switch between active wake timers and armed hardware devices.")

$tabPageTimers = New-Object System.Windows.Forms.TabPage
$tabPageTimers.Text = "Wake Timers"
$tabPageTimers.BackColor = [System.Drawing.SystemColors]::Control

$tabPageArmed = New-Object System.Windows.Forms.TabPage
$tabPageArmed.Text = "Armed Devices"
$tabPageArmed.BackColor = [System.Drawing.SystemColors]::Control

[void]$tabTelemetryDetails.TabPages.Add($tabPageTimers)
[void]$tabTelemetryDetails.TabPages.Add($tabPageArmed)
$grpTelemetry.Controls.Add($tabTelemetryDetails)

$txtWakeTimers = New-Object System.Windows.Forms.TextBox
$txtWakeTimers.Multiline = $true
$txtWakeTimers.ScrollBars = "Vertical"
$txtWakeTimers.ReadOnly = $true
$txtWakeTimers.Size = New-Object System.Drawing.Size(292, 50)
$txtWakeTimers.Location = New-Object System.Drawing.Point(4, 4)
$txtWakeTimers.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 250)
$tabPageTimers.Controls.Add($txtWakeTimers)
$script:txtWakeTimers = $txtWakeTimers
$tooltip.SetToolTip($txtWakeTimers, "Lists active system wake timers that can wake the PC from sleep automatically.")

$listArmedDevices = New-Object System.Windows.Forms.ListBox
$listArmedDevices.Size = New-Object System.Drawing.Size(292, 50)
$listArmedDevices.Location = New-Object System.Drawing.Point(4, 4)
$listArmedDevices.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 250)
$listArmedDevices.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
$tabPageArmed.Controls.Add($listArmedDevices)
$script:listArmedDevices = $listArmedDevices
$tooltip.SetToolTip($listArmedDevices, "Lists hardware devices (keyboard, mouse, network adapter) armed to wake the PC.")

# Redesigned refresh button, externalized to the drawer panel
$btnTelemetryRefresh = New-Object System.Windows.Forms.Button
$btnTelemetryRefresh.Text = "Refresh Telemetry"
$btnTelemetryRefresh.Font = $font
$btnTelemetryRefresh.Size = New-Object System.Drawing.Size(340, 36)
$btnTelemetryRefresh.Location = New-Object System.Drawing.Point(10, 400)
$grpAdvancedDiag.Controls.Add($btnTelemetryRefresh)
$script:btnTelemetryRefresh = $btnTelemetryRefresh
$tooltip.SetToolTip($btnTelemetryRefresh, "Query and refresh active sleep blockers, system overrides, and wake diagnostics.")


# 6. Global Status Label (Page 2 Bottom Info Bar)
$lblDiagDetail = New-Object System.Windows.Forms.Label
$lblDiagDetail.Text = "Select an item from the Active Blockers list to see details, or click Scan Blockers."
$lblDiagDetail.AutoSize = $false
$lblDiagDetail.Size = New-Object System.Drawing.Size(760, 36)
$lblDiagDetail.Location = New-Object System.Drawing.Point(10, 452)
$lblDiagDetail.ForeColor = [System.Drawing.Color]::DimGray
$tabPage2.Controls.Add($lblDiagDetail)
$script:lblDiagDetail = $lblDiagDetail


# 7. Style Reset & Metadata Location Update
$script:grpDiagOperatingMode = $grpOperatingMode
$script:diagTip = $tooltip

# Grey out Operating Mode box initially
$grpOperatingMode.ForeColor = [System.Drawing.Color]::Gray
foreach ($ctrl in $grpOperatingMode.Controls) { $ctrl.Enabled = $false }

# Position metadata footer
$bottomMetadata = New-Object System.Windows.Forms.Label
$bottomMetadata.Text = "$ProductName $ProductVersion  |  $AuthorLine"
$bottomMetadata.Font = $font
$bottomMetadata.ForeColor = $BrandCyan
$bottomMetadata.AutoSize = $false
$bottomMetadata.Size = New-Object System.Drawing.Size(300, 20)
$bottomMetadata.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$bottomMetadata.Location = New-Object System.Drawing.Point(480, 595)
$form.Controls.Add($bottomMetadata)
$script:bottomMetadata = $bottomMetadata
$bottomMetadata.BringToFront()
$tooltip.SetToolTip($bottomMetadata, "Double-click to open CHANGELOG.md (if present in the application folder).")

# Styling resets
# NOTE: controls named statusBox / txtLiveLog / txtLastWake / txtWakeTimers are excluded from
# font AND ForeColor resets so they keep their custom terminal/log colours.
function Reset-MainFormChildControls {
    param($container)
    foreach ($ctrl in $container.Controls) {
        if ($ctrl -isnot [System.Windows.Forms.GroupBox] -and
            $ctrl.Name -ne "statusBox" -and $ctrl.Name -ne "txtLiveLog" -and
            $ctrl.Name -ne "txtLastWake" -and $ctrl.Name -ne "txtWakeTimers" -and
            $ctrl.Name -ne "btnSubTabTools" -and $ctrl.Name -ne "btnSubTabLive" -and
            $ctrl.Name -ne "liveLogSep") {
            $ctrl.Font = $font
            $ctrl.ForeColor = [System.Drawing.SystemColors]::ControlText
        }
        if ($ctrl.Controls.Count -gt 0) {
            Reset-MainFormChildControls $ctrl
        }
    }
}

foreach ($grp in @($modeGroup, $opGroup, $cfgGroup, $deviceGroup, $statusGroup, $grpAdvancedTools, $grpTest, $grpTelemetry, $grpBlockers, $grpOverrides, $grpAutomated, $grpOperatingMode)) {
    $grp.Font = $boldFont
    $grp.ForeColor = [System.Drawing.SystemColors]::ControlText
    Reset-MainFormChildControls $grp
}

Reset-MainFormChildControls $tabPage1
Reset-MainFormChildControls $tabPage2


# Set initial tab style (Setup active by default)
$btnTabSetup.BackColor = [System.Drawing.SystemColors]::Control
$btnTabSetup.ForeColor = $BrandPurple
$btnTabSetup.Font = $boldFont
$btnTabSetup.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$btnTabDiag.BackColor = [System.Drawing.SystemColors]::Control
$btnTabDiag.ForeColor = [System.Drawing.Color]::DimGray
$btnTabDiag.Font = $font
$btnTabDiag.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray

# Set initial state of Clean Reset button based on install status
$script:IsSamishInstalled = Test-SamishInstalled
if ($script:IsSamishInstalled) {
    $btnCleanReset.Enabled = $true
}
else {
    $btnCleanReset.Enabled = $false
    $tooltip.SetToolTip($btnCleanReset, "SAMISH is not installed - clean reset unavailable.")
}

