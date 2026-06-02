# ---------- UI ----------
function Set-ButtonVisualState {
    <#
    .SYNOPSIS
        Visually enable/disable a button while keeping Enabled=$true so tooltips work.

    .DESCRIPTION
        WinForms hides tooltips on controls with Enabled=$false. This function
        keeps the control enabled but dims its text and stores the logical state
        in Tag so click handlers can check before acting.
    #>
    param(
        [System.Windows.Forms.Button]$Button,
        [bool]$Active,
        [string]$ActiveTag = $null
    )
    if (-not $Button) { return }

    $Button.Enabled = $true
    if ($Active) {
        $Button.Tag = $ActiveTag
        if ($global:ThemeCustomActive) {
            $Button.ForeColor = $global:ThemeCustomPrimary
        } else {
            $Button.ForeColor = [System.Drawing.SystemColors]::ControlText
        }
    }
    else {
        $Button.Tag = "VisuallyDisabled"
        if ($global:ThemeCustomActive) {
            $Button.ForeColor = $global:ThemeCustomDisabledText
        }
        else {
            $Button.ForeColor = [System.Drawing.SystemColors]::GrayText
        }
    }
    $Button.Invalidate()
}

$form = New-Object System.Windows.Forms.Form
$form.GetType().GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic).SetValue($form, $true, $null)
$form.Text = "$ProductName - Setup"
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.AutoScaleMode = "Font"

# Measure screen DPI scaling factor at startup
$script:DpiScale = 1.0
try {
    $hwnd = $form.Handle
    $dpi = [SamishWin32]::GetDpiForWindow($hwnd)
    if ($dpi -gt 0) {
        $script:DpiScale = $dpi / 96.0
    }
    else {
        throw "GetDpiForWindow returned 0"
    }
}
catch {
    try {
        $graphics = $form.CreateGraphics()
        $script:DpiScale = $graphics.DpiX / 96.0
        $graphics.Dispose()
    }
    catch {}
}

$script:MainFormGdiResources = New-Object System.Collections.Generic.List[System.IDisposable]
. "$PSScriptRoot\UI.Theme.ps1"

$script:MonitoredApps = @()

$script:IsWindowExpanded = $false

$form.ClientSize = New-Object System.Drawing.Size(800, 640)

$formIconPath = Join-Path $PackageDir "Assets\128x128.ico"
if (Test-Path -LiteralPath $formIconPath) {
    try {
        $formIcon = New-Object System.Drawing.Icon($formIconPath)
        [void]$script:MainFormGdiResources.Add($formIcon)
        $form.Icon = $formIcon
    }
    catch { }
}



$title = New-Object System.Windows.Forms.Label
$title.Text = "$ProductName"

$title.Font = $titleFont
$title.ForeColor = $BrandPurple
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(18, 12)
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Name = "subtitle"
$subtitle.Text = ""

$subtitle.Font = $subtitleFont
$subtitle.ForeColor = $BrandCyan
$subtitle.AutoSize = $false
$subtitle.Size = New-Object System.Drawing.Size(300, 20)
$subtitle.UseMnemonic = $false
$subtitle.Location = New-Object System.Drawing.Point(20, 60)

