# SAMISH Stealth Theme Extension Module
# Handles the "Anti-Gravity Cyberpunk" Sequence

# Global state to prevent overlapping triggers
if ($null -eq $global:ThemeCustomActive) { $global:ThemeCustomActive = $false }
if ($null -eq $global:IsThemeAnimating) { $global:IsThemeAnimating = $false }
if ($null -eq $global:OriginalTops) { $global:OriginalTops = @{} }
if ($null -eq $global:OriginalControlStyles) {
    $global:OriginalControlStyles = @{}
}

if ($null -eq $global:PackageDir) {
    if ($PackageDir) {
        $global:PackageDir = $PackageDir
    }
    elseif ($PSScriptRoot) {
        $global:PackageDir = Split-Path -Parent $PSScriptRoot
    }
    else {
        $global:PackageDir = "C:\Scripts\GOOGLE-ANTI-GRAVITY\SAMISH"
    }
}

$global:ImgColorPath = Join-Path $global:PackageDir "Assets\SAMISH-SQUARE-STYLIZED.png"
$global:ImgGrayPath = Join-Path $global:PackageDir "Assets\SAMISH-SQUARE-GREYSCALE-STYLIZED3.png"

# Neon Palette - MUST BE GLOBAL to survive dot-sourcing inside a scriptblock
# Fallback Neon Theme Set (hardcoded Easter egg values)
$global:ThemeNeonBackground = [System.Drawing.Color]::FromArgb(15, 15, 18)       # #0F0F12
$global:ThemeNeonSecondary = [System.Drawing.Color]::FromArgb(153, 51, 255)      # From stylized logo
$global:ThemeNeonAlert = [System.Drawing.Color]::FromArgb(255, 0, 102)           # #FF0066
$global:ThemeNeonHighlight = [System.Drawing.Color]::FromArgb(179, 255, 0)       # #b3ff00
$global:ThemeNeonPrimary = [System.Drawing.Color]::FromArgb(0, 245, 212)         # #00f5d4
$global:ThemeNeonText = [System.Drawing.Color]::FromArgb(255, 255, 255)          # #FFFFFF
$global:ThemeNeonButton = [System.Drawing.Color]::FromArgb(35, 35, 40)           # #232328
$global:ThemeNeonButtonHover = [System.Drawing.Color]::FromArgb(50, 50, 60)      # #32323C
$global:ThemeNeonInput = [System.Drawing.Color]::FromArgb(25, 25, 30)            # #19191E
$global:ThemeNeonPanel = [System.Drawing.Color]::FromArgb(18, 18, 22)            # #121216
$global:ThemeNeonDisabled = [System.Drawing.Color]::FromArgb(10, 10, 12)         # #0A0A0C
$global:ThemeNeonDisabledText = [System.Drawing.Color]::FromArgb(115, 135, 145)  # #738791

# Active custom variables that paint elements in the UI (initialized with Neon values by default)
$global:ThemeCustomBackground = $global:ThemeNeonBackground
$global:ThemeCustomSecondary = $global:ThemeNeonSecondary
$global:ThemeCustomAlert = $global:ThemeNeonAlert
$global:ThemeCustomHighlight = $global:ThemeNeonHighlight
$global:ThemeCustomPrimary = $global:ThemeNeonPrimary
$global:ThemeCustomText = $global:ThemeNeonText
$global:ThemeCustomButton = $global:ThemeNeonButton
$global:ThemeCustomButtonHover = $global:ThemeNeonButtonHover
$global:ThemeCustomInput = $global:ThemeNeonInput
$global:ThemeCustomPanel = $global:ThemeNeonPanel
$global:ThemeCustomDisabled = $global:ThemeNeonDisabled
$global:ThemeCustomDisabledText = $global:ThemeNeonDisabledText
$global:ThemeCustomCheckboxBg = $global:ThemeCustomInput
$global:ThemeCustomCheckboxBorder = $global:ThemeCustomSecondary
$global:ThemeCustomCheckboxCheck = $global:ThemeCustomPrimary

# Helper to convert various string formats (Hex, RGB, Name) into Color objects
function global:Get-ColorFromString {
    param([string]$str)
    if ([string]::IsNullOrWhiteSpace($str)) { return $null }
    $str = $str.Trim()
    try {
        if ($str.StartsWith("#")) {
            return [System.Drawing.ColorTranslator]::FromHtml($str)
        }
        if ($str -match "^(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})$") {
            return [System.Drawing.Color]::FromArgb([int]$matches[1], [int]$matches[2], [int]$matches[3])
        }
        return [System.Drawing.Color]::FromName($str)
    }
    catch {
        return $null
    }
}

# Helper to find a control's parent solid background color (for flat checkboxes/radiobuttons)
function global:Get-ParentSolidBackColor {
    param([System.Windows.Forms.Control]$c)
    $parent = $c.Parent
    while ($null -ne $parent) {
        if ($parent.BackColor -and $parent.BackColor -ne [System.Drawing.Color]::Transparent -and $parent.BackColor.A -eq 255) {
            return $parent.BackColor
        }
        $parent = $parent.Parent
    }
    return $global:ThemeCustomBackground
}

