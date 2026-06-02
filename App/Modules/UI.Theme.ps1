# ---------- UI.Theme.ps1 ----------
# Developer Note: Font objects and Color brushes must be added to the GDI resource 
# cleanup tracker. Do not invoke GDI resources outside the primary GUI thread. 
# DPI scaling is calculated once on startup and must complete in under 50 ms.


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

$font = New-Object System.Drawing.Font("Segoe UI", [float](10 * $script:DpiScale))
[void]$script:MainFormGdiResources.Add($font)
$boldFont = New-Object System.Drawing.Font("Segoe UI", [float](10 * $script:DpiScale), [System.Drawing.FontStyle]::Bold)
[void]$script:MainFormGdiResources.Add($boldFont)
$titleFont = New-Object System.Drawing.Font("Segoe UI", [float](24 * $script:DpiScale), [System.Drawing.FontStyle]::Bold)
[void]$script:MainFormGdiResources.Add($titleFont)
$subtitleFont = New-Object System.Drawing.Font("Segoe UI", [float](10 * $script:DpiScale))
[void]$script:MainFormGdiResources.Add($subtitleFont)
$lblDetailsTitleFont = New-Object System.Drawing.Font("Segoe UI", [float](8.25 * $script:DpiScale), [System.Drawing.FontStyle]::Bold)
[void]$script:MainFormGdiResources.Add($lblDetailsTitleFont)
$detailsFont = New-Object System.Drawing.Font("Segoe UI", [float](7.5 * $script:DpiScale))
[void]$script:MainFormGdiResources.Add($detailsFont)
$statusBoxFont = New-Object System.Drawing.Font("Consolas", [float](9 * $script:DpiScale))
[void]$script:MainFormGdiResources.Add($statusBoxFont)
