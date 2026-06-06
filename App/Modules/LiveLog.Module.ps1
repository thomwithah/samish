#requires -Version 5.1
# ==============================================================================
# Module: LiveLog.Module.ps1
# Purpose: Live log streaming in the Setup UI status panel. Polls the SAMISH
#          log file and appends new content in real-time with a console-style
#          appearance. Manages enter/exit state and deferred status updates.
#          Extracted from Setup.ps1 to reduce its size.
# Inputs: statusBox, btnLiveLog controls (from UI.ps1); log path from config.
# Outputs: Real-time log streaming to the statusBox control.
# Error Handling: try/catch with fail-forward for all file I/O.
# ==============================================================================

# ----- Live Log (in Status box) helpers -----
$script:IsLiveLogMode = $false
$script:SavedStatusText = ""
$script:SavedStatusBack = $null
$script:SavedStatusFore = $null
$script:SavedStatusFont = $null
$script:LiveLogTimer = $null
$script:LiveLogPosition = 0

function Enter-LiveLogMode {
    $path = Get-VerifiedPreferredLogPathOrShowMessageBox
    if (-not $path) { return }

    $script:IsLiveLogMode = $true
    # Reset deferred status buffer for this live session
    $script:DeferredStatusUpdates = @()
    $script:DeferredStatusLatest = $null
    $script:SavedStatusText = $statusBox.Text
    $script:SavedStatusBack = $statusBox.BackColor
    $script:SavedStatusFore = $statusBox.ForeColor
    $script:SavedStatusFont = $statusBox.Font

    # Live-log theme (uses Neon palette when active, dark console look otherwise)
    if ($global:ThemeCustomActive) {
        $statusBox.BackColor = if ($global:ThemeCustomPanel) { $global:ThemeCustomPanel } else { [System.Drawing.Color]::FromArgb(18, 18, 22) }
        $statusBox.ForeColor = if ($global:ThemeCustomPrimary) { $global:ThemeCustomPrimary } else { [System.Drawing.Color]::FromArgb(0, 245, 212) }
    } else {
        $statusBox.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 35)
        $statusBox.ForeColor = [System.Drawing.Color]::Gainsboro
    }
    if (-not $script:LiveLogFont) {
        $script:LiveLogFont = New-Object System.Drawing.Font("Consolas", 9)
        if ($script:MainFormGdiResources) {
            $script:MainFormGdiResources.Add($script:LiveLogFont)
        }
    }
    $statusBox.Font = $script:LiveLogFont

    $statusBox.Clear()
    $statusBox.AppendText("LIVE LOG (press Live Log again to exit)`r`n`r`n")

    # Start at end - show last chunk first (small tail)
    try {
        $fi = Get-Item -LiteralPath $path
        $len = [int64]$fi.Length
        $script:LiveLogPosition = [Math]::Max(0, $len - 8192)  # last ~8KB
    }
    catch {
        $script:LiveLogPosition = 0
    }

    # Timer to poll for new data
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 350
    $timer.Add_Tick({
            try {
                Append-LiveLogChunk -Path $path
            }
            catch { }
        })
    $script:LiveLogTimer = $timer
    $timer.Start()

    # Button text flip
    $btnLiveLog.Text = "Exit Live Log"
}

function Exit-LiveLogMode {
    $script:IsLiveLogMode = $false

    try {
        if ($script:LiveLogTimer) {
            $script:LiveLogTimer.Stop()
            $script:LiveLogTimer.Dispose()
            $script:LiveLogTimer = $null
        }
    }
    catch { }

    # Restore theme + text
    if ($script:SavedStatusBack) { $statusBox.BackColor = $script:SavedStatusBack }
    if ($script:SavedStatusFore) { $statusBox.ForeColor = $script:SavedStatusFore }
    if ($script:SavedStatusFont) { $statusBox.Font = $script:SavedStatusFont }

    # Restore content:
    # - Start with what was there before Live Log
    # - Then append any status updates that happened while Live Log was active
    if ($script:DeferredStatusUpdates -and $script:DeferredStatusUpdates.Count -gt 0) {

        $merged = $script:SavedStatusText

        if (-not [string]::IsNullOrWhiteSpace($merged)) {
            $merged += "`r`n`r`n"
        }

        $merged += "--- Updates while Live Log was active ---`r`n`r`n"

        # De-dupe adjacent identical updates (common when the same status is set twice)
        $out = New-Object System.Collections.Generic.List[string]
        $prev = $null
        foreach ($u in $script:DeferredStatusUpdates) {
            if ($null -ne $u -and $u -ne $prev) {
                $out.Add($u)
                $prev = $u
            }
        }

        $merged += ($out -join "`r`n`r`n")

        $statusBox.Text = $merged
    }
    else {
        $statusBox.Text = $script:SavedStatusText
    }

    $btnLiveLog.Text = "Live Log"
}

function Append-LiveLogChunk {
    param([string]$Path)

    if (-not $script:IsLiveLogMode) { return }
    if (-not (Test-Path -LiteralPath $Path)) { return }

    $fs = $null
    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        if ($script:LiveLogPosition -gt $fs.Length) { $script:LiveLogPosition = 0 } # log rotated/truncated

        $fs.Seek($script:LiveLogPosition, [System.IO.SeekOrigin]::Begin) | Out-Null
        $sr = New-Object System.IO.StreamReader($fs)

        # Read to end
        $newText = $sr.ReadToEnd()
        $script:LiveLogPosition = $fs.Position

        if (-not [string]::IsNullOrEmpty($newText)) {
            $statusBox.AppendText($newText)

            # Hard cap to keep UI snappy (keep last ~200k chars)
            $maxChars = 200000
            if ($statusBox.TextLength -gt $maxChars) {
                $statusBox.Text = $statusBox.Text.Substring($statusBox.TextLength - $maxChars)
                $statusBox.SelectionStart = $statusBox.TextLength
                $statusBox.ScrollToCaret()
            }
        }
    }
    finally {
        if ($fs) { $fs.Dispose() }
    }
}
