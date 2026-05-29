# SAMISH Stealth Theme Extension Module
# Handles the "Anti-Gravity Cyberpunk" Sequence

# Global state to prevent overlapping triggers
if ($null -eq $global:ThemeNeonActive) { $global:ThemeNeonActive = $false }
if ($null -eq $global:IsThemeAnimating) { $global:IsThemeAnimating = $false }
if ($null -eq $global:OriginalTops) { $global:OriginalTops = @{} }
if ($null -eq $global:OriginalControlStyles) {
    $global:OriginalControlStyles = @{}
}

if ($null -eq $global:PackageDir) {
    if ($PackageDir) {
        $global:PackageDir = $PackageDir
    } elseif ($PSScriptRoot) {
        $global:PackageDir = Split-Path -Parent $PSScriptRoot
    } else {
        $global:PackageDir = "C:\Scripts\GOOGLE-ANTI-GRAVITY\SAMISH"
    }
}

$global:ImgColorPath = Join-Path $global:PackageDir "Assets\SAMISH-SQUARE-STYLIZED.png"
$global:ImgGrayPath = Join-Path $global:PackageDir "Assets\SAMISH-SQUARE-GREYSCALE-STYLIZED3.png"

# Neon Palette - MUST BE GLOBAL to survive dot-sourcing inside a scriptblock
$global:NeonBackground = [System.Drawing.Color]::FromArgb(15, 15, 18)    # #0F0F12
$global:NeonPurple     = [System.Drawing.Color]::FromArgb(153, 51, 255)   # From stylized logo
$global:NeonPink       = [System.Drawing.Color]::FromArgb(255, 0, 102)    # #FF0066
$global:NeonLime       = [System.Drawing.Color]::FromArgb(179, 255, 0)    # #b3ff00
$global:NeonCyan       = [System.Drawing.Color]::FromArgb(0, 245, 212)    # #00f5d4
$global:NeonText       = [System.Drawing.Color]::FromArgb(255, 255, 255)  # #FFFFFF

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
                if ($c -is [System.Windows.Forms.Button]) {
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

function global:Invoke-BrandSequence {
    param([System.Windows.Forms.Form]$Form)

    if ($global:IsThemeAnimating) { return }
    $global:IsThemeAnimating = $true
    
    if (-not $global:ThemeNeonActive) {
        Save-OriginalStyles -Form $Form
    }
    
    if (-not (Test-Path -LiteralPath $global:ImgColorPath) -or -not (Test-Path -LiteralPath $global:ImgGrayPath)) {
        $global:IsThemeAnimating = $false
        return
    }

    $targetSize = 789

    # Load the logo image directly into a Drawing.Image - no PictureBox needed.
    # GDI+ DrawImage handles PNG transparency correctly in one pass.
    $imgPath = if ($global:ThemeNeonActive) { $global:ImgGrayPath } else { $global:ImgColorPath }
    $logoImage = $null
    try { $logoImage = [System.Drawing.Image]::FromFile($imgPath) } catch {}

    Run-TakeoverAnimation -Form $Form -LogoImage $logoImage -TargetSize $targetSize -Reverting $global:ThemeNeonActive
}

function global:Run-TakeoverAnimation {
    param(
        [System.Windows.Forms.Form]$Form,
        [System.Drawing.Image]$LogoImage,
        [int]$TargetSize,
        [bool]$Reverting
    )

    $PackageDir_Local = $global:PackageDir
    if (-not $PackageDir_Local) { $PackageDir_Local = $PackageDir }

    $FadeForm = New-Object System.Windows.Forms.Form
    $FadeForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $FadeForm.StartPosition   = [System.Windows.Forms.FormStartPosition]::Manual
    $FadeForm.Location        = $Form.PointToScreen((New-Object System.Drawing.Point(0,0)))
    $FadeForm.Size            = $Form.ClientSize
    $FadeForm.BackColor       = $global:NeonBackground
    $FadeForm.Opacity         = 0.0
    $FadeForm.ShowInTaskbar   = $false

    # State shared by both the Paint event and the timer tick.
    # FadeForm.Tag holds it so the Paint handler reaches it via $sender.Tag.
    $animState = [PSCustomObject]@{
        Form             = $Form
        FadeForm         = $FadeForm
        LogoImage        = $LogoImage
        LogoSize         = 10
        FlashColor       = $global:NeonBackground
        TargetSize       = $TargetSize
        Reverting        = $Reverting
        ScaleVelocity    = 1.0
        ScaleAcceleration = if ($Reverting) { 1.6 } else { 1.1 }
        StrobeFrames     = @()
        StrobeIndex      = 0
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
                $x  = [int](($sender.Width  - $sz) / 2)
                $y  = [int](($sender.Height - $sz) / 2)
                $g.DrawImage($s.LogoImage, $x, $y, $sz, $sz)
            } catch {}
        }
    })

    $Form.Add_LocationChanged({
        if ($FadeForm -ne $null -and -not $FadeForm.IsDisposed) {
            $FadeForm.Location = $Form.PointToScreen((New-Object System.Drawing.Point(0,0)))
        }
    })
    $Form.Add_SizeChanged({
        if ($FadeForm -ne $null -and -not $FadeForm.IsDisposed) {
            $FadeForm.Size     = $Form.ClientSize
            $FadeForm.Location = $Form.PointToScreen((New-Object System.Drawing.Point(0,0)))
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
                        $strobeFrames += $global:NeonCyan
                    } else {
                        $strobeFrames += $global:NeonCyan
                        $strobeFrames += $global:NeonCyan
                        $strobeFrames += $global:NeonCyan
                    }
                    if ($j -lt ($parts.Count - 1)) {
                        $strobeFrames += $global:NeonBackground
                    }
                }
                if ($i -lt ($letters.Count - 1)) {
                    $strobeFrames += $global:NeonBackground
                    $strobeFrames += $global:NeonBackground
                    $strobeFrames += $global:NeonBackground
                }
            }
            $strobeFrames += $global:NeonBackground
        } else {
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
                        $strobeFrames += $global:NeonPink
                    } else {
                        $strobeFrames += $global:NeonBackground
                    }
                }
            }
            $strobeFrames += $global:NeonBackground
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
            } else {
                # === FADE-IN phase ===
                $newOp = $state.FadeForm.Opacity + 0.05
                if ($newOp -gt 1.0) { $newOp = 1.0 }
                $state.FadeForm.Opacity = $newOp

                if ($state.FadeForm.Opacity -ge 1.0) {
                    # === STROBE phase ===
                    if (-not $state.Reverting -and $state.StrobeFrames -and $state.StrobeIndex -lt $state.StrobeFrames.Count) {
                        $strobeColor = $state.StrobeFrames[$state.StrobeIndex]
                        $state.StrobeIndex++
                        $state.Form.BackColor    = $strobeColor
                        $state.FlashColor        = $strobeColor
                        # One Invalidate() → one Paint pass → background + logo drawn together atomically.
                        $state.FadeForm.Invalidate()
                        return
                    }

                    $sender.Stop()

                    if (-not (Get-Command Set-BrandTheme -ErrorAction SilentlyContinue)) {
                        . (Join-Path $PackageDir_Local "Modules\Theme-Extension.ps1")
                    }

                    try {
                        if ($state.Reverting) {
                            Set-BrandTheme -Form $state.Form -IsNeon $false
                        } else {
                            Set-BrandTheme -Form $state.Form -IsNeon $true
                        }
                    } catch {
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
                    } catch {}

                    Run-DropAnimation -Form $state.Form -FadeForm $state.FadeForm -Reverting $state.Reverting
                }
            }
        } catch {
            Out-File -FilePath "C:\Scripts\GOOGLE-ANTI-GRAVITY\SAMISH\SAMISH_ERROR.txt" -InputObject "Takeover Error: $($_.Exception.ToString())" -Append
            try { $sender.Stop() } catch {}
            try { if ($state -and $state.FadeForm -and -not $state.FadeForm.IsDisposed) { $state.FadeForm.Close(); $state.FadeForm.Dispose() } } catch {}
            try {
                if ($state -and $state.LogoImage) {
                    $state.LogoImage.Dispose()
                    $state.LogoImage = $null
                }
            } catch {}
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
        Form = $Form
        FadeForm = $FadeForm
        Reverting = $Reverting
        TickCount = 0
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
                            Bounces = 0
                            Delay = [int]($targetTop / 25)
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
                                $ctrlState.Velocity = -($ctrlState.Velocity * 0.45) # Bounce back up with 45% velocity
                                $ctrl.Top = $targetTop
                                $ctrlState.Bounces++
                            } else {
                                $ctrl.Top = $targetTop
                                $ctrlState.Velocity = 0.0
                                $ctrlState.Bounces = 2 # Settle
                            }
                        } else {
                            $ctrl.Top = $nextTop
                        }
                    }
                }
            } else {
                # Normal mode reversion: instant restore, already in position
                $allDropped = $true
            }

            if ($state.FadeForm.Opacity -le 0.0 -and $allDropped) {
                $sender.Stop()
                $state.FadeForm.Close()
                $state.FadeForm.Dispose()
                
                if ($state.Reverting) {
                    $global:ThemeNeonActive = $false
                    $global:OriginalControlStyles.Clear()
                    if (Get-Command Save-ThemePreference -ErrorAction SilentlyContinue) { Save-ThemePreference -IsNeon $false }
                } else {
                    $global:ThemeNeonActive = $true
                    if (Get-Command Save-ThemePreference -ErrorAction SilentlyContinue) { Save-ThemePreference -IsNeon $true }
                }
                $global:IsThemeAnimating = $false
            }
        } catch {
            Out-File -FilePath "C:\Scripts\GOOGLE-ANTI-GRAVITY\SAMISH\SAMISH_ERROR.txt" -InputObject "Drop Error: $($_.Exception.ToString())" -Append
        }
    }
    
    $timer.add_Tick($action)
    $timer.Start()
}