# Loader for custom_theme.json configuration
function global:Load-CustomThemeColors {
    try {
        $appDir = $null
        if ($global:PackageDir) {
            $appDir = Join-Path $global:PackageDir "App"
        }
        elseif ($PSScriptRoot) {
            $appDir = Split-Path -Parent $PSScriptRoot
        }
        else {
            $appDir = "C:\Scripts\GOOGLE-ANTI-GRAVITY\SAMISH\App"
        }
        $themePath = Join-Path $appDir "custom_theme.json"
        if (Test-Path -LiteralPath $themePath) {
            $raw = Get-Content -LiteralPath $themePath -Raw -ErrorAction SilentlyContinue
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $cfg = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($cfg) {
                    if ($cfg.BaseColors) {
                        if ($cfg.BaseColors.Background) { $global:ThemeCustomBackground = Get-ColorFromString $cfg.BaseColors.Background }
                        if ($cfg.BaseColors.Panel) { $global:ThemeCustomPanel = Get-ColorFromString $cfg.BaseColors.Panel }
                        if ($cfg.BaseColors.Input) { $global:ThemeCustomInput = Get-ColorFromString $cfg.BaseColors.Input }
                        if ($cfg.BaseColors.Button) { $global:ThemeCustomButton = Get-ColorFromString $cfg.BaseColors.Button }
                        if ($cfg.BaseColors.ButtonHover) { $global:ThemeCustomButtonHover = Get-ColorFromString $cfg.BaseColors.ButtonHover }
                        if ($cfg.BaseColors.Disabled) { $global:ThemeCustomDisabled = Get-ColorFromString $cfg.BaseColors.Disabled }
                        if ($cfg.BaseColors.DisabledText) { $global:ThemeCustomDisabledText = Get-ColorFromString $cfg.BaseColors.DisabledText }
                        if ($cfg.BaseColors.BorderDim) { $global:ThemeCustomBorderDim = Get-ColorFromString $cfg.BaseColors.BorderDim }
                        if ($cfg.BaseColors.Text) { $global:ThemeCustomText = Get-ColorFromString $cfg.BaseColors.Text }
                        if ($cfg.BaseColors.CheckboxBorder) { $global:ThemeCustomCheckboxBorder = Get-ColorFromString $cfg.BaseColors.CheckboxBorder }
                        if ($cfg.BaseColors.CheckboxCheck) { $global:ThemeCustomCheckboxCheck = Get-ColorFromString $cfg.BaseColors.CheckboxCheck }
                        if ($cfg.BaseColors.CheckboxBg) { $global:ThemeCustomCheckboxBg = Get-ColorFromString $cfg.BaseColors.CheckboxBg }
                    }
                    if ($cfg.VibrantAccents) {
                        if ($cfg.VibrantAccents.Primary) { $global:ThemeCustomPrimary = Get-ColorFromString $cfg.VibrantAccents.Primary }
                        if ($cfg.VibrantAccents.Secondary) { $global:ThemeCustomSecondary = Get-ColorFromString $cfg.VibrantAccents.Secondary }
                        if ($cfg.VibrantAccents.Alert) { $global:ThemeCustomAlert = Get-ColorFromString $cfg.VibrantAccents.Alert }
                        if ($cfg.VibrantAccents.Highlight) { $global:ThemeCustomHighlight = Get-ColorFromString $cfg.VibrantAccents.Highlight }
                    }
                }
            }
        }
    }
    catch {}
}

function global:Load-NeonThemeColors {
    $global:ThemeCustomBackground = $global:ThemeNeonBackground
    $global:ThemeCustomSecondary = $global:ThemeNeonSecondary
    $global:ThemeCustomAlert = $global:ThemeNeonAlert
    $global:ThemeCustomHighlight = $global:ThemeNeonHighlight
    $global:ThemeCustomPrimary = $global:ThemeNeonPrimary
    $global:ThemeCustomText = $global:ThemeNeonText
    $global:ThemeCustomButton = $global:ThemeNeonButton
    $global:ThemeCustomButtonHover = $global:ThemeNeonButtonHover
    $global:ThemeCustomInput = $global:ThemeNeonInput
    $global:ThemeCustomPanel = $global:ThemeNeonPanel
    $global:ThemeCustomDisabled = $global:ThemeNeonDisabled
    $global:ThemeCustomDisabledText = $global:ThemeNeonDisabledText
    $global:ThemeCustomCheckboxBg = $global:ThemeCustomInput
    $global:ThemeCustomCheckboxBorder = $global:ThemeCustomSecondary
    $global:ThemeCustomCheckboxCheck = $global:ThemeCustomPrimary
}

function global:Initialize-ActiveThemeColors {
    $cfgPath = Join-Path $env:APPDATA "SAMISH\config.json"
    $theme = "Normal"
    if (Test-Path -LiteralPath $cfgPath) {
        try {
            $cfg = (Get-Content -LiteralPath $cfgPath -Raw) | ConvertFrom-Json
            if ($cfg -and $cfg.PSObject.Properties.Match('Theme').Count -gt 0) {
                $theme = $cfg.Theme
            }
        } catch {}
    }
    
    if ($theme -eq "Custom") {
        Load-CustomThemeColors
    } else {
        Load-NeonThemeColors
    }
}

# Run color loading immediately to initialize custom theme colors
Initialize-ActiveThemeColors

function global:Register-HoverFadeAnimation {
    param(
        [System.Windows.Forms.Control]$c,
        [System.Drawing.Color]$NormalColor,
        [System.Drawing.Color]$HoverColor
    )

    if ($c.PSObject.Properties.Match('HoverAnimTimer').Count -eq 0) {
        $c | Add-Member -MemberType NoteProperty -Name 'HoverAnimTimer' -Value $null -Force
        $c | Add-Member -MemberType NoteProperty -Name 'HoverAnimStep' -Value 0 -Force
        # Direction: 1 = fade in, -1 = fade out
        $c | Add-Member -MemberType NoteProperty -Name 'HoverAnimDirection' -Value 0 -Force

        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = 15
        $c.HoverAnimTimer = $timer

        $timer.add_Tick({
            if (-not $global:ThemeCustomActive) {
                $c.HoverAnimTimer.Stop()
                return
            }

            $c.HoverAnimStep += $c.HoverAnimDirection
            if ($c.HoverAnimStep -ge 6) {
                $c.HoverAnimStep = 6
                $c.BackColor = $HoverColor
                $c.FlatAppearance.MouseOverBackColor = $HoverColor
                $c.HoverAnimTimer.Stop()
            }
            elseif ($c.HoverAnimStep -le 0) {
                $c.HoverAnimStep = 0
                $c.BackColor = $NormalColor
                $c.FlatAppearance.MouseOverBackColor = $NormalColor
                $c.HoverAnimTimer.Stop()
            }
            else {
                $pct = $c.HoverAnimStep / 6.0
                $r = [int]($NormalColor.R + ($HoverColor.R - $NormalColor.R) * $pct)
                $g = [int]($NormalColor.G + ($HoverColor.G - $NormalColor.G) * $pct)
                $b = [int]($NormalColor.B + ($HoverColor.B - $NormalColor.B) * $pct)
                $col = [System.Drawing.Color]::FromArgb($r, $g, $b)
                $c.BackColor = $col
                $c.FlatAppearance.MouseOverBackColor = $col
            }
        })

        $c.add_MouseEnter({
            if ($global:ThemeCustomActive -and $c.Enabled) {
                $c.HoverAnimDirection = 1
                $c.HoverAnimTimer.Start()
            }
        })

        $c.add_MouseLeave({
            if ($global:ThemeCustomActive -and $c.Enabled) {
                $c.HoverAnimDirection = -1
                $c.HoverAnimTimer.Start()
            }
        })
    }
}

