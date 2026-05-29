# ========================================================================
# SAMISH Custom Device Profile Configuration Wizard
# ========================================================================
# This script guides the user through setting up a custom device profile.
# It validates inputs defensively and updates Custom-Device.json.
# ========================================================================

$ErrorActionPreference = "Stop"

Clear-Host
Write-Host "========================================================================" -ForegroundColor Magenta
Write-Host "            SAMISH Custom Device Profile Configuration Wizard" -ForegroundColor Magenta
Write-Host "========================================================================" -ForegroundColor Magenta
Write-Host "This helper will configure your Custom Device Profile."
Write-Host "This lets you stop and start any arbitrary application during sleep/wake."
Write-Host

# 1. Resolve Path to Custom-Device.json
$InstallDir = Join-Path $env:APPDATA "SAMISH"
$ProfilesDir = Join-Path $InstallDir "Profiles"
$ConfigPath = Join-Path $ProfilesDir "Custom-Device.json"

# Fallback: if running from source folder before install, configure locally
if (-not (Test-Path -LiteralPath $ProfilesDir)) {
    $ProfilesDir = Join-Path $PSScriptRoot "Profiles"
    $ConfigPath = Join-Path $ProfilesDir "Custom-Device.json"
}

# Ensure target folder exists
if (-not (Test-Path -LiteralPath $ProfilesDir)) {
    try {
        New-Item -ItemType Directory -Path $ProfilesDir -Force | Out-Null
    } catch {
        Write-Host "ERROR: Could not create profile directory at $ProfilesDir" -ForegroundColor Red
        Exit 1
    }
}

# Load existing values if present, otherwise set defaults
$displayName = "Custom Device (Advanced)"
$processName = "NOTEPAD"
$defaultExePath = "C:\Windows\notepad.exe"
$gracefulDelay = 800
$shutdownWait = 800

if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $raw = Get-Content -LiteralPath $ConfigPath -Raw
        $cfg = $raw | ConvertFrom-Json
        if ($cfg) {
            if ($cfg.displayName) { $displayName = $cfg.displayName }
            if ($cfg.targets -and $cfg.targets.Count -gt 0) {
                $t = $cfg.targets[0]
                if ($t.processName) { $processName = $t.processName }
                if ($t.defaultExePath) { $defaultExePath = $t.defaultExePath }
            }
            if ($cfg.defaults) {
                if ($cfg.defaults.GracefulWindowWakeDelayMs) { $gracefulDelay = $cfg.defaults.GracefulWindowWakeDelayMs }
                if ($cfg.defaults.GracefulShutdownWaitMs) { $shutdownWait = $cfg.defaults.GracefulShutdownWaitMs }
            }
        }
    }
    catch {}
}

# --- Prompt 1: Display Name ---
Write-Host "1. Enter the display name to show in the SAMISH Setup UI:" -ForegroundColor Cyan
Write-Host "   [Current: $displayName]"
$inputName = Read-Host "   New Name (Press Enter to keep current)"
if (-not [string]::IsNullOrWhiteSpace($inputName)) {
    $displayName = $inputName.Trim()
}
Write-Host

# --- Prompt 2: Process Name ---
while ($true) {
    Write-Host "2. Enter the target process name (WITHOUT the .exe extension):" -ForegroundColor Cyan
    Write-Host "   [Current: $processName]"
    $inputProc = Read-Host "   New Process Name (Press Enter to keep current)"
    if ([string]::IsNullOrWhiteSpace($inputProc)) {
        break
    }
    
    $cleanProc = $inputProc.Trim()
    if ($cleanProc.EndsWith(".exe", [System.StringComparison]::OrdinalIgnoreCase)) {
        $cleanProc = $cleanProc.Substring(0, $cleanProc.Length - 4)
    }
    
    if (-not [string]::IsNullOrWhiteSpace($cleanProc)) {
        $processName = $cleanProc
        break
    }
}
Write-Host

# --- Prompt 3: Executable Path ---
while ($true) {
    Write-Host "3. Enter the absolute path to the application's executable:" -ForegroundColor Cyan
    Write-Host "   [Current: $defaultExePath]"
    $inputPath = Read-Host "   New Path (Press Enter to keep current)"
    
    $tempPath = $defaultExePath
    if (-not [string]::IsNullOrWhiteSpace($inputPath)) {
        $tempPath = $inputPath.Trim()
        # Remove surrounding quotes if user dragged and dropped the file
        $tempPath = $tempPath.Trim('"').Trim("'")
    }

    # Defensive path check (failing forward with a warning if missing)
    if (Test-Path -LiteralPath $tempPath) {
        $defaultExePath = $tempPath
        break
    } else {
        Write-Host "   WARNING: Executable not found at '$tempPath'." -ForegroundColor Yellow
        $confirm = Read-Host "   Do you want to save this path anyway? (y/n)"
        if ($confirm -eq "y" -or $confirm -eq "yes") {
            $defaultExePath = $tempPath
            break
        }
    }
}
Write-Host

# --- Prompt 4: Delays ---
Write-Host "4. Advanced Delays (Optional):" -ForegroundColor Cyan
Write-Host "   - Window Wake Delay: Time in milliseconds to wait after restoring UI window."
Write-Host "     [Current: $gracefulDelay ms]"
$inputWake = Read-Host "     New Delay (Press Enter to keep current)"
if (-not [string]::IsNullOrWhiteSpace($inputWake) -and $inputWake -as [int]) {
    $gracefulDelay = [int]$inputWake
}

Write-Host "   - Shutdown Wait: Time in milliseconds to wait for graceful exit before force kill."
Write-Host "     [Current: $shutdownWait ms]"
$inputShutdown = Read-Host "     New Wait (Press Enter to keep current)"
if (-not [string]::IsNullOrWhiteSpace($inputShutdown) -and $inputShutdown -as [int]) {
    $shutdownWait = [int]$inputShutdown
}
Write-Host

# --- Compile and Save JSON ---
try {
    $jsonObj = [pscustomobject]@{
        id          = "Custom"
        displayName = $displayName
        targets     = @(
            [pscustomobject]@{
                processName      = $processName
                defaultExePath   = $defaultExePath
                supportsGraceful = $true
                supportsClassic  = $true
            }
        )
        defaults    = [pscustomobject]@{
            GracefulWindowWakeDelayMs = $gracefulDelay
            GracefulShutdownWaitMs    = $shutdownWait
        }
    }

    $jsonStr = $jsonObj | ConvertTo-Json -Depth 5
    $jsonStr | Out-File -FilePath $ConfigPath -Encoding UTF8 -Force
    
    Write-Host "========================================================================" -ForegroundColor Green
    Write-Host "SUCCESS: Custom Device Profile saved successfully!" -ForegroundColor Green
    Write-Host "File saved to: $ConfigPath" -ForegroundColor Gray
    Write-Host "========================================================================" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Failed to save profile configuration." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
