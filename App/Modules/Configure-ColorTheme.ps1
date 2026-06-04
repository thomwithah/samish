# Configure-ColorTheme.ps1
# Interactive wizard to generate custom_theme.json

$AppDir = Split-Path -Parent $PSScriptRoot
$TemplateFile = Join-Path $AppDir "custom_theme_template.json"
$TargetFile = Join-Path $AppDir "custom_theme.json"
$BackupFile = Join-Path $AppDir "custom_theme.json.bak"
$ProjectRoot = Split-Path -Parent $AppDir
$Executable = Join-Path $ProjectRoot "dist\v1.3.0\SAMISH_Setup_v1.3.0.exe"

if (-not (Test-Path $TemplateFile)) {
    Write-Host "Error: custom_theme_template.json not found in $AppDir" -ForegroundColor Red
    exit
}

Add-Type -AssemblyName System.Drawing

function Set-ConfigThemeValue {
    param([string]$ThemeValue)
    try {
        $cfgPath = Join-Path $env:APPDATA "SAMISH\config.json"
        $cfg = @{}
        if (Test-Path -LiteralPath $cfgPath) {
            $raw = Get-Content -LiteralPath $cfgPath -Raw -ErrorAction SilentlyContinue
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $cfg = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
            }
        }
        if ($null -eq $cfg) { $cfg = @{} }
        $cfg | Add-Member -MemberType NoteProperty -Name "Theme" -Value $ThemeValue -Force
        $json = $cfg | ConvertTo-Json -Depth 6
        Set-Content -LiteralPath $cfgPath -Value $json -Encoding UTF8
    } catch {
        Write-Host "Warning: Failed to update Theme in config.json: $_" -ForegroundColor Yellow
    }
}

# Startup custom theme verification check
if (Test-Path -LiteralPath $TargetFile) {
    $cfgPath = Join-Path $env:APPDATA "SAMISH\config.json"
    $currentTheme = "Normal"
    if (Test-Path -LiteralPath $cfgPath) {
        try {
            $raw = Get-Content -LiteralPath $cfgPath -Raw -ErrorAction SilentlyContinue
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $cfg = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($cfg -and $cfg.PSObject.Properties.Match('Theme').Count -gt 0) {
                    $currentTheme = $cfg.Theme
                }
            }
        } catch {}
    }
    if ($currentTheme -ne "Custom") {
        Write-Host "=============================================" -ForegroundColor Cyan
        Write-Host " A saved custom theme configuration was found." -ForegroundColor Cyan
        Write-Host "=============================================" -ForegroundColor Cyan
        Write-Host ""
        $applyChoice = Read-Host "Would you like to activate and apply it as your active theme now? (Y/N)"
        if ($applyChoice -match "^y" -or $applyChoice -match "^Y") {
            Set-ConfigThemeValue -ThemeValue "Custom"
            Write-Host "Custom theme activated successfully." -ForegroundColor Green
            Start-Sleep -Seconds 2
        }
    }
}

function Prompt-Color {
    param(
        [string]$PromptText,
        [string]$DefaultValue
    )
    
    while ($true) {
        Write-Host ""
        Write-Host $PromptText -ForegroundColor Cyan
        Write-Host "Current/Default: $DefaultValue" -ForegroundColor DarkGray
        $inputVal = Read-Host "Enter color (Hex, RGB, or Name) [Press Enter to keep default]"
        
        if ([string]::IsNullOrWhiteSpace($inputVal)) {
            return $DefaultValue
        }
        
        # Validation
        $inputVal = $inputVal.Trim()
        
        # Hex Check
        if ($inputVal -match "^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})$") {
            return $inputVal
        }
        
        # RGB Check
        if ($inputVal -match "^(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})$") {
            $r, $g, $b = [int]$matches[1], [int]$matches[2], [int]$matches[3]
            if ($r -le 255 -and $g -le 255 -and $b -le 255) {
                return "$r, $g, $b"
            }
        }
        
        # Named Color Check
        $namedColor = [System.Drawing.Color]::FromName($inputVal)
        if ($namedColor.IsKnownColor) {
            # Convert named color to RGB string
            return "$($namedColor.R), $($namedColor.G), $($namedColor.B)"
        }
        
        Write-Host "Invalid color format. Please use Hex (e.g., #FF0000), RGB (e.g., 255, 0, 0), or a standard color name (e.g., Red, LightBlue)." -ForegroundColor Red
    }
}

