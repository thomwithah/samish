# ==========================================
# SAMISH Device Adapter: Custom (Advanced)
# ==========================================

function Get-CustomProfileConfig {
    $dir = Join-Path $env:APPDATA "SAMISH\Profiles"
    $file = Join-Path $dir "Custom-Device.json"
    if (-not (Test-Path -LiteralPath $file)) {
        # Fallback to local package directory template
        $file = Join-Path $PSScriptRoot "Profiles\Custom-Device.json"
        if (-not $PSScriptRoot -and $PSCommandPath) {
            $file = Join-Path (Split-Path -Parent $PSCommandPath) "Profiles\Custom-Device.json"
        }
        if (-not (Test-Path -LiteralPath $file)) { return $null }
    }
    try {
        $raw = Get-Content -LiteralPath $file -Raw
        return $raw | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Stop-CustomAdapter {
    param(
        [string]$ProcessName,
        [string]$ConfiguredPath,
        [string]$OperatingMode,
        [int]$WindowWakeDelayMs,
        [int]$ShutdownWaitMs
    )

    $stopped = $false

    # Dynamically resolve values from Custom-Device.json
    $cfg = Get-CustomProfileConfig
    $proc = $ProcessName
    $path = $ConfiguredPath
    if ($cfg -and $cfg.targets -and $cfg.targets.Count -gt 0) {
        $t = $cfg.targets[0]
        if ($t.processName) { $proc = [string]$t.processName }
        if ($t.defaultExePath) { $path = [string]$t.defaultExePath }
    }

    if ($OperatingMode -eq "Graceful" -and (Get-Command Invoke-AppStopGraceful -ErrorAction SilentlyContinue)) {
        Log-Always "Stopping Custom Target: $proc (Graceful mode)"
        $r = Invoke-AppStopGraceful `
            -ProcessName $proc `
            -ConfiguredPath $path `
            -WindowWakeDelayMs $WindowWakeDelayMs `
            -ShutdownWaitMs $ShutdownWaitMs
        
        $method = "Unknown"
        if ($r -and $r.Method) { $method = [string]$r.Method }
        if ($r -and $r.Stopped) {
            Log-Always ("Stopped Custom Target: $proc (" + $method + ")")
            $stopped = $true
        } else {
            $err = ""
            if ($r -and $r.Error) { $err = [string]$r.Error }
            Log-Always ("Graceful stop failed (" + $method + "). " + $err)
        }
    } else {
        Log-Always "Stopping Custom Target: $proc (Classic mode)"
        $r2 = Invoke-AppStop -ProcessName $proc
        if ($r2 -and $r2.Stopped) {
            Log-Always "Stopped Custom Target: $proc (Classic)"
            $stopped = $true
        } else {
            Log-Always "Classic stop failed or process not found."
        }
    }

    return $stopped
}

function Start-CustomAdapter {
    param(
        [string]$ProcessName,
        [string]$ConfiguredPath
    )

    $started = $false

    # Dynamically resolve values from Custom-Device.json
    $cfg = Get-CustomProfileConfig
    $proc = $ProcessName
    $path = $ConfiguredPath
    if ($cfg -and $cfg.targets -and $cfg.targets.Count -gt 0) {
        $t = $cfg.targets[0]
        if ($t.processName) { $proc = [string]$t.processName }
        if ($t.defaultExePath) { $path = [string]$t.defaultExePath }
    }

    $lookup = Get-AppExecutablePath -ProcessName $proc -ConfiguredPath $path
    
    if ($lookup.IsValid) {
        $result = Invoke-AppStart -ProcessName $proc -ExePath $lookup.Path
        if ($result.Started) {
            Log-Always "Starting Custom Target: $proc ($($lookup.Source))"
            $started = $true
        }
    } else {
        Log-Always "Executable for Custom Target: $proc not found. Skipping startup."
    }

    return $started
}
