# ========================================================================
# SAMISH Device Adapter Mock Verification Script
# ========================================================================
# This script copies notepad.exe to renamed stubs to mock Voicemeeter,
# Wave Link, GoXLR, and Custom processes. It then tests that the new
# adapters successfully stop and start them.
# ========================================================================

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Modules = Join-Path $Root "Modules"
$Adapters = Join-Path $Modules "Adapters"
$Scratch = Join-Path $Root "scratch"

Write-Host "========================================================================" -ForegroundColor Magenta
Write-Host "                SAMISH Adapter Mock Verification Tool" -ForegroundColor Magenta
Write-Host "========================================================================" -ForegroundColor Magenta
Write-Host

# 1. Load Modules
Write-Host "Loading SAMISH engine helper modules..." -ForegroundColor Gray
. (Join-Path $Modules "App.Control.Common.ps1")
. (Join-Path $Modules "App.Control.Classic.ps1")
. (Join-Path $Modules "App.Control.Graceful.ps1")
Write-Host "Helper modules loaded." -ForegroundColor Green

# 2. Setup Stubs Directory
$StubsDir = Join-Path $Scratch "Stubs"
if (Test-Path -LiteralPath $StubsDir) {
    Remove-Item -LiteralPath $StubsDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $StubsDir -Force | Out-Null

# Copy cmd.exe as stubs
$CmdSrc = "C:\Windows\System32\cmd.exe"

Write-Host "Creating dummy stub executables using cmd.exe..." -ForegroundColor Gray
Copy-Item -LiteralPath $CmdSrc -Destination (Join-Path $StubsDir "voicemeeter8x64.exe") -Force
Copy-Item -LiteralPath $CmdSrc -Destination (Join-Path $StubsDir "WaveLink.exe") -Force
Copy-Item -LiteralPath $CmdSrc -Destination (Join-Path $StubsDir "GoXLR App.exe") -Force
Copy-Item -LiteralPath $CmdSrc -Destination (Join-Path $StubsDir "CustomTarget.exe") -Force
Write-Host "Stubs created." -ForegroundColor Green

# 3. Create Custom-Device.json config for mock testing
$ProfilesDir = Join-Path $Root "Profiles"
$CustomDeviceJson = Join-Path $ProfilesDir "Custom-Device.json"
# We make sure Custom-Device.json exists with our CustomTarget stub path
$customObj = [pscustomobject]@{
    id          = "Custom"
    displayName = "Custom Device (Mock Test)"
    targets     = @(
        [pscustomobject]@{
            processName      = "CustomTarget"
            defaultExePath   = (Join-Path $StubsDir "CustomTarget.exe")
            supportsGraceful = $true
            supportsClassic  = $true
        }
    )
    defaults    = [pscustomobject]@{
        GracefulWindowWakeDelayMs = 200
        GracefulShutdownWaitMs    = 200
    }
}
$customObj | ConvertTo-Json -Depth 5 | Out-File -FilePath $CustomDeviceJson -Encoding UTF8 -Force

# Helper to mock Get-AppExecutablePath for our local stubs
function Get-AppExecutablePath {
    param(
        [string]$ProcessName,
        [string]$ConfiguredPath,
        [string]$RegistrySearchString = $null
    )
    # Redirect registry search to local stub folder for test verification
    $stubFile = Join-Path $StubsDir "$ProcessName.exe"
    if (Test-Path -LiteralPath $stubFile) {
        return [pscustomobject]@{
            IsValid = $true
            Path    = $stubFile
            Source  = "MockRegistry"
        }
    }
    return [pscustomobject]@{ IsValid = $false; Path = $null; Source = $null }
}

# Logger mock so adapters don't throw
function Log-Always([string]$msg) {
    Write-Host "   [ADAPTER LOG] $msg" -ForegroundColor Gray
}

# --- TEST SUITE ---
$targets = @(
    @{ Name = "Voicemeeter"; Process = "voicemeeter8x64"; Script = "Adapter.Voicemeeter.ps1" },
    @{ Name = "WaveLink";     Process = "WaveLink";        Script = "Adapter.WaveLink.ps1" },
    @{ Name = "GoXLR";        Process = "GoXLR App";       Script = "Adapter.GoXLR.ps1" },
    @{ Name = "Custom";       Process = "CustomTarget";    Script = "Adapter.Custom.ps1" }
)

foreach ($t in $targets) {
    Write-Host "`r`nTesting Adapter: $($t.Name) ($($t.Process))" -ForegroundColor Cyan
    
    # Dot source adapter script
    . (Join-Path $Adapters $t.Script)
    
    # Launch stub
    $stubPath = Join-Path $StubsDir "$($t.Process).exe"
    Write-Host "   Spawning stub process: $stubPath" -ForegroundColor Gray
    $proc = Start-Process -FilePath $stubPath -ArgumentList "/k" -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 800 # Let window settle
    
    # Validate Stop
    Write-Host "   Invoking STOP adapter..." -ForegroundColor Gray
    $stopFunc = "Stop-$($t.Name)Adapter"
    $stopped = & $stopFunc `
        -ProcessName $t.Process `
        -ConfiguredPath $stubPath `
        -OperatingMode "Graceful" `
        -WindowWakeDelayMs 200 `
        -ShutdownWaitMs 200
        
    if ($stopped) {
        Write-Host "   SUCCESS: Adapter stopped target process." -ForegroundColor Green
    } else {
        Write-Host "   FAILED: Adapter failed to stop target process." -ForegroundColor Red
        $proc | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    
    # Validate Start
    Write-Host "   Invoking START adapter..." -ForegroundColor Gray
    $startFunc = "Start-$($t.Name)Adapter"
    $started = & $startFunc `
        -ProcessName $t.Process `
        -ConfiguredPath $stubPath
        
    if ($started) {
        Write-Host "   SUCCESS: Adapter started target process." -ForegroundColor Green
        # Cleanup
        Get-Process -Name $t.Process -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "   FAILED: Adapter failed to start target process." -ForegroundColor Red
    }
}

# Cleanup stubs folder
Start-Sleep -Milliseconds 500
Remove-Item -LiteralPath $StubsDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`r`n========================================================================" -ForegroundColor Magenta
Write-Host "                    Verification Complete!" -ForegroundColor Magenta
Write-Host "========================================================================" -ForegroundColor Magenta