function Run-Wizard {
    # Backup existing theme if it exists
    if (Test-Path $TargetFile) {
        Copy-Item $TargetFile $BackupFile -Force
        Write-Host "Backed up current theme to custom_theme.json.bak" -ForegroundColor DarkGray
    }

    # Load current values from Target (if exists) or Template
    $sourceFile = if (Test-Path $TargetFile) { $TargetFile } else { $TemplateFile }
    $Config = Get-Content $sourceFile | ConvertFrom-Json

    Write-Host "`n=========================================="
    Write-Host " SAMISH Color Theme Configurator"
    Write-Host "=========================================="
    Write-Host "You can use Hex codes (#FF0066), ARGB (255, 0, 102), or simple names (Red, MintCream)."

    $Config.BaseColors.Background = Prompt-Color -PromptText "Main Window Background" -DefaultValue $Config.BaseColors.Background
    $Config.BaseColors.Panel = Prompt-Color -PromptText "GroupBox & Panel Background" -DefaultValue $Config.BaseColors.Panel
    $Config.BaseColors.Input = Prompt-Color -PromptText "TextBox & ComboBox Background" -DefaultValue $Config.BaseColors.Input
    $Config.BaseColors.Button = Prompt-Color -PromptText "Button Background" -DefaultValue $Config.BaseColors.Button
    $Config.BaseColors.ButtonHover = Prompt-Color -PromptText "Button Hover Background" -DefaultValue $Config.BaseColors.ButtonHover
    $Config.BaseColors.Disabled = Prompt-Color -PromptText "Disabled Control Background" -DefaultValue $Config.BaseColors.Disabled
    $Config.BaseColors.DisabledText = Prompt-Color -PromptText "Greyed-out/Disabled Text Color" -DefaultValue $Config.BaseColors.DisabledText
    $Config.BaseColors.BorderDim = Prompt-Color -PromptText "Dimmed Border (Disabled Buttons)" -DefaultValue $Config.BaseColors.BorderDim
    $Config.BaseColors.Text = Prompt-Color -PromptText "Primary Text Color" -DefaultValue $Config.BaseColors.Text
    $Config.BaseColors.CheckboxBg = Prompt-Color -PromptText "Checkbox & RadioButton Box/Circle Background Color" -DefaultValue $Config.BaseColors.CheckboxBg
    $Config.BaseColors.CheckboxBorder = Prompt-Color -PromptText "Checkbox & RadioButton Border Color" -DefaultValue $Config.BaseColors.CheckboxBorder
    $Config.BaseColors.CheckboxCheck = Prompt-Color -PromptText "Checkbox Check & RadioButton Dot Color" -DefaultValue $Config.BaseColors.CheckboxCheck

    $Config.VibrantAccents.Primary = Prompt-Color -PromptText "Primary Highlight/Accent (e.g. active tab line, neon cyan)" -DefaultValue $Config.VibrantAccents.Primary
    $Config.VibrantAccents.Secondary = Prompt-Color -PromptText "Secondary Border/Accent (e.g. textbox focus border, neon purple)" -DefaultValue $Config.VibrantAccents.Secondary
    $Config.VibrantAccents.Alert = Prompt-Color -PromptText "Alert/Warning Accent (e.g. error flashes, neon pink)" -DefaultValue $Config.VibrantAccents.Alert
    $Config.VibrantAccents.Highlight = Prompt-Color -PromptText "Micro-Highlight (e.g. success flashes, neon lime)" -DefaultValue $Config.VibrantAccents.Highlight

    $jsonOutput = $Config | ConvertTo-Json -Depth 5
    Set-Content -Path $TargetFile -Value $jsonOutput -Encoding UTF8

    Write-Host "`nTheme configuration saved to: $TargetFile" -ForegroundColor Green
    Set-ConfigThemeValue -ThemeValue "Custom"
    Write-Host "Custom theme set as active in config.json!" -ForegroundColor Green
    
    if (Test-Path $Executable) {
        Write-Host ""
        $launch = Read-Host "Would you like to launch SAMISH now to preview your new colors? (Y/N)"
        if ($launch -match "^y" -or $launch -match "^Y") {
            Write-Host "Launching SAMISH..." -ForegroundColor Cyan
            Start-Process $Executable
        }
    }
}

while ($true) {
    Clear-Host
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host " SAMISH Interactive Color Theme Configurator" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Please select an option:"
    Write-Host " [1] Create or edit your Custom Color Theme"
    Write-Host " [2] Restore default brand theme"
    Write-Host " [3] Restore your previously saved Custom Theme (from backup)"
    Write-Host " [X] Exit"
    Write-Host ""
    
    $choice = Read-Host "Selection"
    
    if ($choice -eq "1") {
        Run-Wizard
        break
    }
    elseif ($choice -eq "2") {
        $saveCustom = Read-Host "`nWould you like to save/keep your current custom theme colors before reverting to defaults? (Y/N)"
        if ($saveCustom -match "^y" -or $saveCustom -match "^Y") {
            if (Test-Path $TargetFile) {
                Copy-Item $TargetFile $BackupFile -Force
                Write-Host "`nYour custom theme configuration has been saved/backed up to custom_theme.json.bak." -ForegroundColor Green
            }
        } else {
            if (Test-Path $TargetFile) {
                Move-Item $TargetFile $BackupFile -Force
                Write-Host "`nCustom theme backed up to custom_theme.json.bak and removed." -ForegroundColor Green
            }
        }
        Set-ConfigThemeValue -ThemeValue "Normal"
        Write-Host "SAMISH theme reset to default brand colors." -ForegroundColor Green
        Start-Sleep -Seconds 3
        break
    }
    elseif ($choice -eq "3") {
        if (Test-Path $BackupFile) {
            Copy-Item $BackupFile $TargetFile -Force
            Set-ConfigThemeValue -ThemeValue "Custom"
            Write-Host "`nSuccessfully restored Custom Theme from backup and set as active." -ForegroundColor Green
        } else {
            Write-Host "`nNo backup file found at $BackupFile" -ForegroundColor Red
        }
        Start-Sleep -Seconds 3
        break
    }
    elseif ($choice -match "^x" -or $choice -match "^X") {
        break
    }
}