function global:Save-OriginalStyles {
    param([System.Windows.Forms.Form]$Form)

    if ($null -eq $global:OriginalControlStyles) {
        $global:OriginalControlStyles = @{}
    }

    $formKey = $Form.GetHashCode()
    if (-not $global:OriginalControlStyles.ContainsKey($formKey)) {
        $global:OriginalControlStyles[$formKey] = @{
            BackColor = $Form.BackColor
            ForeColor = $Form.ForeColor
        }
    }

    function Walk-Save($ctrls) {
        foreach ($c in $ctrls) {
            # Guard against null or disposed controls in the tree
            if ($null -eq $c) { continue }
            try { if ($c.IsDisposed) { continue } } catch { continue }
            $ctrlKey = $c.GetHashCode()
            if ($null -eq $ctrlKey) { continue }
            if (-not $global:OriginalControlStyles.ContainsKey($ctrlKey)) {
                $styles = @{
                    BackColor = $c.BackColor
                    ForeColor = $c.ForeColor
                }
                if ($c.PSObject.Properties.Match('BorderStyle')) {
                    $styles['BorderStyle'] = $c.BorderStyle
                }
                if ($c.PSObject.Properties.Match('FlatStyle')) {
                    $styles['FlatStyle'] = $c.FlatStyle
                }
                if ($c -is [System.Windows.Forms.Button] -or $c -is [System.Windows.Forms.CheckBox] -or $c -is [System.Windows.Forms.RadioButton]) {
                    $styles['BorderColor'] = $c.FlatAppearance.BorderColor
                    $styles['BorderSize'] = $c.FlatAppearance.BorderSize
                    $styles['MouseOverBackColor'] = $c.FlatAppearance.MouseOverBackColor
                }
                $global:OriginalControlStyles[$ctrlKey] = $styles
            }
            if ($c.HasChildren) {
                Walk-Save $c.Controls
            }
        }
    }

    Walk-Save $Form.Controls
}

function global:Get-NextTheme {
    $current = "Normal"
    $cfgPath = Join-Path $env:APPDATA "SAMISH\config.json"
    if (Test-Path -LiteralPath $cfgPath) {
        try {
            $cfg = (Get-Content -LiteralPath $cfgPath -Raw) | ConvertFrom-Json
            if ($cfg -and $cfg.PSObject.Properties.Match('Theme').Count -gt 0) {
                $current = $cfg.Theme
            }
        } catch {}
    }
    
    $appDir = if ($global:PackageDir) { Join-Path $global:PackageDir "App" } else { "C:\Scripts\GOOGLE-ANTI-GRAVITY\SAMISH\App" }
    $hasCustom = Test-Path -LiteralPath (Join-Path $appDir "custom_theme.json")
    
    switch ($current) {
        "Normal" {
            if ($hasCustom) { return "Custom" } else { return "Neon" }
        }
        "Custom" {
            return "Neon"
        }
        "Neon" {
            return "Normal"
        }
        default {
            return "Normal"
        }
    }
}

function global:Invoke-BrandSequence {
    param([System.Windows.Forms.Form]$Form)

    if ($global:IsThemeAnimating) { return }
    $global:IsThemeAnimating = $true
    
    $targetTheme = Get-NextTheme
    $isReverting = ($targetTheme -eq "Normal")
    
    if (-not $global:ThemeCustomActive) {
        Save-OriginalStyles -Form $Form
    }
    
    if (-not (Test-Path -LiteralPath $global:ImgColorPath) -or -not (Test-Path -LiteralPath $global:ImgGrayPath)) {
        $global:IsThemeAnimating = $false
        return
    }

    $targetSize = 789

    # Load the logo image directly into a Drawing.Image - no PictureBox needed.
    # GDI+ DrawImage handles PNG transparency correctly in one pass.
    $imgPath = if ($isReverting) { $global:ImgGrayPath } else { $global:ImgColorPath }
    $logoImage = $null
    try { $logoImage = [System.Drawing.Image]::FromFile($imgPath) } catch {}

    Run-TakeoverAnimation -Form $Form -LogoImage $logoImage -TargetSize $targetSize -Reverting $isReverting -TargetTheme $targetTheme
}

