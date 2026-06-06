# ==========================================
# SAMISH App Control - Graceful Mode
# ==========================================

# This module attempts a graceful shutdown using window messages.
# If graceful shutdown fails (no window handle or process still running),
# it falls back to Classic (force kill) via Invoke-AppStop.

function Invoke-AppStopGraceful {
    param(
        [string]$ProcessName = "BEACN",
        [string]$ConfiguredPath = $null,
        [int]$WindowWakeDelayMs = 800,
        [int]$ShutdownWaitMs = 800
    )

    # Return object contract:
    # AppStopResult

    $windowRestored = $false

    # 1) Confirm process running
    $p = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $p) {
        return [AppStopResult]::new($false, "NotRunning", "NotRunning", $false, $false, "")
    }

    $procId = $p.Id

    # 2) Ensure SendMessage is available (via NativeMethods.ps1)
    if (-not ([System.Management.Automation.PSTypeName]'SamishWin32').Type) {
        # Try to load NativeMethods if not already loaded by caller
        $NativeMethodsPath = Join-Path $PSScriptRoot "NativeMethods.ps1"
        if (Test-Path -LiteralPath $NativeMethodsPath) {
            . $NativeMethodsPath
        }
    }

    if (-not ([System.Management.Automation.PSTypeName]'SamishWin32').Type) {
        if (Get-Command Log-Always -ErrorAction SilentlyContinue) {
            Log-Always "ERROR: SamishWin32 C# signatures for Graceful close are unavailable. Falling back to Classic mode."
        }
        # If type load fails, we cannot do graceful messaging.
        if (Get-Command Invoke-AppStop -ErrorAction SilentlyContinue) {
            $r = Invoke-AppStop -ProcessName $ProcessName
            return [AppStopResult]::new(
                [bool]$r.Stopped,
                $r.Status,
                "ClassicFallback",
                $false,
                $true,
                "Failed to load user32 SendMessage. Fell back to Classic."
            )
        }
        return [AppStopResult]::new($false, "Error", "Error", $false, $false, "Failed to load user32 SendMessage and Classic fallback not available.")
    }

    # 3) Ensure window handle exists; if tray-only, restore UI
    try {
        # Refresh process object by PID to get latest window handle
        $p = Get-Process -Id $procId -ErrorAction Stop
    } catch {
        return [AppStopResult]::new($false, "Error", "Error", $false, $false, "Process disappeared while preparing graceful stop.")
    }

    if ($p.MainWindowHandle -eq 0) {

        # Need executable path to restore UI (same PID behavior expected)
        $exe = $null
        if (Get-Command Get-AppExecutablePath -ErrorAction SilentlyContinue) {
            $info = Get-AppExecutablePath -ProcessName $ProcessName -ConfiguredPath $ConfiguredPath
            if ($info -and $info.IsValid) { $exe = $info.Path }
        }

        if (-not $exe) {
            # Can't restore UI; fall back
            if (Get-Command Invoke-AppStop -ErrorAction SilentlyContinue) {
                $r = Invoke-AppStop -ProcessName $ProcessName
                return [AppStopResult]::new(
                    [bool]$r.Stopped,
                    $r.Status,
                    "ClassicFallback",
                    $false,
                    $true,
                    "No window handle and could not resolve executable path. Fell back to Classic."
                )
            }
            return [AppStopResult]::new($false, "Error", "Error", $false, $false, "No window handle and could not resolve BEACN path, and Classic fallback not available.")
        }

        try {
            # This should restore or open the window for the existing process instance.
            Start-Process -FilePath $exe | Out-Null
            $windowRestored = $true
        } catch {
            # Restore attempt failed; fall back
            if (Get-Command Invoke-AppStop -ErrorAction SilentlyContinue) {
                $r = Invoke-AppStop -ProcessName $ProcessName
                return [AppStopResult]::new(
                    [bool]$r.Stopped,
                    $r.Status,
                    "ClassicFallback",
                    $false,
                    $true,
                    "Failed to restore UI. Fell back to Classic."
                )
            }
            return [AppStopResult]::new($false, "Error", "Error", $false, $false, "Failed to restore UI and Classic fallback not available.")
        }

        # Poll for MainWindowHandle to become non-zero (so we don't sleep longer than necessary)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while ($sw.ElapsedMilliseconds -lt $WindowWakeDelayMs) {
            try {
                $checkP = Get-Process -Id $procId -ErrorAction Stop
                if ($checkP.MainWindowHandle -ne 0) {
                    break
                }
            } catch {
                # Process exited or crashed
                break
            }
            Start-Sleep -Milliseconds 50
        }
        $sw.Stop()

        # Refresh handle
        try {
            $p = Get-Process -Id $procId -ErrorAction Stop
        } catch {
            return [AppStopResult]::new($true, "Stopped", "Graceful", $windowRestored, $false, "")
        }
    }

    # If still no handle, fallback
    if ($p.MainWindowHandle -eq 0) {
        if (Get-Command Invoke-AppStop -ErrorAction SilentlyContinue) {
            $r = Invoke-AppStop -ProcessName $ProcessName
            return [AppStopResult]::new(
                [bool]$r.Stopped,
                $r.Status,
                "ClassicFallback",
                $windowRestored,
                $true,
                "No window handle after restore attempt. Fell back to Classic."
            )
        }
        return [AppStopResult]::new($false, "Error", "Error", $windowRestored, $false, "No window handle after restore attempt and Classic fallback not available.")
    }

    # 4) Send graceful shutdown messages (with one retry before Classic fallback)
    $messageAttempts = 2  # Total attempts: first try + one retry
    for ($msgAttempt = 1; $msgAttempt -le $messageAttempts; $msgAttempt++) {
        if ($msgAttempt -gt 1) {
            if (Get-Command Log-Always -ErrorAction SilentlyContinue) {
                Log-Always "Graceful stop: message retry $msgAttempt/$messageAttempts for $ProcessName"
            }
        }

        try {
            # WM_QUERYENDSESSION = 0x0011
            # WM_ENDSESSION     = 0x0016
            [SamishWin32]::SendMessage($p.MainWindowHandle, 0x0011, [IntPtr]::Zero, [IntPtr]::new(1)) | Out-Null
            [SamishWin32]::SendMessage($p.MainWindowHandle, 0x0016, [IntPtr]::new(1), [IntPtr]::new(1)) | Out-Null
        } catch {
            if ($msgAttempt -lt $messageAttempts) {
                # Retry after brief pause
                Start-Sleep -Milliseconds 500  # measured in ms -- wait before message retry
                continue
            }
            # Final attempt failed; fallback to Classic
            if (Get-Command Invoke-AppStop -ErrorAction SilentlyContinue) {
                $r = Invoke-AppStop -ProcessName $ProcessName
                return [AppStopResult]::new(
                    [bool]$r.Stopped,
                    $r.Status,
                    "ClassicFallback",
                    $windowRestored,
                    $true,
                    "Failed to send shutdown messages after $messageAttempts attempts. Fell back to Classic."
                )
            }
            return [AppStopResult]::new($false, "Error", "Error", $windowRestored, $false, "Failed to send shutdown messages after $messageAttempts attempts and Classic fallback not available.")
        }

        # 5) Poll briefly for the process to exit (so we don't wait longer than necessary if it exits instantly)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $exited = $false
        while ($sw.ElapsedMilliseconds -lt $ShutdownWaitMs) {
            if (-not (Get-Process -Id $procId -ErrorAction SilentlyContinue)) {
                $exited = $true
                break
            }
            Start-Sleep -Milliseconds 50
        }
        $sw.Stop()

        if ($exited) {
            return [AppStopResult]::new($true, "Stopped", "Graceful", $windowRestored, $false, "")
        }

        # If not exited and we have retries left, refresh handle and try again
        if ($msgAttempt -lt $messageAttempts) {
            try {
                $p = Get-Process -Id $procId -ErrorAction Stop
            } catch {
                # Process exited between polls
                return [AppStopResult]::new($true, "Stopped", "Graceful", $windowRestored, $false, "")
            }
        }
    }

    # 6) Fallback to Classic after all message attempts exhausted
    if (Get-Command Invoke-AppStop -ErrorAction SilentlyContinue) {
        $r = Invoke-AppStop -ProcessName $ProcessName
        return [AppStopResult]::new(
            [bool]$r.Stopped,
            $r.Status,
            "ClassicFallback",
            $windowRestored,
            $true,
            "Graceful shutdown did not exit in time after $messageAttempts message attempts. Fell back to Classic."
        )
    }

    return [AppStopResult]::new($false, "Error", "Error", $windowRestored, $false, "Graceful shutdown did not exit in time after $messageAttempts message attempts and Classic fallback not available.")
}