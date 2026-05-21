# ==========================================
# SAMISH App Control - Classic Mode
# ==========================================

function Invoke-AppStop {
    param(
        [string]$ProcessName = "BEACN"
    )

    # ✅ Flexible match instead of exact match
    $p = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -like "*$ProcessName*"
    }

    if ($p) {
        try {
            $p | Stop-Process -Force -ErrorAction SilentlyContinue

            return @{
                Stopped = $true
                Status  = "Stopped"
            }
        }
        catch {
            return @{
                Stopped = $false
                Status  = "Error"
            }
        }
    }

    Write-Host "DEBUG: No process matched for name fragment: $ProcessName"

    return @{
        Stopped = $false
        Status  = "NotRunning"
    }
}


function Invoke-AppStart {
    param(
        [string]$ProcessName = "BEACN",
        [string]$ExePath
    )

    if (-not (Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)) {

        if ($ExePath -and (Test-Path $ExePath)) {
            try {
                Start-Process $ExePath | Out-Null
                return @{
                    Started = $true
                    Status  = "Started"
                }
            } catch {
                return @{
                    Started = $false
                    Status  = "Error"
                }
            }
        }

        return @{
            Started = $false
            Status  = "PathInvalid"
        }
    }

    return @{
        Started = $false
        Status  = "AlreadyRunning"
    }
}