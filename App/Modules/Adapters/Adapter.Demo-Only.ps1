# ==========================================
# SAMISH Device Adapter: Demo-Only
# ==========================================
# This is a sample adapter for developers to build their own device integrations.

function Stop-Demo-OnlyAdapter {
    param(
        [string]$ProcessName,
        [string]$ConfiguredPath,
        [string]$OperatingMode,
        [int]$WindowWakeDelayMs,
        [int]$ShutdownWaitMs
    )

    Log-Always "DEMO ADAPTER: Stop requested for $ProcessName in $OperatingMode mode."
    Log-Always "DEMO ADAPTER: Simulated wait for 500ms..."
    Start-Sleep -Milliseconds 500
    Log-Always "DEMO ADAPTER: Simulated stop success."

    return $true
}

function Start-Demo-OnlyAdapter {
    param(
        [string]$ProcessName,
        [string]$ConfiguredPath
    )

    Log-Always "DEMO ADAPTER: Start requested for $ProcessName."
    Log-Always "DEMO ADAPTER: Simulated wait for 500ms..."
    Start-Sleep -Milliseconds 500
    Log-Always "DEMO ADAPTER: Simulated start success."

    return $true
}