$subtitle.add_Paint({
        param($sender, $e)
        $normalFont = $sender.Font
        $boldFont = New-Object System.Drawing.Font($normalFont.FontFamily, $normalFont.Size, [System.Drawing.FontStyle]::Bold)
    
        $words = @(
            @{ Init = "S"; Rest = "treaming" },
            @{ Init = "A"; Rest = "udio" },
            @{ Init = "M"; Rest = "ixer" },
            @{ Init = "I"; Rest = "nterface" },
            @{ Init = "S"; Rest = "leep" },
            @{ Init = "H"; Rest = "elper" }
        )
    
        $brush = New-Object System.Drawing.SolidBrush($sender.ForeColor)
        $sf = [System.Drawing.StringFormat]::GenericTypographic
        $x = 0.0
        $y = 0.0
        $spaceWidth = 5.0
    
        for ($i = 0; $i -lt $words.Count; $i++) {
            $w = $words[$i]
        
            # Draw bold initial
            $e.Graphics.DrawString($w.Init, $boldFont, $brush, $x, $y, $sf)
            $initSize = $e.Graphics.MeasureString($w.Init, $boldFont, [System.Drawing.PointF]::Empty, $sf)
            $x += $initSize.Width
        
            # Draw normal rest
            $e.Graphics.DrawString($w.Rest, $normalFont, $brush, $x, $y, $sf)
            $restSize = $e.Graphics.MeasureString($w.Rest, $normalFont, [System.Drawing.PointF]::Empty, $sf)
            $x += $restSize.Width
        
            # Add space after word (except for the last word)
            if ($i -lt $words.Count - 1) {
                $x += $spaceWidth
            }
        }
    
        $brush.Dispose()
        $boldFont.Dispose()
    })

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
        [void]$script:MainFormGdiResources.Add($logoImg)
        $logo.Image = $logoImg
    }
}
$form.Controls.Add($logo)
$script:logo = $logo

# Separator line under header (matching diagnostics window style)
$mainSep = New-Object System.Windows.Forms.Label
$mainSep.Name = "mainSep"
$mainSep.Size = New-Object System.Drawing.Size(764, 2)
$mainSep.Location = New-Object System.Drawing.Point(18, 84)
$mainSep.BackColor = $BrandCyan
$form.Controls.Add($mainSep)
$script:mainSep = $mainSep

# =====================================================================
# DASHBOARD LAYOUT & CONTROLS RESTRUCTURING (SAMISH v1.1.0)
# =====================================================================

# Create Custom Flat Navigation Buttons at the top of the form
$btnTabSetup = New-Object System.Windows.Forms.Button
$btnTabSetup.Name = "btnTabSetup"
$btnTabSetup.Text = "1. Setup && Install"
$btnTabSetup.Font = $boldFont
$btnTabSetup.Size = New-Object System.Drawing.Size(145, 30)
$btnTabSetup.Location = New-Object System.Drawing.Point(330, 48)
$btnTabSetup.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnTabSetup.FlatAppearance.BorderSize = 0
$btnTabSetup.BackColor = [System.Drawing.SystemColors]::Control
$btnTabSetup.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnTabSetup.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$form.Controls.Add($btnTabSetup)
$script:btnTabSetup = $btnTabSetup
$tooltip.SetToolTip($btnTabSetup, "Configure install mode, operating mode, and device profiles.")

$btnTabDiag = New-Object System.Windows.Forms.Button
$btnTabDiag.Name = "btnTabDiag"
$btnTabDiag.Text = "2. Sleep Automation"
$btnTabDiag.Font = $font
$btnTabDiag.Size = New-Object System.Drawing.Size(180, 30)
$btnTabDiag.Location = New-Object System.Drawing.Point(485, 48)
$btnTabDiag.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnTabDiag.FlatAppearance.BorderSize = 0
$btnTabDiag.BackColor = [System.Drawing.SystemColors]::Control
$btnTabDiag.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
$btnTabDiag.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$form.Controls.Add($btnTabDiag)
$script:btnTabDiag = $btnTabDiag
$tooltip.SetToolTip($btnTabDiag, "Scan for system sleep blockers, manage overrides, and test app wake actions.")

# Sliding indicator underline
$tabIndicatorLine = New-Object System.Windows.Forms.Label
$tabIndicatorLine.Name = "tabIndicatorLine"
$tabIndicatorLine.Size = New-Object System.Drawing.Size([int](145 * $script:DpiScale), [int](2 * $script:DpiScale))
$tabIndicatorLine.Location = New-Object System.Drawing.Point([int](330 * $script:DpiScale), [int](81 * $script:DpiScale))
$tabIndicatorLine.BackColor = $BrandPurple
$form.Controls.Add($tabIndicatorLine)
$script:tabIndicatorLine = $tabIndicatorLine