function global:Run-TakeoverAnimation {
    param(
        [System.Windows.Forms.Form]$Form,
        [System.Drawing.Image]$LogoImage,
        [int]$TargetSize,
        [bool]$Reverting,
        [string]$TargetTheme
    )

    $PackageDir_Local = $global:PackageDir
    if (-not $PackageDir_Local) { $PackageDir_Local = $PackageDir }

    $FadeForm = New-Object System.Windows.Forms.Form
    $FadeForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $FadeForm.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $FadeForm.Location = $Form.PointToScreen((New-Object System.Drawing.Point(0, 0)))
    $FadeForm.Size = $Form.ClientSize
    $FadeForm.BackColor = $global:ThemeCustomBackground
    $FadeForm.Opacity = 0.0
    $FadeForm.ShowInTaskbar = $false

    # State shared by both the Paint event and the timer tick.
    # FadeForm.Tag holds it so the Paint handler reaches it via $sender.Tag.
    $animState = [PSCustomObject]@{
        Form              = $Form
        FadeForm          = $FadeForm
        LogoImage         = $LogoImage
        LogoSize          = 10
        FlashColor        = $global:ThemeCustomBackground
        TargetSize        = $TargetSize
        Reverting         = $Reverting
        TargetTheme       = $TargetTheme
        ScaleVelocity     = 1.0
        ScaleAcceleration = if ($Reverting) { 1.6 } else { 1.1 }
        StrobeFrames      = @()
        StrobeIndex       = 0
    }
    $FadeForm.Tag = $animState

    # Single GDI+ Paint pass: fill background color then draw logo on top.
    # Both happen in the same WM_PAINT - zero chance of mixed-state frames.
    $FadeForm.add_Paint({
            param($sender, $e)
            $s = $sender.Tag
            if ($null -eq $s) { return }
            $g = $e.Graphics
            $g.Clear($s.FlashColor)
            if ($null -ne $s.LogoImage -and $s.LogoSize -gt 0) {
                try {
                    $sz = [int]$s.LogoSize
                    $x = [int](($sender.Width - $sz) / 2)
                    $y = [int](($sender.Height - $sz) / 2)
                    $g.DrawImage($s.LogoImage, $x, $y, $sz, $sz)
                }
                catch {}
            }
        })

    $Form.Add_LocationChanged({
            if ($FadeForm -ne $null -and -not $FadeForm.IsDisposed) {
                $FadeForm.Location = $Form.PointToScreen((New-Object System.Drawing.Point(0, 0)))
            }
        })
    $Form.Add_SizeChanged({
            if ($FadeForm -ne $null -and -not $FadeForm.IsDisposed) {
                $FadeForm.Size = $Form.ClientSize
                $FadeForm.Location = $Form.PointToScreen((New-Object System.Drawing.Point(0, 0)))
                $FadeForm.Invalidate()
            }
        })

    $FadeForm.Show($Form)

    # Pre-generate randomized stroboscopic frames for "SAMISH"
    $strobeFrames = @()
    if (-not $Reverting) {
        $mode = Get-Random -Minimum 0 -Maximum 2
        if ($mode -eq 0) {
            # Morse Code: S(...) A(.-) M(--) I(..) S(...) H(....)
            $letters = @(
                @("dot", "dot", "dot"),       # S
                @("dot", "dash"),             # A
                @("dash", "dash"),            # M
                @("dot", "dot"),              # I
                @("dot", "dot", "dot"),       # S
                @("dot", "dot", "dot", "dot") # H
            )
            for ($i = 0; $i -lt $letters.Count; $i++) {
                $parts = $letters[$i]
                for ($j = 0; $j -lt $parts.Count; $j++) {
                    $p = $parts[$j]
                    if ($p -eq "dot") {
                        $strobeFrames += $global:ThemeCustomPrimary
                    }
                    else {
                        $strobeFrames += $global:ThemeCustomPrimary
                        $strobeFrames += $global:ThemeCustomPrimary
                        $strobeFrames += $global:ThemeCustomPrimary
                    }
                    if ($j -lt ($parts.Count - 1)) {
                        $strobeFrames += $global:ThemeCustomBackground
                    }
                }
                if ($i -lt ($letters.Count - 1)) {
                    $strobeFrames += $global:ThemeCustomBackground
                    $strobeFrames += $global:ThemeCustomBackground
                    $strobeFrames += $global:ThemeCustomBackground
                }
            }
            $strobeFrames += $global:ThemeCustomBackground
        }
        else {
            # Binary ASCII Stream for "SAMISH"
            $binStrings = @(
                "01010011", # S
                "01000001", # A
                "01001101", # M
                "01001001", # I
                "01010011", # S
                "01001000"  # H
            )
            foreach ($binStr in $binStrings) {
                for ($j = 0; $j -lt $binStr.Length; $j++) {
                    $bit = $binStr[$j]
                    if ($bit -eq '1') {
                        $strobeFrames += $global:ThemeCustomAlert
                    }
                    else {
                        $strobeFrames += $global:ThemeCustomBackground
                    }
                }
            }
            $strobeFrames += $global:ThemeCustomBackground
        }
    }
    $animState.StrobeFrames = $strobeFrames

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = if ($Reverting) { 15 } else { 20 }
    $timer.Tag = $animState

    $action = {
        param($sender, $e)
        try {
            $state = $sender.Tag

            if ($state.LogoSize -lt $state.TargetSize) {
                # === ZOOM phase: grow logo ===
                $state.ScaleVelocity += $state.ScaleAcceleration
                $newSz = $state.LogoSize + [int]$state.ScaleVelocity
                if ($newSz -gt $state.TargetSize) { $newSz = $state.TargetSize }
                $state.LogoSize = $newSz
                $state.FadeForm.Invalidate()
            }
            else {
                # === FADE-IN phase ===
                $newOp = $state.FadeForm.Opacity + 0.05
                if ($newOp -gt 1.0) { $newOp = 1.0 }
                $state.FadeForm.Opacity = $newOp

                if ($state.FadeForm.Opacity -ge 1.0) {
                    # === STROBE phase ===
                    if (-not $state.Reverting -and $state.StrobeFrames -and $state.StrobeIndex -lt $state.StrobeFrames.Count) {
                        $strobeColor = $state.StrobeFrames[$state.StrobeIndex]
                        $state.StrobeIndex++
                        $state.Form.BackColor = $strobeColor
                        $state.FlashColor = $strobeColor
                        # One Invalidate() -> one Paint pass -> background + logo drawn together atomically.
                        $state.FadeForm.Invalidate()
                        return
                    }

                    $sender.Stop()

                    if (-not (Get-Command Set-BrandTheme -ErrorAction SilentlyContinue)) {
                        . (Join-Path $PackageDir_Local "Modules\Theme-Extension.ps1")
                    }

                    try {
                        if ($state.TargetTheme -eq "Normal") {
                            Set-BrandTheme -Form $state.Form -IsCustom $false
                        }
                        else {
                            if ($state.TargetTheme -eq "Custom") {
                                Load-CustomThemeColors
                            } else {
                                Load-NeonThemeColors
                            }
                            Set-BrandTheme -Form $state.Form -IsCustom $true
                        }
                    }
                    catch {
                        Out-File -FilePath "C:\Scripts\GOOGLE-ANTI-GRAVITY\SAMISH\SAMISH_ERROR.txt" -InputObject "Set-BrandTheme Error: $($_.Exception.ToString())" -Append
                    }

                    $global:OriginalTops.Clear()
                    foreach ($ctrl in $state.Form.Controls) {
                        if ($null -eq $ctrl) { continue }
                        try { if ($ctrl.IsDisposed) { continue } } catch { continue }
                        $global:OriginalTops[$ctrl.Handle] = $ctrl.Top
                        if (-not $state.Reverting) {
                            $ctrl.Top -= 220
                        }
                    }

                    # Dispose the logo image now that we're done with the overlay
                    try {
                        if ($state.LogoImage) {
                            $state.LogoImage.Dispose()
                            $state.LogoImage = $null
                        }
                    }
                    catch {}

                    Run-DropAnimation -Form $state.Form -FadeForm $state.FadeForm -Reverting $state.Reverting
                }
            }
        }
        catch {
            Out-File -FilePath "C:\Scripts\GOOGLE-ANTI-GRAVITY\SAMISH\SAMISH_ERROR.txt" -InputObject "Takeover Error: $($_.Exception.ToString())" -Append
            try { $sender.Stop() } catch {}
            try { if ($state -and $state.FadeForm -and -not $state.FadeForm.IsDisposed) { $state.FadeForm.Close(); $state.FadeForm.Dispose() } } catch {}
            try {
                if ($state -and $state.LogoImage) {
                    $state.LogoImage.Dispose()
                    $state.LogoImage = $null
                }
            }
            catch {}
            $global:IsThemeAnimating = $false
        }
    }

    $timer.add_Tick($action)
    $timer.Start()
}

