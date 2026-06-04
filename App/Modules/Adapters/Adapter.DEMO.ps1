#requires -Version 5.1
# ==========================================
# SAMISH Device Adapter: DEMO
# ==========================================
# Purpose: Mock device adapter for user interface testing, simulated sleep blocker scans,
#          and wake/resume action simulation.
#
# Inputs:
#   Stop-DEMOAdapter:
#     -ProcessName: Process name to stop (simulated)
#     -ConfiguredPath: Path to executable (simulated)
#     -OperatingMode: Active operating mode (Graceful vs Classic)
#     -WindowWakeDelayMs: Wake delay in milliseconds
#     -ShutdownWaitMs: Shutdown wait in milliseconds
#
#   Start-DEMOAdapter:
#     -ProcessName: Process name to start (simulated)
#     -ConfiguredPath: Path to executable (simulated)
#
# Outputs:
#   Returns $true upon successful execution.
#
# Error Handling:
#   Uses standard powershell error handling; fails forward.
# ==========================================

function Stop-DEMOAdapter {
    param(
        [string]$ProcessName,
        [string]$ConfiguredPath,
        [string]$OperatingMode,
        [int]$WindowWakeDelayMs,
        [int]$ShutdownWaitMs
    )

    Log-Always "DEMO ADAPTER: Stop requested for $ProcessName in $OperatingMode mode."
    Log-Always "DEMO ADAPTER: Simulated wait for 500ms..."
    # measured in ms (simulated wait)
    Start-Sleep -Milliseconds 500
    Log-Always "DEMO ADAPTER: Simulated stop success."

    return $true
}

function Start-DEMOAdapter {
    param(
        [string]$ProcessName,
        [string]$ConfiguredPath
    )

    Log-Always "DEMO ADAPTER: Start requested for $ProcessName."
    Log-Always "DEMO ADAPTER: Simulated wait for 500ms..."
    # measured in ms (simulated wait)
    Start-Sleep -Milliseconds 500
    Log-Always "DEMO ADAPTER: Simulated start success."

    return $true
}