# Create wrapper panel for TabControl to implement custom borders and clip native borders
$pnlTabWrapper = New-Object System.Windows.Forms.Panel
$pnlTabWrapper.Name = "pnlTabWrapper"
$pnlTabWrapper.Location = New-Object System.Drawing.Point(10, 95)
$pnlTabWrapper.Size = New-Object System.Drawing.Size(780, 490)
$pnlTabWrapper.BackColor = [System.Drawing.Color]::Transparent
$form.Controls.Add($pnlTabWrapper)
$script:pnlTabWrapper = $pnlTabWrapper

$pnlTabWrapper.add_Paint({
        param($sender, $e)
        if ($global:ThemeCustomActive) {
            $penColor = if ($global:ThemeCustomSecondary) { $global:ThemeCustomSecondary } else { [System.Drawing.Color]::FromArgb(153, 51, 255) }
            $pen = New-Object System.Drawing.Pen($penColor, 1)
            $e.Graphics.DrawRectangle($pen, 0, 0, $sender.Width - 1, $sender.Height - 1)
            $pen.Dispose()
        }
    })

# Create borderless TabControl (clipped inside wrapper panel)
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Location = New-Object System.Drawing.Point(-4, -4)
$tabControl.Size = New-Object System.Drawing.Size(788, 498)
$tabControl.SizeMode = [System.Windows.Forms.TabSizeMode]::Fixed
$tabControl.ItemSize = New-Object System.Drawing.Size(0, 1)
$tabControl.Appearance = [System.Windows.Forms.TabAppearance]::FlatButtons
$pnlTabWrapper.Controls.Add($tabControl)
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

# Enable double buffering via reflection on TabControl and TabPages
$tabControl.GetType().GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic).SetValue($tabControl, $true, $null)
$tabPage1.GetType().GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic).SetValue($tabPage1, $true, $null)
$tabPage2.GetType().GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic).SetValue($tabPage2, $true, $null)

. "$PSScriptRoot\UI.SetupTab.ps1"
. "$PSScriptRoot\UI.DiagTab.ps1"

# 7. Style Reset & Metadata Location Update
$script:grpDiagOperatingMode = $grpOperatingMode
$script:diagTip = $tooltip

# Grey out Operating Mode box initially
$grpOperatingMode.ForeColor = [System.Drawing.Color]::Gray
foreach ($ctrl in $grpOperatingMode.Controls) { $ctrl.Enabled = $false }

# Position metadata footer
$bottomMetadata = New-Object System.Windows.Forms.Label
$bottomMetadata.Name = "bottomMetadata"
$bottomMetadata.Text = "$ProductName $ProductVersion  |  $AuthorLine"
$bottomMetadata.Font = $font
$bottomMetadata.ForeColor = $BrandCyan
$bottomMetadata.AutoSize = $false
$bottomMetadata.Size = New-Object System.Drawing.Size(300, 20)
$bottomMetadata.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$bottomMetadata.Location = New-Object System.Drawing.Point(480, 606)
$form.Controls.Add($bottomMetadata)
$script:bottomMetadata = $bottomMetadata
$bottomMetadata.BringToFront()
$tooltip.SetToolTip($bottomMetadata, "Double-click to open CHANGELOG.md (if present in the application folder).")

