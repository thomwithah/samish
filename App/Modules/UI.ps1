# ---------- UI ----------
$script:MainFormGdiResources = New-Object System.Collections.Generic.List[System.IDisposable]
. "$PSScriptRoot\UI.Theme.ps1"



$script:MonitoredApps = @()

$form = New-Object System.Windows.Forms.Form
$form.GetType().GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic).SetValue($form, $true, $null)
$form.Text = "$ProductName - Setup"
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.AutoScaleMode = "Font"

# Measure screen DPI scaling factor at startup
$graphics = $form.CreateGraphics()
$script:DpiScale = 1.0
try {
    $script:DpiScale = $graphics.DpiX / 96.0
}
catch {}
$graphics.Dispose()

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
$tabIndicatorLine.Size = New-Object System.Drawing.Size(145, 2)
$tabIndicatorLine.Location = New-Object System.Drawing.Point(330, 78)
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
        if ($global:ThemeNeonActive) {
            $penColor = if ($global:NeonPurple) { $global:NeonPurple } else { [System.Drawing.Color]::FromArgb(153, 51, 255) }
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
            $ctrl.ForeColor = [System.Drawing.SystemColors]::ControlText
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