function global:Run-DropAnimation {
    param(
        [System.Windows.Forms.Form]$Form,
        [System.Windows.Forms.Form]$FadeForm,
        [bool]$Reverting
    )

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = if ($Reverting) { 15 } else { 20 }
    $timer.Tag = [PSCustomObject]@{
        Form          = $Form
        FadeForm      = $FadeForm
        Reverting     = $Reverting
        TickCount     = 0
        ControlStates = @{}
    }

    $action = {
        param($sender, $e)
        try {
            $state = $sender.Tag
            $state.TickCount++

            if ($state.FadeForm.Opacity -gt 0.0) {
                $newOp = $state.FadeForm.Opacity - 0.05
                if ($newOp -lt 0.0) { $newOp = 0.0 }
                $state.FadeForm.Opacity = $newOp
            }

            $allDropped = $true
            if (-not $state.Reverting) {
                # Cascaded physics gravity drop with elastic rebound (Neon Mode only)
                foreach ($ctrl in $state.Form.Controls) {
                    $ctrlKey = $ctrl.Handle
                    $targetTop = $global:OriginalTops[$ctrlKey]
                    if ($null -eq $targetTop) { continue }
                    
                    if (-not $state.ControlStates.ContainsKey($ctrlKey)) {
                        $state.ControlStates[$ctrlKey] = [PSCustomObject]@{
                            Velocity = 0.0
                            Bounces  = 0
                            Delay    = [int]($targetTop / 25)
                        }
                    }
                    
                    $ctrlState = $state.ControlStates[$ctrlKey]
                    if ($state.TickCount -lt $ctrlState.Delay) {
                        $allDropped = $false
                        continue
                    }
                    
                    if ($ctrl.Top -lt $targetTop -or $ctrlState.Bounces -lt 2) {
                        $allDropped = $false
                        $ctrlState.Velocity += 1.6 # Gravity
                        $nextTop = $ctrl.Top + $ctrlState.Velocity
                        
                        if ($nextTop -ge $targetTop) {
                            if ($ctrlState.Bounces -lt 1) {
                                $ctrlState.Velocity = - ($ctrlState.Velocity * 0.45) # Bounce back up with 45% velocity
                                $ctrl.Top = $targetTop
                                $ctrlState.Bounces++
                            }
                            else {
                                $ctrl.Top = $targetTop
                                $ctrlState.Velocity = 0.0
                                $ctrlState.Bounces = 2 # Settle
                            }
                        }
                        else {
                            $ctrl.Top = $nextTop
                        }
                    }
                }
            }
            else {
                # Normal mode reversion: instant restore, already in position
                $allDropped = $true
            }

            if ($state.FadeForm.Opacity -le 0.0 -and $allDropped) {
                $sender.Stop()
                $state.FadeForm.Close()
                $state.FadeForm.Dispose()
                
                if ($state.TargetTheme -eq "Normal") {
                    $global:ThemeCustomActive = $false
                    $global:OriginalControlStyles.Clear()
                    if (Get-Command Save-ThemePreference -ErrorAction SilentlyContinue) { Save-ThemePreference -ThemeName "Normal" }
                }
                else {
                    $global:ThemeCustomActive = $true
                    if (Get-Command Save-ThemePreference -ErrorAction SilentlyContinue) { Save-ThemePreference -ThemeName $state.TargetTheme }
                }
                $global:IsThemeAnimating = $false
            }
        }
        catch {
            Out-File -FilePath "C:\Scripts\GOOGLE-ANTI-GRAVITY\SAMISH\SAMISH_ERROR.txt" -InputObject "Drop Error: $($_.Exception.ToString())" -Append
        }
    }
    
    $timer.add_Tick($action)
    $timer.Start()
}