# Styling resets
# NOTE: controls named statusBox / txtLiveLog / lblDiagDetail are excluded from
# font AND ForeColor resets so they keep their custom colors/fonts.
function Reset-MainFormChildControls {
    param($container)
    foreach ($ctrl in $container.Controls) {
        if ($ctrl -isnot [System.Windows.Forms.GroupBox] -and
            $ctrl.Name -ne "statusBox" -and $ctrl.Name -ne "txtLiveLog" -and
            $ctrl.Name -ne "txtLastWake" -and
            $ctrl.Name -ne "btnSubTabTools" -and $ctrl.Name -ne "btnSubTabLive" -and
            $ctrl.Name -ne "advancedTabIndicator" -and
            $ctrl.Name -ne "btnTelemetryTabTimers" -and $ctrl.Name -ne "btnTelemetryTabArmed" -and
            $ctrl.Name -ne "btnInstall" -and
            $ctrl.Name -ne "liveLogSep" -and $ctrl.Name -ne "lblDiagDetail") {
            $ctrl.Font = $font
            # Don't overwrite ForeColor on controls marked as visually disabled
            if ($ctrl.Tag -ne 'VisuallyDisabled' -and $ctrl.Tag -ne 'SimpleRestoreDisabled') {
                $ctrl.ForeColor = [System.Drawing.SystemColors]::ControlText
            }
        }
        if ($ctrl.Controls.Count -gt 0) {
            Reset-MainFormChildControls $ctrl
        }
    }
}

foreach ($grp in @($modeGroup, $opGroup, $cfgGroup, $deviceGroup, $statusGroup, $grpAdvancedTools, $grpTest, $grpBlockers, $grpOverrides, $grpAutomated, $grpOperatingMode)) {
    $grp.Font = $boldFont
    $grp.ForeColor = [System.Drawing.SystemColors]::ControlText
    Reset-MainFormChildControls $grp
}

Reset-MainFormChildControls $tabPage1
Reset-MainFormChildControls $tabPage2


# Set initial tab style (Setup active by default)
$btnTabSetup.BackColor = [System.Drawing.SystemColors]::Control
$btnTabSetup.ForeColor = [System.Drawing.SystemColors]::ControlText
$btnTabSetup.Font = $boldFont
$btnTabSetup.FlatAppearance.BorderSize = 0
$btnTabDiag.BackColor = [System.Drawing.SystemColors]::Control
$btnTabDiag.ForeColor = [System.Drawing.Color]::DimGray
$btnTabDiag.Font = $font
$btnTabDiag.FlatAppearance.BorderSize = 0

# Set initial state of Clean Reset button based on install status
$script:IsSamishInstalled = Test-SamishInstalled
if ($script:IsSamishInstalled) {
    $btnCleanReset.Enabled = $true
}
else {
    $btnCleanReset.Enabled = $false
    $tooltip.SetToolTip($btnCleanReset, "SAMISH is not installed - clean reset unavailable.")
}



# Refresh state now that all tabs are loaded
if (Get-Command Update-TestGroupState -ErrorAction SilentlyContinue) {
    try { Update-TestGroupState } catch {}
}

# ---- UI Mode Toggle ----
# CheckBox in footer area for switching between Simple / Full
$script:chkUiMode = New-Object System.Windows.Forms.CheckBox
$script:chkUiMode.Name = "chkUiMode"
$script:chkUiMode.Text = "Full View"
$script:chkUiMode.Font = $font
$script:chkUiMode.AutoSize = $true
$script:chkUiMode.Location = New-Object System.Drawing.Point(15, 596)
$script:chkUiMode.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$script:chkUiMode.Checked = $true
$script:chkUiMode.FlatAppearance.BorderColor = $BrandCyan
$form.Controls.Add($script:chkUiMode)
$script:chkUiMode.BringToFront()
$tooltip.SetToolTip($script:chkUiMode, "Toggle between Simple (minimal dashboard) and Full (all controls and diagnostic panels) views.")


