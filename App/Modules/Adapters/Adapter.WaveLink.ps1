# ==========================================
# SAMISH Device Adapter: WaveLink
# ==========================================

function Stop-WaveLinkAdapter {
    param(
        [string]$ProcessName,
        [string]$ConfiguredPath,
        [string]$OperatingMode,
        [int]$WindowWakeDelayMs,
        [int]$ShutdownWaitMs
    )

    $stopped = $false

    if ($OperatingMode -eq "Graceful" -and (Get-Command Invoke-AppStopGraceful -ErrorAction SilentlyContinue)) {
        Log-Always "Stopping $ProcessName (Graceful mode)"
        $r = Invoke-AppStopGraceful `
            -ProcessName $ProcessName `
            -ConfiguredPath $ConfiguredPath `
            -WindowWakeDelayMs $WindowWakeDelayMs `
            -ShutdownWaitMs $ShutdownWaitMs
        
        $method = "Unknown"
        if ($r -and $r.Method) { $method = [string]$r.Method }
        if ($r -and $r.Stopped) {
            Log-Always ("Stopped $ProcessName (" + $method + ")")
            $stopped = $true
        } else {
            $err = ""
            if ($r -and $r.Error) { $err = [string]$r.Error }
            Log-Always ("Graceful stop failed (" + $method + "). " + $err)
        }
    } else {
        Log-Always "Stopping $ProcessName (Classic mode)"
        $r2 = Invoke-AppStop -ProcessName $ProcessName
        if ($r2 -and $r2.Stopped) {
            Log-Always "Stopped $ProcessName (Classic)"
            $stopped = $true
        } else {
            Log-Always "Classic stop failed or process not found."
        }
    }

    return $stopped
}

function Start-WaveLinkAdapter {
    param(
        [string]$ProcessName,
        [string]$ConfiguredPath
    )

    $started = $false

    $lookup = Get-AppExecutablePath -ProcessName $ProcessName -ConfiguredPath $ConfiguredPath -RegistrySearchString "WaveLink"
    
    if ($lookup.IsValid) {
        $result = Invoke-AppStart -ProcessName $ProcessName -ExePath $lookup.Path
        if ($result.Started) {
            Log-Always "Starting $ProcessName ($($lookup.Source))"
            $started = $true
        }
    } else {
        Log-Always "Executable for $ProcessName not found. Skipping startup."
    }

    return $started
}
