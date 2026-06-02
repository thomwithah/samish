#requires -Version 5.1
# =============================================================================
# SAMISH Game-Mode Guard
# =============================================================================
# Purpose:  Detects when the user is running a full-screen game (or any
#           process listed in the config's GameModeList). When active, the
#           engine skips non-essential diagnostics to avoid performance impact.
#
# Inputs:   -Enabled  (bool)   - master switch from config.json
#           -GameList (array)   - process names to watch
#
# Outputs:  Invoke-GameModeCheck returns $true when game mode should be active.
#
# Error handling: All external calls wrapped in try/catch; returns $false on
#                 any failure so the engine continues normally.
# =============================================================================

function Invoke-GameModeCheck {
    <#
    .SYNOPSIS
        Returns $true if any process in the game-mode list is currently running.

    .DESCRIPTION
        Checks the Enabled flag and GameList array passed as parameters.
        If enabled and at least one listed process is found, game mode is
        considered active and non-essential engine work should be skipped.

    .PARAMETER Enabled
        Master switch -- if $false, returns $false immediately.

    .PARAMETER GameList
        Array of process names (without .exe) to check against running processes.

    .OUTPUTS
        [bool] $true when game mode is active, $false otherwise.
    #>
    param(
        [bool]$Enabled = $false,
        [string[]]$GameList = @()
    )

    # Guard: feature disabled or no list configured
    if (-not $Enabled) { return $false }
    if (-not $GameList -or $GameList.Count -eq 0) { return $false }

    try {
        # Snapshot running process names once (cheaper than per-item Get-Process)
        $runningNames = @{}
        foreach ($proc in (Get-Process -ErrorAction SilentlyContinue)) {
            $key = $proc.ProcessName.ToLower()
            if (-not $runningNames.ContainsKey($key)) {
                $runningNames[$key] = $true
            }
        }

        foreach ($target in $GameList) {
            if ([string]::IsNullOrWhiteSpace($target)) { continue }

            # Strip .exe suffix if user included it
            $name = $target.Trim()
            if ($name.EndsWith('.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
                $name = [System.IO.Path]::GetFileNameWithoutExtension($name)
            }

            if ($runningNames.ContainsKey($name.ToLower())) {
                return $true
            }
        }
    }
    catch {
        # Fail-forward: if process enumeration fails, assume not in game mode
        try { Log-Always "GameModeGuard error: $_" } catch {}
    }

    return $false
}

Export-ModuleMember -Function Invoke-GameModeCheck
