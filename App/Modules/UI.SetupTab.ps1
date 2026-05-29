# ---------- UI.SetupTab.ps1 ----------
# ---------- Install Mode + Operating Mode -----------
$topY = 95
$leftX = 18
$totalWidth = 684
$gapX = 18
$halfWidth = [int](($totalWidth - $gapX) / 2)

# ----- Install Mode  -----
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

# ----- Operating Mode -----
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
$cbTray.Text = "Enable Tray Icon"
$cbTray.AutoSize = $true
$cbTray.Location = New-Object System.Drawing.Point(15, 182)
$cfgGroup.Controls.Add($cbTray)

$cbAutoRecovery = New-Object System.Windows.Forms.CheckBox
$cbAutoRecovery.Text = "Enable Auto-Recovery"
$cbAutoRecovery.AutoSize = $true
$cbAutoRecovery.Location = New-Object System.Drawing.Point(185, 182)
$cfgGroup.Controls.Add($cbAutoRecovery)
$script:cbAutoRecovery = $cbAutoRecovery

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
$tooltip.SetToolTip($cbAutoRecovery,
    "Automatically detects if your main mixer application (e.g. BEACN) crashes or is closed unexpectedly, relaunching it immediately.")
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
$detailsPanel.Location = New-Object System.Drawing.Point(350, 30)
$detailsPanel.Size = New-Object System.Drawing.Size(315, 128)
$deviceGroup.Controls.Add($detailsPanel)

$lblDetailsTitle = New-Object System.Windows.Forms.Label
$lblDetailsTitle.Text = "Selected Profile:"
$lblDetailsTitle.AutoSize = $true

$lblDetailsTitle.Font = $lblDetailsTitleFont
$lblDetailsTitle.Location = New-Object System.Drawing.Point(0, 2)
$detailsPanel.Controls.Add($lblDetailsTitle)



$lblProc = New-Object System.Windows.Forms.Label
$lblProc.Text = "Process: (unknown)"
$lblProc.Font = $detailsFont
$lblProc.AutoSize = $true
$lblProc.Location = New-Object System.Drawing.Point(0, 16)
$detailsPanel.Controls.Add($lblProc)

$lblPath = New-Object System.Windows.Forms.Label
$lblPath.Text = "Path: (unknown)"
$lblPath.Font = $detailsFont
$lblPath.AutoSize = $false
$lblPath.AutoEllipsis = $true
$lblPath.Size = New-Object System.Drawing.Size(305, 20)
$lblPath.Location = New-Object System.Drawing.Point(0, 32)
$detailsPanel.Controls.Add($lblPath)

$lblCaps = New-Object System.Windows.Forms.Label
$lblCaps.Text = "Supports: (unknown)"
$lblCaps.Font = $detailsFont
$lblCaps.AutoSize = $true
$lblCaps.Location = New-Object System.Drawing.Point(0, 54)
$detailsPanel.Controls.Add($lblCaps)

