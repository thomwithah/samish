# ---------- UI.Theme.ps1 ----------
# Developer Note: Font objects and Color brushes must be added to the GDI resource 
# cleanup tracker. Do not invoke GDI resources outside the primary GUI thread. 
# DPI scaling is calculated once on startup and must complete in under 50 ms.
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

$font = New-Object System.Drawing.Font("Segoe UI", 10)
[void]$script:MainFormGdiResources.Add($font)
$boldFont = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
[void]$script:MainFormGdiResources.Add($boldFont)
$titleFont = New-Object System.Drawing.Font("Segoe UI", 24, [System.Drawing.FontStyle]::Bold)
[void]$script:MainFormGdiResources.Add($titleFont)
$subtitleFont = New-Object System.Drawing.Font("Segoe UI", 10)
[void]$script:MainFormGdiResources.Add($subtitleFont)
$lblDetailsTitleFont = New-Object System.Drawing.Font("Segoe UI", 8.25, [System.Drawing.FontStyle]::Bold)
[void]$script:MainFormGdiResources.Add($lblDetailsTitleFont)
$detailsFont = New-Object System.Drawing.Font("Segoe UI", 7.5)
[void]$script:MainFormGdiResources.Add($detailsFont)
$statusBoxFont = New-Object System.Drawing.Font("Consolas", 9)
[void]$script:MainFormGdiResources.Add($statusBoxFont)