function global:Set-BrandTheme {
    param(
        [System.Windows.Forms.Form]$Form,
        [bool]$IsCustom
    )

    $global:ThemeCustomActive = $IsCustom

    # Pre-define CheckBox and RadioButton custom paint handlers for high-contrast neon styling
    $checkboxPaintBlock = {
        param($sender, $e)
        if (-not $global:ThemeCustomActive) { return }
        $g = $e.Graphics
        
        $boxBgColor = $global:ThemeCustomCheckboxBg
        if ($null -eq $boxBgColor) { $boxBgColor = [System.Drawing.Color]::FromArgb(25, 25, 30) }
        
        $borderColor = $global:ThemeCustomCheckboxBorder
        if ($null -eq $borderColor) { $borderColor = $global:ThemeCustomSecondary }
        
        $checkColor = $global:ThemeCustomCheckboxCheck
        if ($null -eq $checkColor) { $checkColor = $global:ThemeCustomPrimary }
        
        if ($sender.Name -eq "chkUiMode") {
            $borderColor = $global:ThemeCustomAlert
            $checkColor = $global:ThemeCustomPrimary
        }
        
        $boxSize = 14
        $boxX = 0
        $boxY = [int](($sender.Height - $boxSize) / 2)
        
        $brush = [System.Drawing.SolidBrush]::new($boxBgColor)
        $g.FillRectangle($brush, $boxX, $boxY, $boxSize, $boxSize)
        $brush.Dispose()
        
        $pen = [System.Drawing.Pen]::new($borderColor, 1)
        $g.DrawRectangle($pen, $boxX, $boxY, $boxSize, $boxSize)
        $pen.Dispose()
        
        if ($sender.Checked) {
            $checkPen = [System.Drawing.Pen]::new($checkColor, 2)
            $p1 = New-Object System.Drawing.Point(($boxX + 3), ($boxY + 7))
            $p2 = New-Object System.Drawing.Point(($boxX + 6), ($boxY + 10))
            $p3 = New-Object System.Drawing.Point(($boxX + 11), ($boxY + 4))
            
            $g.DrawLine($checkPen, $p1, $p2)
            $g.DrawLine($checkPen, $p2, $p3)
            $checkPen.Dispose()
        }
    }.GetNewClosure()

    $radioPaintBlock = {
        param($sender, $e)
        if (-not $global:ThemeCustomActive) { return }
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        
        $boxBgColor = $global:ThemeCustomCheckboxBg
        if ($null -eq $boxBgColor) { $boxBgColor = [System.Drawing.Color]::FromArgb(25, 25, 30) }
        
        $borderColor = $global:ThemeCustomCheckboxBorder
        if ($null -eq $borderColor) { $borderColor = $global:ThemeCustomSecondary }
        
        $dotColor = $global:ThemeCustomCheckboxCheck
        if ($null -eq $dotColor) { $dotColor = $global:ThemeCustomPrimary }
        
        $circleSize = 14
        $circleX = 0
        $circleY = [int](($sender.Height - $circleSize) / 2)
        
        $brush = [System.Drawing.SolidBrush]::new($boxBgColor)
        $g.FillEllipse($brush, $circleX, $circleY, $circleSize, $circleSize)
        $brush.Dispose()
        
        $pen = [System.Drawing.Pen]::new($borderColor, 1)
        $g.DrawEllipse($pen, $circleX, $circleY, $circleSize, $circleSize)
        $pen.Dispose()
        
        if ($sender.Checked) {
            $dotBrush = [System.Drawing.SolidBrush]::new($dotColor)
            $dotSize = 6
            $dotX = $circleX + [int](($circleSize - $dotSize) / 2)
            $dotY = $circleY + [int](($circleSize - $dotSize) / 2)
            $g.FillEllipse($dotBrush, $dotX, $dotY, $dotSize, $dotSize)
            $dotBrush.Dispose()
        }
    }.GetNewClosure()

    # Save original styles first
    $formKey = $Form.GetHashCode()
    Save-OriginalStyles -Form $Form

    if ($IsCustom) {
        $Form.BackColor = $global:ThemeCustomBackground
    }
    else {
        if ($global:OriginalControlStyles.ContainsKey($formKey)) {
            $Form.BackColor = $global:OriginalControlStyles[$formKey]['BackColor']
            $Form.ForeColor = $global:OriginalControlStyles[$formKey]['ForeColor']
        }
        else {
            $Form.BackColor = [System.Drawing.SystemColors]::Control
        }
    }

    function Walk-Controls($ctrls) {
        foreach ($c in $ctrls) {
            # Guard against null or disposed controls
            if ($null -eq $c) { continue }
            try { if ($c.IsDisposed) { continue } } catch { continue }
            $ctrlKey = $c.GetHashCode()
            if ($null -eq $ctrlKey) { continue }
            if ($IsCustom) {
                if ($c -is [System.Windows.Forms.PictureBox] -and $c.Name -eq "logo") {
                    $c.ImageLocation = $global:ImgColorPath
                }
                elseif ($c -is [System.Windows.Forms.Button]) {
                    $c.BackColor = $global:ThemeCustomButton
                    if ($c.Tag -eq 'VisuallyDisabled' -or $c.Tag -eq 'SimpleRestoreDisabled') {
                        $c.ForeColor = $global:ThemeCustomDisabledText
                    }
                    else {
                        $c.ForeColor = $global:ThemeCustomPrimary
                    }
                    $c.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
                    $c.FlatAppearance.BorderColor = $global:ThemeCustomSecondary
                    $c.FlatAppearance.MouseOverBackColor = $global:ThemeCustomButtonHover
                    # Preserve BorderSize=0 for tab-style buttons so border color is set but invisible
                    if ($c.Name -match '^btnDrawer2Tab|^btnSubTab|^btnTab') {
                        $c.FlatAppearance.BorderSize = 0
                    }
                    Register-HoverFadeAnimation -c $c -NormalColor $global:ThemeCustomButton -HoverColor $global:ThemeCustomButtonHover
                }
                elseif ($c.Name -match "^mainSep$|^subSep$|^telemetrySubSep$|^drawer2TabSep$") {
                    $c.BackColor = $global:ThemeCustomPrimary
                }
                elseif ($c.Name -match "Indicator|advancedTabIndicator|Sep") {
                    $c.BackColor = $global:ThemeCustomSecondary
                }
                elseif ($c -is [System.Windows.Forms.GroupBox]) {
                    $c.ForeColor = $global:ThemeCustomAlert
                    if ($c.PSObject.Properties.Match('OriginalText').Count -eq 0) {
                        $c | Add-Member -MemberType NoteProperty -Name 'OriginalText' -Value $c.Text
                    }
                    $c.Text = ""
                    if ($c.PSObject.Properties.Match('ThemeHooked').Count -eq 0) {
                        $c | Add-Member -MemberType NoteProperty -Name 'ThemeHooked' -Value $true
                        $c.add_Paint({
                                param($sender, $e)
                                if ($global:ThemeCustomActive) {
                                    $g = $e.Graphics
                                    $pen = New-Object System.Drawing.Pen($global:ThemeCustomDisabled, 1)
                                    $gbW = [int]$sender.Width
                                    $gbH = [int]$sender.Height
                                    
                                    # Draw border rectangle
                                    $rect = New-Object System.Drawing.Rectangle(0, 7, ($gbW - 1), ($gbH - 8))
                                    $g.DrawRectangle($pen, $rect)
                                    $pen.Dispose()
                                    
                                    # Mask and draw text
                                    if ($sender.PSObject.Properties.Match('OriginalText').Count -gt 0 -and $sender.OriginalText) {
                                        $origText = $sender.OriginalText
                                        $font = $sender.Font
                                        $textSize = $g.MeasureString($origText, $font)
                                        $textW = [int]($textSize.Width)
                                        
                                        $bg = Get-ParentSolidBackColor -c $sender
                                        $bgBrush = New-Object System.Drawing.SolidBrush($bg)
                                        $g.FillRectangle($bgBrush, 8, 0, $textW, 14)
                                        $bgBrush.Dispose()
                                        
                                        $textBrush = New-Object System.Drawing.SolidBrush($sender.ForeColor)
                                        $g.DrawString($origText, $font, $textBrush, 8, 0)
                                        $textBrush.Dispose()
                                    }
                                }
                            })
                    }
                }
                elseif ($c -is [System.Windows.Forms.Label]) {
                    if ($c.Text -eq "SAMISH") {
                        $c.ForeColor = $global:ThemeCustomAlert
                    }
                    elseif ($c.Name -eq "subtitle") {
                        $c.ForeColor = $global:ThemeCustomPrimary
                    }
                    elseif ($c.Name -eq "bottomMetadata") {
                        $c.ForeColor = $global:ThemeCustomAlert
                    }
                    elseif ($c.Name -eq "lblWakeApp") {
                        # let Set-OperatingModeBoxState handle it
                    }
                    else {
                        $c.ForeColor = $global:ThemeCustomText
                    }
                    $c.BackColor = [System.Drawing.Color]::Transparent
                }
                elseif ($c -is [System.Windows.Forms.CheckBox] -or $c -is [System.Windows.Forms.RadioButton]) {
                    $c.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
                    $c.FlatAppearance.BorderColor = $global:ThemeCustomCheckboxBorder
                    $c.FlatAppearance.MouseOverBackColor = $global:ThemeCustomButtonHover
                    $c.FlatAppearance.MouseDownBackColor = $global:ThemeCustomButton
                    $c.BackColor = [System.Drawing.Color]::Transparent
                    
                    if ($c.PSObject.Properties.Match('ThemeHooked').Count -eq 0) {
                        $c | Add-Member -MemberType NoteProperty -Name 'ThemeHooked' -Value $true
                        if ($c -is [System.Windows.Forms.CheckBox]) {
                            $c.add_Paint($checkboxPaintBlock)
                        } else {
                            $c.add_Paint($radioPaintBlock)
                        }
                        
                        $c.add_EnabledChanged({
                            param($sender, $e)
                            if ($global:ThemeCustomActive) {
                                if (-not $sender.Enabled) {
                                    $sender.ForeColor = $global:ThemeCustomDisabledText
                                } else {
                                    if ($sender.Name -eq "chkUiMode") {
                                        $sender.ForeColor = $global:ThemeCustomDisabledText
                                    } else {
                                        $sender.ForeColor = $global:ThemeCustomText
                                    }
                                }
                            }
                        })
                    }
                    
                    # Add leading spaces for GDI+ flat style padding if not already present
                    if ($c.Text -and -not $c.Text.StartsWith("  ")) {
                        $c.Text = "  " + $c.Text.TrimStart()
                    }
                    
                    if ($c.Name -eq "chkOverrideMonitor") {
                        # let Set-OperatingModeBoxState handle it
                    }
                    else {
                        if (-not $c.Enabled) {
                            $c.ForeColor = $global:ThemeCustomDisabledText
                        } else {
                            if ($c.Name -eq "chkUiMode") {
                                $c.ForeColor = $global:ThemeCustomDisabledText
                                $c.FlatAppearance.BorderColor = $global:ThemeCustomAlert
                            } else {
                                $c.ForeColor = $global:ThemeCustomText
                            }
                        }
                    }
                }
                elseif ($c -is [System.Windows.Forms.TextBox]) {
                    $c.BackColor = $global:ThemeCustomInput
                    $c.ForeColor = $global:ThemeCustomPrimary
                    $c.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
                }
                elseif ($c -is [System.Windows.Forms.ComboBox]) {
                    $c.BackColor = if ($c.Enabled) { $global:ThemeCustomInput } else { $global:ThemeCustomDisabled }
                    $c.ForeColor = if ($c.Enabled) { $global:ThemeCustomPrimary } else { $global:ThemeCustomDisabledText }
                    $c.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
                    
                    if ($c.PSObject.Properties.Match('ThemeHooked').Count -eq 0) {
                        $c | Add-Member -MemberType NoteProperty -Name 'ThemeHooked' -Value $true
                        $c.add_EnabledChanged({
                                param($sender, $e)
                                if ($global:ThemeCustomActive) {
                                    $sender.BackColor = if ($sender.Enabled) { $global:ThemeCustomInput } else { $global:ThemeCustomDisabled }
                                    $sender.ForeColor = if ($sender.Enabled) { $global:ThemeCustomPrimary } else { $global:ThemeCustomDisabledText }
                                }
                            })
                    }
                }
                elseif ($c -is [System.Windows.Forms.ListBox]) {
                    $c.BackColor = $global:ThemeCustomPanel
                    $c.ForeColor = $global:ThemeCustomText
                    $c.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
                }
                elseif ($c -is [System.Windows.Forms.TabControl] -or $c -is [System.Windows.Forms.TabPage] -or $c -is [System.Windows.Forms.Panel]) {
                    if ($c.Name -eq "pnlOnWakeBorder") {
                        # let Set-OperatingModeBoxState handle it
                    }
                    else {
                        $c.BackColor = $global:ThemeCustomBackground
                        $c.ForeColor = $global:ThemeCustomText
                    }
                }
            }
            else {
                # Revert theme
                if ($global:OriginalControlStyles.ContainsKey($ctrlKey)) {
                    $styles = $global:OriginalControlStyles[$ctrlKey]
                    if ($c -is [System.Windows.Forms.ListBox] -or $c -is [System.Windows.Forms.TextBox] -or $c -is [System.Windows.Forms.Button] -or $c -is [System.Windows.Forms.ComboBox] -or $c -is [System.Windows.Forms.Panel] -or $c -is [System.Windows.Forms.TabControl] -or $c -is [System.Windows.Forms.TabPage] -or $c.Name -match "Indicator|Sep|mainSep|subSep") {
                        try { $c.BackColor = $styles['BackColor'] } catch { $c.ResetBackColor() }
                        
                        # Fallback overrides for items whose original state may have been lost if custom theme was active on startup
                        if ($c -is [System.Windows.Forms.Panel] -and $c.Name -match "^pnl") {
                            $c.BackColor = [System.Drawing.Color]::Transparent
                        }
                        elseif ($c -is [System.Windows.Forms.ListBox] -and ($c.Name -eq "listArmedDevices" -or $c.Name -eq "listHardwareScans")) {
                            $c.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 250)
                        }
                    }
                    else {
                        try { $c.ResetBackColor() } catch {}
                    }
                    
                    if ($c -is [System.Windows.Forms.GroupBox]) {
                        $c.ForeColor = [System.Drawing.SystemColors]::ControlText
                        if ($c.PSObject.Properties.Match('OriginalText').Count -gt 0) {
                            $c.Text = $c.OriginalText
                        }
                    }
                    elseif ($c -is [System.Windows.Forms.Button] -and $c.Name -match "^btnDiag") {
                        if ($c.Tag -eq "VisuallyDisabled") {
                            $c.ForeColor = [System.Drawing.SystemColors]::GrayText
                        }
                        else {
                            $c.ForeColor = [System.Drawing.SystemColors]::ControlText
                        }
                    }
                    else {
                        try { $c.ForeColor = $styles['ForeColor'] } catch { $c.ResetForeColor() }
                    }
                    if ($styles.ContainsKey('BorderStyle')) {
                        try { $c.BorderStyle = $styles['BorderStyle'] } catch {}
                    }
                    if ($styles.ContainsKey('FlatStyle')) {
                        try { $c.FlatStyle = $styles['FlatStyle'] } catch {}
                    }
                    if ($c -is [System.Windows.Forms.Button] -or $c -is [System.Windows.Forms.CheckBox] -or $c -is [System.Windows.Forms.RadioButton]) {
                        if ($c -is [System.Windows.Forms.CheckBox] -or $c -is [System.Windows.Forms.RadioButton]) {
                            # Revert GDI+ flat style padding
                            if ($c.Text -and $c.Text.StartsWith("  ")) {
                                $c.Text = $c.Text.Substring(2)
                            }
                        }
                        if ($c.Name -match "^btnDiag|^btnTest|^btnTelemetry") {
                            $c.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
                            $c.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
                        }
                        else {
                            if ($styles.ContainsKey('BorderColor')) {
                                $c.FlatAppearance.BorderColor = $styles['BorderColor']
                            }
                            if ($styles.ContainsKey('MouseOverBackColor')) {
                                $c.FlatAppearance.MouseOverBackColor = $styles['MouseOverBackColor']
                            }
                        }
                        if ($c.Name -match '^btnDrawer2Tab|^btnSubTab|^btnTab') {
                            $c.FlatAppearance.BorderSize = 0
                            $c.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
                        }
                        elseif ($styles.ContainsKey('BorderSize')) {
                            $c.FlatAppearance.BorderSize = $styles['BorderSize']
                        }
                    }
                }
                else {
                    $c.ResetBackColor()
                    $c.ResetForeColor()
                }
                
                if ($c -is [System.Windows.Forms.PictureBox] -and $c.Name -eq "logo") {
                    $c.ImageLocation = $global:ImgColorPath
                }
            }

            try { $c.Invalidate() } catch {}

            if ($c.HasChildren) {
                Walk-Controls $c.Controls
            }
        }
    }

    Walk-Controls -ctrls $Form.Controls

    # Restore z-order for the version label so its double-click handler remains reachable
    if ($script:bottomMetadata) { $script:bottomMetadata.BringToFront() }

    # Sync active tab / secondary tab colors
    if (Get-Command Update-TabIndicator -ErrorAction SilentlyContinue) {
        try { Update-TabIndicator } catch {}
    }
    if (Get-Command Update-SecondaryTabStyles -ErrorAction SilentlyContinue) {
        try { Update-SecondaryTabStyles } catch {}
    }
    # Ensure current state of Operating Mode box is rendered with correct colors for active theme
    if (Get-Command Set-OperatingModeBoxState -ErrorAction SilentlyContinue) {
        try {
            $isBoxEnabled = $true
            if ($script:listAutomated) {
                $isBoxEnabled = ($script:listAutomated.SelectedIndex -ge 0 -and $script:listAutomated.SelectedIndex -lt $script:MonitoredApps.Count)
            }
            Set-OperatingModeBoxState -Enabled $isBoxEnabled
        }
        catch {}
    }
    # Ensure current state of Operating Mode Tests box is rendered with correct colors for active theme
    if (Get-Command Update-TestGroupState -ErrorAction SilentlyContinue) {
        try { Update-TestGroupState } catch {}
    }
}

function global:Save-ThemePreference {
    param([string]$ThemeName)
    try {
        $cfgPath = $null
        if ($global:PackageDir) {
            $cfgPath = Join-Path $env:APPDATA "SAMISH\config.json"
        }
        else {
            $cfgPath = Join-Path $env:APPDATA "SAMISH\config.json"
        }
        
        $cfg = @{}
        if (Test-Path -LiteralPath $cfgPath) {
            try { $cfg = (Get-Content -LiteralPath $cfgPath -Raw) | ConvertFrom-Json } catch { $cfg = @{} }
        }
        else {
            $dir = Split-Path -Parent $cfgPath
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        }
        
        $cfg | Add-Member -MemberType NoteProperty -Name "Theme" -Value $ThemeName -Force
        
        $json = $cfg | ConvertTo-Json -Depth 6
        Set-Content -LiteralPath $cfgPath -Value $json -Encoding UTF8
    }
    catch {}
}

# Convenience wrapper for modal dialogs and dynamically spawned forms.
# Automatically applies the currently active theme (Normal or Neon)
# to any Form passed in.
function global:Apply-SamishTheme {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Form]$Form
    )

    if ($global:ThemeCustomActive) {
        Set-BrandTheme -Form $Form -IsCustom $true
    }
}