function Set-ProfileDetails {
    param($profileObj)

    if (-not $profileObj) {
        $lblProc.Text = "Process: (unknown)"
        $lblPath.Text = "Path: (unknown)"
        $tooltip.SetToolTip($lblPath, $null)
        $lblCaps.Text = "Supports: (unknown)"
    }
    else {
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
            $tooltip.SetToolTip($lblPath, "Full path: $path")
            $lblCaps.Text = "Supports: $caps"
        }
        catch {
            $lblProc.Text = "Process: (unknown)"
            $lblPath.Text = "Path: (unknown)"
            $tooltip.SetToolTip($lblPath, $null)
            $lblCaps.Text = "Supports: (unknown)"
        }
    }
    if (-not $script:ProfileDetailsInitialized) {
        # Force WinForms to calculate AutoSize bounds immediately
        [System.Windows.Forms.Application]::DoEvents()
 
        # Dynamically stack labels perfectly at any DPI scaling factor
        $lblProc.Top = $lblDetailsTitle.Bottom + 4
 
        # Path is AutoSize=$false (for ellipsis), so it must borrow the scaled height of Proc
        $lblPath.Height = $lblProc.Height 
        $lblPath.Top = $lblProc.Bottom + 2
 
        $lblCaps.Top = $lblPath.Bottom + 4
 
        $script:ProfileDetailsInitialized = $true
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

            if ($p.Id -eq "BEACN") {
                $tooltip.SetToolTip($rb, "To set up the recommended configuration for BEACN:`n1. Select the BEACN profile under Device Settings.`n2. Select Hidden install mode (runs silently in the background).`n3. Select Graceful operating mode (cleanly shuts down the BEACN app).`n4. Click 'Install / Update' to install the background task.`n5. Approve the Power Plan Fix if prompted to ensure proper screen-off timing.")
            }
            elseif ($p.Id -eq "DEMO") {
                $tooltip.SetToolTip($rb, "Demo Device (UI Test):`nUse this profile to test the SAMISH user interface, simulated sleep blocker scans, and wake/resume action simulation. This profile also serves as a developer template to model custom device adapter modules from.")
            }
            elseif ($p.Id -eq "Voicemeeter") {
                $tooltip.SetToolTip($rb, "To set up the recommended configuration for Voicemeeter:`n1. Select the Voicemeeter profile under Device Settings.`n2. Select Graceful operating mode (sends WM_CLOSE to gracefully save settings and shut down Voicemeeter, preventing device hangs and distorted audio on wake).`n3. Click 'Install / Update'.`nNote: Voicemeeter will be restarted automatically on system wake.")
            }
            elseif ($p.Id -eq "WaveLink") {
                $tooltip.SetToolTip($rb, "To set up the recommended configuration for Elgato Wave Link:`n1. Select the Wave Link profile under Device Settings.`n2. Select Graceful operating mode (safely terminates WaveLink.exe to preserve active stream/mic routing settings).`n3. Click 'Install / Update'.`nNote: Wave Link is automatically restarted on system resume to restore microphone and output feeds.")
            }
            elseif ($p.Id -eq "GoXLR") {
                $tooltip.SetToolTip($rb, "To set up the recommended configuration for GoXLR App:`n1. Select the GoXLR profile under Device Settings.`n2. Select Graceful operating mode to cleanly terminate the GoXLR App.`n3. Click 'Install / Update'.`nNote: Relaunches on wake to restore profiles and motor-fader positions.")
            }
            elseif ($p.Id -eq "Custom") {
                $tooltip.SetToolTip($rb, "Custom Device (Advanced User Mode):`nAllows you to control any unsupported mixer or application.`n`nTo configure:`n1. Open and edit the profile config file in your installation directory:`n   %APPDATA%\SAMISH\Profiles\Custom-Device.json`n2. Modify the Display Name, Process Name, and executable path.`n3. Click 'Read Setup Status' in Setup to apply changes instantly.`n`n*Tip: Run 'Configure-CustomProfile.bat' in the install folder for an interactive, guided setup helper.")
            }

            $rb.add_CheckedChanged({
                    param($sender, $e)
                    if (-not $sender.Checked) { return }

                    $selectedId = [string]$sender.Tag
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
$statusBox.Name = "statusBox"
$statusBox.Multiline = $true
$statusBox.ReadOnly = $true
$statusBox.ScrollBars = "Vertical"
$statusBox.WordWrap = $true
$statusBox.BorderStyle = "FixedSingle"
$statusBox.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 250)

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
        if ($null -ne $cfg -and $null -ne $cfg.MonitoredApps) {
            $script:MonitoredApps = @(foreach ($app in $cfg.MonitoredApps) {
                    if ($null -eq $app.PSObject.Properties['OnWakeAction']) {
                        $onWake = "Smart"
                        if ($null -ne $app.NoRestartOnWake -and $app.NoRestartOnWake) {
                            $onWake = "KeepClosed"
                        }
                        elseif ($null -ne $app.ForcePlayOnWake -and $app.ForcePlayOnWake) {
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
            if ($null -ne $cfg -and (
                    ($null -ne $cfg.EnableTrayIcon -and $cfg.EnableTrayIcon) -or
                    ($null -ne $cfg.EnableHotkey -and $cfg.EnableHotkey)
                )) {
                $rbInteractive.Checked = $true
            }
            else {
                $rbHidden.Checked = $true
            }
        }

        # --- Operating Mode radios ---
        if ($null -ne $cfg -and $null -ne $cfg.OperatingMode) {
            if ($cfg.OperatingMode -eq "Classic") {
                $rbOpClassic.Checked = $true
            }
            else {
                $rbOpGraceful.Checked = $true
            }
        }
        else {
            $rbOpGraceful.Checked = $true  # Default
        }

        # --- Logging ---
        if ($null -ne $cfg -and $null -ne $cfg.EnableLogging) {
            $cbLogging.Checked = [bool]$cfg.EnableLogging
        }
        else {
            $cbLogging.Checked = $false
        }

        if ($null -ne $cfg -and $null -ne $cfg.LogEverySeconds) {
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
        else {
            $ddLogInterval.SelectedItem = "Every 30 seconds"
            $tbLogCustom.Text = "30"
            $tbLogCustom.Enabled = $false
        }

        # --- Tray / Hotkey ---
        if ($null -ne $cfg -and $null -ne $cfg.EnableTrayIcon) {
            $cbTray.Checked = [bool]$cfg.EnableTrayIcon
        }
        else {
            $cbTray.Checked = $false
        }

        if ($null -ne $cfg -and $null -ne $cfg.EnableHotkey) {
            $cbHotkey.Checked = [bool]$cfg.EnableHotkey
        }
        else {
            $cbHotkey.Checked = $false
        }

        if ($null -ne $cfg -and $cfg.PSObject.Properties.Match('EnableAutoRecovery').Count -gt 0) {
            $cbAutoRecovery.Checked = [bool]$cfg.EnableAutoRecovery
        }
        else {
            $cbAutoRecovery.Checked = $true
        }

        # --- Hotkey mode ---
        if ($null -ne $cfg -and $null -ne $cfg.HotkeyMode) {
            $ddHotkey.SelectedItem = [string]$cfg.HotkeyMode
        }
        else {
            $ddHotkey.SelectedItem = "ScrollLock"
        }

        # --- Custom hotkey textbox reverse-map (VK -> friendly) ---
        if ($null -ne $cfg -and $null -ne $cfg.HotkeyMode -and $cfg.HotkeyMode -eq "Custom" -and $null -ne $cfg.CustomHotkeyVirtualKey) {
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
        else {
            $tbCustomKey.Text = "F8"
        }

        # --- Apply enable/disable states WITHOUT clobbering values ---
        if ($rbHidden.Checked) {
            $cbTray.Enabled = $false
        }
        else {
            $cbTray.Enabled = $true
        }

        # Logging enablement sync
        $ddLogInterval.Enabled = $cbLogging.Checked
        if ($cbLogging.Checked) {
            $tbLogCustom.Enabled = ($ddLogInterval.SelectedItem.ToString() -eq "Custom seconds...")
        }
        else {
            $tbLogCustom.Enabled = $false
        }

        # Hotkey enablement sync
        $ddHotkey.Enabled = $cbHotkey.Checked
        $isCustomHotkey = $false
        if ($cbHotkey.Checked -and $ddHotkey.SelectedItem) {
            $isCustomHotkey = ($ddHotkey.SelectedItem.ToString() -eq "Custom")
        }
        $tbCustomKey.Enabled = $isCustomHotkey

        # --- Theme ---
        if ($null -ne $cfg -and $null -ne $cfg.Theme) {
            $isNeon = ($cfg.Theme -eq "Neon")
            if ($global:ThemeNeonActive -ne $isNeon -or $null -eq $global:NeonCyan) {
                $global:ThemeNeonActive = $isNeon
                if (Get-Command Set-BrandTheme -ErrorAction SilentlyContinue) {
                    try { Set-BrandTheme -Form $form -IsNeon $isNeon } catch {}
                }
            }
        }

        # Refresh the test group now that MonitoredApps and profile data are loaded.
        if (Get-Command Update-TestGroupState -ErrorAction SilentlyContinue) {
            Update-TestGroupState
        }
    }
    catch {
        $errPath = if ($global:PackageDir) { "$global:PackageDir\SAMISH_ERROR.txt" } else { "C:\Scripts\GOOGLE-ANTI-GRAVITY\SAMISH\SAMISH_ERROR.txt" }
        Out-File -FilePath $errPath -Append `
            -InputObject "[$(Get-Date -Format 'HH:mm:ss')] Apply-UIFromConfigIfPresent Exception: $($_.Exception.Message) at $($_.ScriptStackTrace)"
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


# v1.1.0: Install/Uninstall buttons (creation code; repositioned to tabPage1 below)
$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Name = "btnInstall"
$btnInstall.Text = "Install / Update"
$btnInstall.Font = $boldFont
$btnInstall.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnInstall.FlatAppearance.BorderSize = 1
$btnInstall.FlatAppearance.BorderColor = $BrandPurple
$btnInstall.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnInstall.BackColor = [System.Drawing.Color]::Transparent
$btnInstall.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$script:btnInstall = $btnInstall

$btnUninstall = New-Object System.Windows.Forms.Button
$btnUninstall.Name = "btnUninstall"
$btnUninstall.Text = "Uninstall"
$btnUninstall.Font = $font
$btnUninstall.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnUninstall.FlatAppearance.BorderSize = 1
$btnUninstall.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$btnUninstall.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnUninstall.BackColor = [System.Drawing.Color]::Transparent
$btnUninstall.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
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
$tbLogCustom.Width = 75
$lblLogCustom.Location = New-Object System.Drawing.Point(310, 60)

$cbHotkey.Location = New-Object System.Drawing.Point(15, 92)
$lblHotkey.Location = New-Object System.Drawing.Point(25, 122)
$ddHotkey.Location = New-Object System.Drawing.Point(85, 118)
$ddHotkey.Width = 135
$cfgGroup.Controls.Remove($lblCustomKey)
$tbCustomKey.Location = New-Object System.Drawing.Point(230, 118)
$tbCustomKey.Width = 75
$lblCustomHint.Location = New-Object System.Drawing.Point(85, 142)

$cbTray.Location = New-Object System.Drawing.Point(15, 164)
$cbAutoRecovery.Location = New-Object System.Drawing.Point(185, 164)

# Action Row Page 1 Left
$btnInstall.Size = New-Object System.Drawing.Size(210, 36)
$btnInstall.Location = New-Object System.Drawing.Point(10, 410)
$tooltip.SetToolTip($btnInstall, "Install or update SAMISH using the selected settings.")

$btnUninstall.Size = New-Object System.Drawing.Size(150, 36)
$btnUninstall.Location = New-Object System.Drawing.Point(230, 410)
$tooltip.SetToolTip($btnUninstall, "Remove SAMISH. To temporarily stop SAMISH from launching on boot, click Uninstall. You will have the option to save your profiles and configuration settings to be automatically reapplied on reinstall.")

# Right Column
$deviceGroup.Size = New-Object System.Drawing.Size(370, 185)
$deviceGroup.Location = New-Object System.Drawing.Point(395, 10)

$profilesPanel.Location = New-Object System.Drawing.Point(10, 16)
$profilesPanel.Size = New-Object System.Drawing.Size(350, 79)

$detailsPanel.Location = New-Object System.Drawing.Point(10, 96)
$detailsPanel.Size = New-Object System.Drawing.Size(350, 86)

$statusGroup.Size = New-Object System.Drawing.Size(370, 195)
$statusGroup.Location = New-Object System.Drawing.Point(395, 200)

$statusBox.Location = New-Object System.Drawing.Point(10, 25)
$statusBox.Size = New-Object System.Drawing.Size(350, 160)



# Action Row Page 1 Right (Advanced Tools Toggle)
$btnToolsAdvanced = New-Object System.Windows.Forms.Button
$btnToolsAdvanced.Name = "btnToolsAdvanced"
$btnToolsAdvanced.Text = "Advanced Tools >>"
$btnToolsAdvanced.Font = $font
$btnToolsAdvanced.Size = New-Object System.Drawing.Size(370, 36)
$btnToolsAdvanced.Location = New-Object System.Drawing.Point(395, 410)
$btnToolsAdvanced.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnToolsAdvanced.FlatAppearance.BorderSize = 1
$btnToolsAdvanced.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$btnToolsAdvanced.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnToolsAdvanced.BackColor = [System.Drawing.Color]::Transparent
$btnToolsAdvanced.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$tabPage1.Controls.Add($btnToolsAdvanced)
$script:btnToolsAdvanced = $btnToolsAdvanced
$tooltip.SetToolTip($btnToolsAdvanced, "Open or close the advanced utility and log monitoring tools drawer.")

# Page 1 Drawer Vertical Separator Line
$toolsDrawerSep = New-Object System.Windows.Forms.Label
$toolsDrawerSep.Name = "toolsDrawerSep"
$toolsDrawerSep.Size = New-Object System.Drawing.Size(2, 443)
$toolsDrawerSep.Location = New-Object System.Drawing.Point(777, 10)
$toolsDrawerSep.BackColor = $BrandPurple
$toolsDrawerSep.Visible = $false
$tabPage1.Controls.Add($toolsDrawerSep)
$script:toolsDrawerSep = $toolsDrawerSep

# 3. Page 1 Slide-Out Drawer: "Advanced Tools & Utilities"
$grpAdvancedTools = New-Object System.Windows.Forms.GroupBox
$grpAdvancedTools.Text = "Advanced Tools && Utilities"
$grpAdvancedTools.Font = $font
$grpAdvancedTools.Size = New-Object System.Drawing.Size(370, 385)
$grpAdvancedTools.Location = New-Object System.Drawing.Point(790, 10)
$grpAdvancedTools.Visible = $false
$tabPage1.Controls.Add($grpAdvancedTools)
$script:grpAdvancedTools = $grpAdvancedTools
$tooltip.SetToolTip($grpAdvancedTools, "Advanced utility tools and live background service monitoring.")

# Create Sub-Tabs for Advanced Tools (Tools vs. Live Log)
$btnSubTabTools = New-Object System.Windows.Forms.Button
$btnSubTabTools.Name = "btnSubTabTools"
$btnSubTabTools.Text = "Tools"
$btnSubTabTools.Font = $boldFont
$btnSubTabTools.Size = New-Object System.Drawing.Size(75, 22)
$btnSubTabTools.Location = New-Object System.Drawing.Point(190, 16)
$btnSubTabTools.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnSubTabTools.FlatAppearance.BorderSize = 0
$btnSubTabTools.BackColor = [System.Drawing.SystemColors]::Control
$btnSubTabTools.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnSubTabTools.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$btnSubTabTools.Visible = $false
$grpAdvancedTools.Controls.Add($btnSubTabTools)
$btnSubTabTools.BringToFront()
$script:btnSubTabTools = $btnSubTabTools
$tooltip.SetToolTip($btnSubTabTools, "View advanced setup actions and utilities.")

$btnSubTabLive = New-Object System.Windows.Forms.Button
$btnSubTabLive.Name = "btnSubTabLive"
$btnSubTabLive.Text = "Live Log"
$btnSubTabLive.Font = $font
$btnSubTabLive.Size = New-Object System.Drawing.Size(75, 22)
$btnSubTabLive.Location = New-Object System.Drawing.Point(270, 16)
$btnSubTabLive.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnSubTabLive.FlatAppearance.BorderSize = 0
$btnSubTabLive.BackColor = [System.Drawing.SystemColors]::Control
$btnSubTabLive.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
$btnSubTabLive.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$btnSubTabLive.Visible = $false
$grpAdvancedTools.Controls.Add($btnSubTabLive)
$btnSubTabLive.BringToFront()
$script:btnSubTabLive = $btnSubTabLive
$tooltip.SetToolTip($btnSubTabLive, "Monitor the live SAMISH activity and background service logs.")

# Sliding sub-tab indicator line (replacing subSep)
$advancedTabIndicator = New-Object System.Windows.Forms.Label
$advancedTabIndicator.Name = "advancedTabIndicator"
$advancedTabIndicator.Size = New-Object System.Drawing.Size(75, 2)
$advancedTabIndicator.Location = New-Object System.Drawing.Point(190, 38)
$advancedTabIndicator.BackColor = $BrandPurple
$advancedTabIndicator.Visible = $false
$grpAdvancedTools.Controls.Add($advancedTabIndicator)
$script:advancedTabIndicator = $advancedTabIndicator

# Sub-Separator line under the sub-tab buttons (mirroring the main separator)
$subSep = New-Object System.Windows.Forms.Label
$subSep.Name = "subSep"
$subSep.Size = New-Object System.Drawing.Size(350, 2)
$subSep.Location = New-Object System.Drawing.Point(10, 41)
$subSep.BackColor = $BrandCyan
$grpAdvancedTools.Controls.Add($subSep)
$script:subSep = $subSep
$advancedTabIndicator.BringToFront()

# Create/Move tool buttons into Page 1 Drawer
$btnPowerPlan = New-Object System.Windows.Forms.Button
$btnPowerPlan.Text = "Verify & Restore Settings"
$btnPowerPlan.UseMnemonic = $false
$btnPowerPlan.Font = $font
$btnPowerPlan.Size = New-Object System.Drawing.Size(350, 32)
$btnPowerPlan.Location = New-Object System.Drawing.Point(10, 60)
$btnPowerPlan.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnPowerPlan.FlatAppearance.BorderSize = 1
$btnPowerPlan.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$btnPowerPlan.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnPowerPlan.BackColor = [System.Drawing.Color]::Transparent
$btnPowerPlan.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$grpAdvancedTools.Controls.Add($btnPowerPlan)
$script:btnPowerPlan = $btnPowerPlan
$tooltip.SetToolTip($btnPowerPlan, "Check, optimize, or restore your system power plan, USB selective suspend, disabled wake devices, and active wake timers.")

$btnOpenTS = New-Object System.Windows.Forms.Button
$btnOpenTS.Text = "Open Windows Task Scheduler"
$btnOpenTS.Font = $font
$btnOpenTS.Size = New-Object System.Drawing.Size(350, 32)
$btnOpenTS.Location = New-Object System.Drawing.Point(10, 105)
$btnOpenTS.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnOpenTS.FlatAppearance.BorderSize = 1
$btnOpenTS.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$btnOpenTS.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnOpenTS.BackColor = [System.Drawing.Color]::Transparent
$btnOpenTS.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$grpAdvancedTools.Controls.Add($btnOpenTS)
$script:btnOpenTS = $btnOpenTS
$tooltip.SetToolTip($btnOpenTS, "Open Windows Task Scheduler to view or manage SAMISH tasks.")

$btnCleanReset = New-Object System.Windows.Forms.Button
$btnCleanReset.Text = "Restart SAMISH Service"
$btnCleanReset.Font = $font
$btnCleanReset.Size = New-Object System.Drawing.Size(350, 32)
$btnCleanReset.Location = New-Object System.Drawing.Point(10, 150)
$btnCleanReset.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCleanReset.FlatAppearance.BorderSize = 1
$btnCleanReset.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$btnCleanReset.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnCleanReset.BackColor = [System.Drawing.Color]::Transparent
$btnCleanReset.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$grpAdvancedTools.Controls.Add($btnCleanReset)
$script:btnCleanReset = $btnCleanReset
$tooltip.SetToolTip($btnCleanReset, "Restart background service and check for errors (safely preserves configuration).")

$btnReadSetup = New-Object System.Windows.Forms.Button
$btnReadSetup.Text = "Read Setup & Status"
$btnReadSetup.UseMnemonic = $false
$btnReadSetup.Font = $font
$btnReadSetup.Size = New-Object System.Drawing.Size(350, 32)
$btnReadSetup.Location = New-Object System.Drawing.Point(10, 195)
$btnReadSetup.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnReadSetup.FlatAppearance.BorderSize = 1
$btnReadSetup.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$btnReadSetup.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnReadSetup.BackColor = [System.Drawing.Color]::Transparent
$btnReadSetup.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$grpAdvancedTools.Controls.Add($btnReadSetup)
$script:btnReadSetup = $btnReadSetup
$tooltip.SetToolTip($btnReadSetup, "Query and print the active installation status and current settings.")

$btnOpenLog = New-Object System.Windows.Forms.Button
$btnOpenLog.Text = "Open Setup Log"
$btnOpenLog.Font = $font
$btnOpenLog.Size = New-Object System.Drawing.Size(350, 32)
$btnOpenLog.Location = New-Object System.Drawing.Point(10, 240)
$btnOpenLog.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnOpenLog.FlatAppearance.BorderSize = 1
$btnOpenLog.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$btnOpenLog.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnOpenLog.BackColor = [System.Drawing.Color]::Transparent
$btnOpenLog.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$grpAdvancedTools.Controls.Add($btnOpenLog)
$script:btnOpenLog = $btnOpenLog
$tooltip.SetToolTip($btnOpenLog, "Open the main SAMISH text log in your default editor.")

# Create the dedicated Live Log console textbox inside the Page 1 Drawer (hidden initially)
$txtLiveLog = New-Object System.Windows.Forms.TextBox
$txtLiveLog.Name = "txtLiveLog"
$txtLiveLog.Multiline = $true
$txtLiveLog.ScrollBars = "Vertical"
$txtLiveLog.ReadOnly = $true
$txtLiveLog.Size = New-Object System.Drawing.Size(350, 279)
$txtLiveLog.Location = New-Object System.Drawing.Point(10, 55)
$txtLiveLog.Visible = $false
$txtLiveLog.BackColor = [System.Drawing.Color]::FromArgb(40, 44, 52)
$txtLiveLog.ForeColor = $BrandCyan
$grpAdvancedTools.Controls.Add($txtLiveLog)
$script:txtLiveLog = $txtLiveLog

$liveLogSep = New-Object System.Windows.Forms.Label
$liveLogSep.Name = "liveLogSep"
$liveLogSep.Size = New-Object System.Drawing.Size(350, 2)
$liveLogSep.Location = New-Object System.Drawing.Point(10, 334)
$liveLogSep.BackColor = $BrandPurple
$liveLogSep.Visible = $false
$grpAdvancedTools.Controls.Add($liveLogSep)
$script:liveLogSep = $liveLogSep

# Create the live log control buttons inside the Page 1 Drawer (hidden initially)
$btnLivePause = New-Object System.Windows.Forms.Button
$btnLivePause.Text = "Pause"
$btnLivePause.Size = New-Object System.Drawing.Size(100, 28)
$btnLivePause.Location = New-Object System.Drawing.Point(10, 344)
$btnLivePause.Visible = $false
$btnLivePause.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnLivePause.FlatAppearance.BorderSize = 1
$btnLivePause.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$btnLivePause.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnLivePause.BackColor = [System.Drawing.Color]::Transparent
$btnLivePause.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$grpAdvancedTools.Controls.Add($btnLivePause)
$script:btnLivePause = $btnLivePause
$tooltip.SetToolTip($btnLivePause, "Pause or resume the live log stream")

$btnLiveCopy = New-Object System.Windows.Forms.Button
$btnLiveCopy.Text = "Copy"
$btnLiveCopy.Size = New-Object System.Drawing.Size(100, 28)
$btnLiveCopy.Location = New-Object System.Drawing.Point(135, 344)
$btnLiveCopy.Visible = $false
$btnLiveCopy.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnLiveCopy.FlatAppearance.BorderSize = 1
$btnLiveCopy.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$btnLiveCopy.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnLiveCopy.BackColor = [System.Drawing.Color]::Transparent
$btnLiveCopy.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$grpAdvancedTools.Controls.Add($btnLiveCopy)
$script:btnLiveCopy = $btnLiveCopy
$tooltip.SetToolTip($btnLiveCopy, "Copy all visible log text to the clipboard")

$btnLiveClear = New-Object System.Windows.Forms.Button
$btnLiveClear.Text = "Clear"
$btnLiveClear.Size = New-Object System.Drawing.Size(100, 28)
$btnLiveClear.Location = New-Object System.Drawing.Point(260, 344)
$btnLiveClear.Visible = $false
$btnLiveClear.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnLiveClear.FlatAppearance.BorderSize = 1
$btnLiveClear.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$btnLiveClear.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnLiveClear.BackColor = [System.Drawing.Color]::Transparent
$btnLiveClear.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$grpAdvancedTools.Controls.Add($btnLiveClear)
$script:btnLiveClear = $btnLiveClear
$tooltip.SetToolTip($btnLiveClear, "Clear the log display (does not delete the log file)")