function global:Set-BrandTheme {
    param(
        [System.Windows.Forms.Form]$Form,
        [bool]$IsNeon
    )

    $global:ThemeNeonActive = $IsNeon

    # Save original styles first
    $formKey = $Form.GetHashCode()
    Save-OriginalStyles -Form $Form

    if ($IsNeon) {
        $Form.BackColor = $global:NeonBackground
    } else {
        if ($global:OriginalControlStyles.ContainsKey($formKey)) {
            $Form.BackColor = $global:OriginalControlStyles[$formKey]['BackColor']
            $Form.ForeColor = $global:OriginalControlStyles[$formKey]['ForeColor']
        } else {
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
            if ($IsNeon) {
                if ($c -is [System.Windows.Forms.PictureBox] -and $c.Name -eq "logo") {
                    $c.ImageLocation = $global:ImgGrayPath
                }
                elseif ($c -is [System.Windows.Forms.Button]) {
                    $c.BackColor = [System.Drawing.Color]::FromArgb(35, 35, 40)
                    $c.ForeColor = $global:NeonCyan
                    $c.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
                    $c.FlatAppearance.BorderColor = $global:NeonPurple
                    $c.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(50, 50, 60)
                    
                    if ($c.PSObject.Properties.Match('ThemeHooked').Count -eq 0) {
                        $c | Add-Member -MemberType NoteProperty -Name 'ThemeHooked' -Value $true
                        $c.add_EnabledChanged({
                            param($sender, $e)
                            if ($global:ThemeNeonActive) {
                                if ($sender.Name -match "btnTelemetryTabTimers|btnTelemetryTabArmed|btnSubTabTools|btnSubTabLive|btnTabSetup|btnTabDiag") {
                                    if (Get-Command Update-SecondaryTabStyles -ErrorAction SilentlyContinue) { Update-SecondaryTabStyles }
                                    if (Get-Command Update-TabIndicator -ErrorAction SilentlyContinue) { Update-TabIndicator }
                                } else {
                                    $sender.BackColor = [System.Drawing.Color]::FromArgb(35, 35, 40)
                                }
                                $sender.Invalidate()
                            }
                        })
                        $c.add_Paint({
                            param($sender, $e)
                            if ($global:ThemeNeonActive -and -not $sender.Enabled) {
                                $g = $e.Graphics
                                # 1. Clear background
                                $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(35, 35, 40))
                                $g.FillRectangle($brush, $sender.ClientRectangle)
                                $brush.Dispose()
                                
                                # 2. Draw border (dimmer purple)
                                $w = [int]$sender.Width
                                $h = [int]$sender.Height
                                $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(75, 25, 125), 1)
                                $rect = New-Object System.Drawing.Rectangle(0, 0, ($w - 1), ($h - 1))
                                $g.DrawRectangle($pen, $rect)
                                $pen.Dispose()
                                
                                # 3. Draw text — Option B muted teal-gray #73878E (visible but clearly disabled)
                                $grayColor = [System.Drawing.Color]::FromArgb(115, 135, 145) # #73878E
                                [System.Windows.Forms.TextRenderer]::DrawText(
                                    $g,
                                    $sender.Text,
                                    $sender.Font,
                                    $sender.ClientRectangle,
                                    $grayColor,
                                    [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter
                                )
                            }
                        })
                    }
                }
                elseif ($c.Name -match "^mainSep$|^subSep$|^telemetrySubSep$|^drawer2TabSep$") {
                    $c.BackColor = $global:NeonCyan
                }
                elseif ($c.Name -match "Indicator|advancedTabIndicator|Sep") {
                    $c.BackColor = $global:NeonPurple
                }
                elseif ($c -is [System.Windows.Forms.Label]) {
                    if ($c.Text -eq "SAMISH") {
                        $c.ForeColor = $global:NeonPink
                    } elseif ($c.Name -eq "subtitle") {
                        $c.ForeColor = $global:NeonCyan
                    } elseif ($c.Name -eq "bottomMetadata") {
                        $c.ForeColor = $global:NeonPink
                    } else {
                        $c.ForeColor = $global:NeonText
                    }
                    $c.BackColor = [System.Drawing.Color]::Transparent
                }
                elseif ($c -is [System.Windows.Forms.CheckBox] -or $c -is [System.Windows.Forms.RadioButton]) {
                    # If this is in grpDiagOperatingMode, its ForeColor is handled dynamically by Set-OperatingModeBoxState
                    if ($c.Parent -and $c.Parent.Name -eq "grpDiagOperatingMode") {
                        # let Set-OperatingModeBoxState handle it
                    } else {
                        $c.ForeColor = $global:NeonText
                    }
                    $c.BackColor = [System.Drawing.Color]::Transparent
                }
                elseif ($c -is [System.Windows.Forms.TextBox]) {
                    $c.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 30)
                    $c.ForeColor = $global:NeonCyan
                    $c.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
                }
                elseif ($c -is [System.Windows.Forms.ComboBox]) {
                    $c.BackColor = if ($c.Enabled) { [System.Drawing.Color]::FromArgb(25, 25, 30) } else { [System.Drawing.Color]::FromArgb(45, 45, 50) }
                    $c.ForeColor = if ($c.Enabled) { $global:NeonCyan } else { [System.Drawing.Color]::Gray }
                    $c.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
                    
                    if ($c.PSObject.Properties.Match('ThemeHooked').Count -eq 0) {
                        $c | Add-Member -MemberType NoteProperty -Name 'ThemeHooked' -Value $true
                        $c.add_EnabledChanged({
                            param($sender, $e)
                            if ($global:ThemeNeonActive) {
                                $sender.BackColor = if ($sender.Enabled) { [System.Drawing.Color]::FromArgb(25, 25, 30) } else { [System.Drawing.Color]::FromArgb(45, 45, 50) }
                                $sender.ForeColor = if ($sender.Enabled) { $global:NeonCyan } else { [System.Drawing.Color]::Gray }
                            }
                        })
                    }
                }
                elseif ($c -is [System.Windows.Forms.GroupBox]) {
                    $c.ForeColor = $global:NeonPink
                    if ($c.PSObject.Properties.Match('ThemeHooked').Count -eq 0) {
                        $c | Add-Member -MemberType NoteProperty -Name 'ThemeHooked' -Value $true
                        $c.add_Paint({
                            param($sender, $e)
                            if ($global:ThemeNeonActive) {
                                $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(45, 45, 50), 1)
                                $gbW = [int]$sender.Width
                                $gbH = [int]$sender.Height
                                $rect = New-Object System.Drawing.Rectangle(0, 7, ($gbW - 1), ($gbH - 8))
                                $e.Graphics.DrawRectangle($pen, $rect)
                                $pen.Dispose()
                            }
                        })
                    }
                }
                elseif ($c -is [System.Windows.Forms.ListBox]) {
                    $c.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 25)
                    $c.ForeColor = $global:NeonText
                    $c.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
                }
                elseif ($c -is [System.Windows.Forms.TabControl] -or $c -is [System.Windows.Forms.TabPage] -or $c -is [System.Windows.Forms.Panel]) {
                    if ($c.Name -eq "pnlOnWakeBorder") {
                        # let Set-OperatingModeBoxState handle it
                    } else {
                        $c.BackColor = $global:NeonBackground
                        $c.ForeColor = $global:NeonText
                    }
                }
            } else {
                # Revert theme
                if ($global:OriginalControlStyles.ContainsKey($ctrlKey)) {
                    $styles = $global:OriginalControlStyles[$ctrlKey]
                    if ($c -is [System.Windows.Forms.ListBox] -or $c -is [System.Windows.Forms.TextBox] -or $c -is [System.Windows.Forms.Button] -or $c -is [System.Windows.Forms.ComboBox] -or $c -is [System.Windows.Forms.Panel] -or $c -is [System.Windows.Forms.TabControl] -or $c -is [System.Windows.Forms.TabPage] -or $c.Name -match "Indicator|Sep|mainSep|subSep") {
                        try { $c.BackColor = $styles['BackColor'] } catch { $c.ResetBackColor() }
                    } else {
                        try { $c.ResetBackColor() } catch {}
                    }
                    try { $c.ForeColor = $styles['ForeColor'] } catch { $c.ResetForeColor() }
                    if ($styles.ContainsKey('BorderStyle')) {
                        try { $c.BorderStyle = $styles['BorderStyle'] } catch {}
                    }
                    if ($styles.ContainsKey('FlatStyle')) {
                        try { $c.FlatStyle = $styles['FlatStyle'] } catch {}
                    }
                    if ($c -is [System.Windows.Forms.Button]) {
                        if ($styles.ContainsKey('BorderColor')) {
                            $c.FlatAppearance.BorderColor = $styles['BorderColor']
                        }
                        if ($styles.ContainsKey('BorderSize')) {
                            $c.FlatAppearance.BorderSize = $styles['BorderSize']
                        }
                        if ($styles.ContainsKey('MouseOverBackColor')) {
                            $c.FlatAppearance.MouseOverBackColor = $styles['MouseOverBackColor']
                        }
                    }
                } else {
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
        } catch {}
    }
    # Ensure current state of Operating Mode Tests box is rendered with correct colors for active theme
    if (Get-Command Update-TestGroupState -ErrorAction SilentlyContinue) {
        try { Update-TestGroupState } catch {}
    }
}

function global:Save-ThemePreference {
    param([bool]$IsNeon)
    try {
        $cfgPath = $null
        if ($global:PackageDir) {
            $cfgPath = Join-Path $env:APPDATA "SAMISH\config.json"
        } else {
            $cfgPath = Join-Path $env:APPDATA "SAMISH\config.json"
        }
        
        $cfg = @{}
        if (Test-Path -LiteralPath $cfgPath) {
            try { $cfg = (Get-Content -LiteralPath $cfgPath -Raw) | ConvertFrom-Json } catch { $cfg = @{} }
        } else {
            $dir = Split-Path -Parent $cfgPath
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        }
        
        $themeVal = if ($IsNeon) { "Neon" } else { "Normal" }
        $cfg | Add-Member -MemberType NoteProperty -Name "Theme" -Value $themeVal -Force
        
        $json = $cfg | ConvertTo-Json -Depth 6
        Set-Content -LiteralPath $cfgPath -Value $json -Encoding UTF8
    } catch {}
}