function Set-UiModeVisibility {
    <#
    .SYNOPSIS
        Adjusts panel visibility based on UI_Mode (Simple, Full).

    .DESCRIPTION
        Simple: Dashboard-only view -- Page 1 only, minimal controls, no diagnostics tab.
                Hides tab buttons, Operating Mode, logging/hotkey controls, Status/Activity,
                device detail labels, and replaces Advanced Tools with a Restore button.
        Full:   Complete UI with all controls, diagnostics, and advanced tools.
    #>
    param(
        [ValidateSet("Simple", "Full")]
        [string]$Mode = "Full"
    )

    # Skip if already in the requested mode (preserves open drawers, etc.)
    if ($script:currentUiMode -eq $Mode) { return }
    $script:currentUiMode = $Mode

    # Close any open drawers first (prevents stale expanded state)
    if (Get-Command Hide-All-Drawers -ErrorAction SilentlyContinue) {
        try { Hide-All-Drawers } catch {}
    }

    switch ($Mode) {
        "Simple" {
            # Force Page 1
            if ($tabControl) { $tabControl.SelectedIndex = 0 }

            # Hide tab navigation buttons and indicator line (pointless with only 1 page)
            if ($btnTabSetup) { $btnTabSetup.Visible = $false }
            if ($btnTabDiag) { $btnTabDiag.Visible = $false }
            if ($script:tabIndicatorLine) { $script:tabIndicatorLine.Visible = $false }

            # Hide Operating Mode group
            if ($opGroup) { $opGroup.Visible = $false }

            # General Settings: hide logging and hotkey rows, keep Tray + Auto-Recovery
            if ($cfgGroup) {
                if ($cbLogging) { $cbLogging.Visible = $false }
                if ($lblLogInterval) { $lblLogInterval.Visible = $false }
                if ($ddLogInterval) { $ddLogInterval.Visible = $false }
                if ($tbLogCustom) { $tbLogCustom.Visible = $false }
                if ($lblLogCustom) { $lblLogCustom.Visible = $false }
                if ($cbHotkey) { $cbHotkey.Visible = $false }
                if ($lblHotkey) { $lblHotkey.Visible = $false }
                if ($ddHotkey) { $ddHotkey.Visible = $false }
                if ($lblCustomKey) { $lblCustomKey.Visible = $false }
                if ($tbCustomKey) { $tbCustomKey.Visible = $false }
                if ($lblCustomHint) { $lblCustomHint.Visible = $false }

                # Move Tray + AutoRecovery checkboxes to top of group
                if ($cbTray) { $cbTray.Location = New-Object System.Drawing.Point(15, 30) }
                if ($cbAutoRecovery) { $cbAutoRecovery.Location = New-Object System.Drawing.Point(185, 30) }
            }

            # Hide Status / Activity box
            if ($statusGroup) { $statusGroup.Visible = $false }

            # Hide device detail labels (Selected Profile, Process, Path, Supports)
            if ($detailsPanel) { $detailsPanel.Visible = $false }

            # Page 2 diagnostic panels
            if ($script:grpBlockers) { $script:grpBlockers.Visible = $false }
            if ($script:grpOverrides) { $script:grpOverrides.Visible = $false }
            if ($script:grpTest) { $script:grpTest.Visible = $false }
            if ($script:grpOperatingMode) { $script:grpOperatingMode.Visible = $false }

            # --- Single-column layout (original column width, stacked vertically) ---
            $colWidth = 370

            # Install Mode: top row
            if ($modeGroup) {
                $modeGroup.Size = New-Object System.Drawing.Size($colWidth, 80)
                $modeGroup.Location = New-Object System.Drawing.Point(10, 10)
            }

            # Device Settings: tall enough to show all profiles with bottom border
            if ($deviceGroup) {
                $deviceGroup.Size = New-Object System.Drawing.Size($colWidth, 170)
                $deviceGroup.Location = New-Object System.Drawing.Point(10, 100)

                # Stretch the internal profiles list panel to fill the taller group
                $pPanel = $deviceGroup.Controls | Where-Object { $_ -is [System.Windows.Forms.Panel] -and $_.AutoScroll -eq $true } | Select-Object -First 1
                if ($pPanel) {
                    $pPanel.Size = New-Object System.Drawing.Size(($colWidth - 30), 135)
                }
            }

            # General Settings: just 2 checkboxes
            if ($cfgGroup) {
                $cfgGroup.Size = New-Object System.Drawing.Size($colWidth, 60)
                $cfgGroup.Location = New-Object System.Drawing.Point(10, 280)
            }

            # Restore Original Settings button: 13px gap above Install (matching Advanced Tools)
            if ($btnToolsAdvanced) {
                $btnToolsAdvanced.Size = New-Object System.Drawing.Size($colWidth, 36)
                $btnToolsAdvanced.Location = New-Object System.Drawing.Point(10, 361)

                # Check if any settings backups exist
                $hasBackup = $false
                try {
                    $backupPaths = @(
                        $script:DeviceWakeBackupPath,
                        $script:TaskWakeBackupPath,
                        $script:ServiceWakeBackupPath,
                        $script:PowerPlanBackupPath
                    )
                    foreach ($bp in $backupPaths) {
                        if ($bp -and (Test-Path -LiteralPath $bp)) {
                            $hasBackup = $true
                            break
                        }
                    }
                }
                catch {}

                $btnToolsAdvanced.Text = "Restore Original Settings"
                # Keep Enabled=$true always so tooltips work; use visual dimming + Tag to block clicks
                $btnToolsAdvanced.Enabled = $true
                if ($hasBackup) {
                    $btnToolsAdvanced.Tag = "SimpleRestore"
                    $btnToolsAdvanced.ForeColor = if ($global:ThemeCustomActive) { $global:ThemeCustomPrimary } else { [System.Drawing.SystemColors]::ControlText }
                    $tooltip.SetToolTip($btnToolsAdvanced, "Restore your system power plan and wake settings to their original state from SAMISH backups.")
                }
                else {
                    $btnToolsAdvanced.Tag = "SimpleRestoreDisabled"
                    if ($global:ThemeCustomActive) {
                        $btnToolsAdvanced.ForeColor = $global:ThemeCustomDisabledText
                    }
                    else {
                        $btnToolsAdvanced.ForeColor = [System.Drawing.SystemColors]::GrayText
                    }
                    $tooltip.SetToolTip($btnToolsAdvanced, "No settings backup found. SAMISH creates a backup when it modifies your power plan.")
                }
            }

            # Install / Uninstall buttons: exact Full mode sizes (210 + 150 = 370 = Restore width)
            if ($btnInstall) {
                $btnInstall.Size = New-Object System.Drawing.Size(210, 36)
                $btnInstall.Location = New-Object System.Drawing.Point(10, 410)
            }
            if ($btnUninstall) {
                $btnUninstall.Size = New-Object System.Drawing.Size(150, 36)
                $btnUninstall.Location = New-Object System.Drawing.Point(230, 410)
            }

            # Resize window to fit single column (~20px margin each side of 370px content)
            $simpleWidth = [int](410 * $script:DpiScale)
            $simpleHeight = [int](640 * $script:DpiScale)
            $form.ClientSize = New-Object System.Drawing.Size($simpleWidth, $simpleHeight)
            if ($script:pnlTabWrapper) {
                $script:pnlTabWrapper.Size = New-Object System.Drawing.Size(([int]($simpleWidth - 20)), [int](490 * $script:DpiScale))
            }
            $tabControl.Size = New-Object System.Drawing.Size(([int]($simpleWidth - 12)), [int](498 * $script:DpiScale))

            # Footer: dropdown position stays the same in both modes
            # Stack version and credit text, left-justified, to the right of dropdown
            if ($script:bottomMetadata) {
                $script:bottomMetadata.Text = "$ProductName $ProductVersion`n$AuthorLine"
                $script:bottomMetadata.Size = New-Object System.Drawing.Size(([int]($simpleWidth - 170)), 32)
                $script:bottomMetadata.Location = New-Object System.Drawing.Point(160, 592)
                $script:bottomMetadata.TextAlign = [System.Drawing.ContentAlignment]::TopRight
            }

            # Logo stays in top-right but adjusts for narrower window
            if ($script:logo) {
                $script:logo.Location = New-Object System.Drawing.Point([int](($simpleWidth - 82)), [int](12 * $script:DpiScale))
            }
        }
        "Full" {
            # Restore window to full 2-column width
            $form.ClientSize = New-Object System.Drawing.Size([int](800 * $script:DpiScale), [int](640 * $script:DpiScale))
            if ($script:pnlTabWrapper) {
                $script:pnlTabWrapper.Size = New-Object System.Drawing.Size([int](780 * $script:DpiScale), [int](490 * $script:DpiScale))
            }
            $tabControl.Size = New-Object System.Drawing.Size([int](788 * $script:DpiScale), [int](498 * $script:DpiScale))

            # Restore footer positions
            if ($script:bottomMetadata) {
                $script:bottomMetadata.Text = "$ProductName $ProductVersion  |  $AuthorLine"
                $script:bottomMetadata.Size = New-Object System.Drawing.Size(300, 20)
                $script:bottomMetadata.Location = New-Object System.Drawing.Point(480, 600)
                $script:bottomMetadata.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
            }
            if ($script:logo) {
                $script:logo.Location = New-Object System.Drawing.Point([int](718 * $script:DpiScale), [int](12 * $script:DpiScale))
            }

            # Show tab navigation buttons and indicator line
            if ($btnTabSetup) { $btnTabSetup.Visible = $true }
            if ($btnTabDiag) { $btnTabDiag.Visible = $true }
            if ($script:tabIndicatorLine) { $script:tabIndicatorLine.Visible = $true }

            # Show Operating Mode group
            if ($opGroup) { $opGroup.Visible = $true }

            # General Settings: restore all controls
            if ($cfgGroup) {
                if ($cbLogging) { $cbLogging.Visible = $true }
                if ($lblLogInterval) { $lblLogInterval.Visible = $true }
                if ($ddLogInterval) { $ddLogInterval.Visible = $true }
                if ($tbLogCustom) { $tbLogCustom.Visible = $true }
                if ($lblLogCustom) { $lblLogCustom.Visible = $true }
                if ($cbHotkey) { $cbHotkey.Visible = $true }
                if ($lblHotkey) { $lblHotkey.Visible = $true }
                if ($ddHotkey) { $ddHotkey.Visible = $true }
                if ($lblCustomKey) { $lblCustomKey.Visible = $true }
                if ($tbCustomKey) { $tbCustomKey.Visible = $true }
                if ($lblCustomHint) { $lblCustomHint.Visible = $true }

                # Restore Tray + AutoRecovery positions (from layout)
                if ($cbTray) { $cbTray.Location = New-Object System.Drawing.Point(15, 164) }
                if ($cbAutoRecovery) { $cbAutoRecovery.Location = New-Object System.Drawing.Point(185, 164) }
            }

            # Show Status / Activity box
            if ($statusGroup) { $statusGroup.Visible = $true }

            # Show device detail labels
            if ($detailsPanel) { $detailsPanel.Visible = $true }

            # Show Page 2 diagnostic panels
            if ($script:grpBlockers) { $script:grpBlockers.Visible = $true }
            if ($script:grpOverrides) { $script:grpOverrides.Visible = $true }
            if ($script:grpTest) { $script:grpTest.Visible = $true }
            if ($script:grpOperatingMode) { $script:grpOperatingMode.Visible = $true }

            # --- Restore 2-column layout (from UI.SetupTab.ps1 positioning) ---

            # Left Column
            if ($modeGroup) {
                $modeGroup.Size = New-Object System.Drawing.Size(370, 85)
                $modeGroup.Location = New-Object System.Drawing.Point(10, 10)
            }
            if ($cfgGroup) {
                $cfgGroup.Size = New-Object System.Drawing.Size(370, 195)
                $cfgGroup.Location = New-Object System.Drawing.Point(10, 200)
            }

            # Right Column
            if ($deviceGroup) {
                $deviceGroup.Size = New-Object System.Drawing.Size(370, 185)
                $deviceGroup.Location = New-Object System.Drawing.Point(395, 10)

                # Restore the internal profiles list panel to Full mode size
                $pPanel = $deviceGroup.Controls | Where-Object { $_ -is [System.Windows.Forms.Panel] -and $_.AutoScroll -eq $true } | Select-Object -First 1
                if ($pPanel) {
                    $pPanel.Location = New-Object System.Drawing.Point(10, 16)
                    $pPanel.Size = New-Object System.Drawing.Size(350, 79)
                }
            }
            if ($statusGroup) {
                $statusGroup.Size = New-Object System.Drawing.Size(370, 195)
                $statusGroup.Location = New-Object System.Drawing.Point(395, 200)
            }

            # Restore button sizes and positions
            if ($btnInstall) {
                $btnInstall.Size = New-Object System.Drawing.Size(210, 36)
                $btnInstall.Location = New-Object System.Drawing.Point(10, 410)
            }
            if ($btnUninstall) {
                $btnUninstall.Size = New-Object System.Drawing.Size(150, 36)
                $btnUninstall.Location = New-Object System.Drawing.Point(230, 410)
            }
            if ($btnToolsAdvanced) {
                $btnToolsAdvanced.Size = New-Object System.Drawing.Size(370, 36)
                $btnToolsAdvanced.Location = New-Object System.Drawing.Point(395, 410)
                $btnToolsAdvanced.Text = "Advanced Tools >>"
                $btnToolsAdvanced.Enabled = $true
                $btnToolsAdvanced.Tag = $null
                $btnToolsAdvanced.ForeColor = if ($global:ThemeCustomActive) { $global:ThemeCustomPrimary } else { [System.Drawing.SystemColors]::ControlText }
                $tooltip.SetToolTip($btnToolsAdvanced, "Open or close the advanced utility and log monitoring tools drawer.")
            }

            # Refresh tab indicator for current state
            if (Get-Command Update-TabIndicator -ErrorAction SilentlyContinue) {
                try { Update-TabIndicator } catch {}
            }
        }
    }
}

# Event handler for mode change
$script:chkUiMode.add_CheckedChanged({
        $selectedMode = if ($script:chkUiMode.Checked) { "Full" } else { "Simple" }
        Set-UiModeVisibility -Mode $selectedMode

        # Persist to config.json
        try {
            if (Test-Path -LiteralPath $ConfigPath) {
                $raw = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction SilentlyContinue
                if (-not [string]::IsNullOrWhiteSpace($raw)) {
                    $cfg = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($cfg) {
                        if ($cfg.PSObject.Properties.Name -contains "UI_Mode") {
                            $cfg.UI_Mode = $selectedMode
                        }
                        else {
                            $cfg | Add-Member -MemberType NoteProperty -Name "UI_Mode" -Value $selectedMode -Force
                        }
                        $json = $cfg | ConvertTo-Json -Depth 6
                        if (Get-Command Save-ContentAtomic -ErrorAction SilentlyContinue) {
                            Save-ContentAtomic -Path $ConfigPath -Content $json
                        }
                        else {
                            Set-Content -LiteralPath $ConfigPath -Value $json -Encoding UTF8
                        }
                    }
                }
            }
        }
        catch {
            # Fail-forward: UI mode change still applies visually even if config save fails
        }
    })

# Read initial UI_Mode from config and apply
try {
    if (Test-Path -LiteralPath $ConfigPath) {
        $raw = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction SilentlyContinue
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $cfgBoot = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($cfgBoot -and $cfgBoot.PSObject.Properties.Name -contains "UI_Mode") {
                $bootMode = [string]$cfgBoot.UI_Mode
                if ($bootMode -in @("Simple", "Full")) {
                    $script:chkUiMode.Checked = ($bootMode -eq "Full")
                    Set-UiModeVisibility -Mode $bootMode
                }
            }
        }
    }
}
catch {}

