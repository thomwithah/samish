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

    # 1. Check if process is already running
    if (Get-Process -Name $ProcessName -ErrorAction SilentlyContinue) {
        return @{
            Started = $false
            Status  = "AlreadyRunning"
            Log     = "Process $ProcessName is already running"
        }
    }

    $logTrace = [System.Collections.Generic.List[string]]::new()

    # Verification helper to poll for the process
    $VerifyActive = {
        param([string]$name)
        for ($i = 0; $i -lt 15; $i++) {
            if (Get-Process -Name $name -ErrorAction SilentlyContinue) {
                return $true
            }
            Start-Sleep -Milliseconds 200
        }
        return $false
    }

    # 2. Try Direct Path with Working Directory
    if ($ExePath -and (Test-Path $ExePath)) {
        $logTrace.Add("Direct launch: attempting to run from path")
        try {
            $workingDir = Split-Path -Parent $ExePath
            $null = Start-Process -FilePath $ExePath -WorkingDirectory $workingDir -PassThru -ErrorAction Stop
            if (&$VerifyActive -name $ProcessName) {
                return @{
                    Started = $true
                    Status  = "Started"
                    Method  = "Direct"
                    Log     = $logTrace -join "; "
                }
            } else {
                $logTrace.Add("Direct launch spawned process, but it did not appear in memory within 3 seconds")
            }
        }
        catch {
            $logTrace.Add("Direct launch failed: $($_.Exception.Message)")
        }
    }
    else {
        $logTrace.Add("Direct launch skipped: configured path is invalid or empty")
    }

    # 3. Try UWP Execution Alias
    # Check if this could be a UWP App (by path name or by checking the local WindowsApps folder)
    $isUwpCandidate = ($ExePath -and $ExePath -like "*\WindowsApps\*") -or ($ProcessName -eq "Spotify")
    if ($isUwpCandidate) {
        $logTrace.Add("UWP candidate: searching for execution alias")
        try {
            # Try to resolve alias name based on configured file name, falling back to process name
            $aliasName = if ($ExePath) { Split-Path $ExePath -Leaf } else { "$ProcessName.exe" }
            $aliasPath = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\$aliasName"
            
            if (Test-Path $aliasPath) {
                $logTrace.Add("Found execution alias at $aliasPath, launching")
                $null = Start-Process -FilePath $aliasPath -WorkingDirectory (Split-Path $aliasPath) -PassThru -ErrorAction Stop
                if (&$VerifyActive -name $ProcessName) {
                    return @{
                        Started = $true
                        Status  = "Started"
                        Method  = "ExecutionAlias"
                        Log     = $logTrace -join "; "
                    }
                } else {
                    $logTrace.Add("Alias launch spawned process, but it did not appear in memory within 3 seconds")
                }
            }
            else {
                $logTrace.Add("Execution alias not found at $aliasPath")
            }
        }
        catch {
            $logTrace.Add("Alias launch failed: $($_.Exception.Message)")
        }
    }

    # 4. Try Shell Start (via cmd.exe /c start)
    if ($ExePath -and (Test-Path $ExePath)) {
        $logTrace.Add("Shell launch: attempting to run via cmd.exe start")
        try {
            $null = Start-Process "cmd.exe" -ArgumentList "/c start `"`" `"$ExePath`"" -WindowStyle Hidden -PassThru -ErrorAction Stop
            if (&$VerifyActive -name $ProcessName) {
                return @{
                    Started = $true
                    Status  = "Started"
                    Method  = "ShellStart"
                    Log     = $logTrace -join "; "
                }
            } else {
                $logTrace.Add("Shell launch executed, but process did not appear in memory within 3 seconds")
            }
        }
        catch {
            $logTrace.Add("Shell launch failed: $($_.Exception.Message)")
        }
    }

    # 5. Try Protocol Handler Fallback
    if ($ProcessName -eq "Spotify") {
        $logTrace.Add("Protocol handler: invoking spotify: protocol")
        try {
            $null = Start-Process "spotify:" -PassThru -ErrorAction Stop
            if (&$VerifyActive -name $ProcessName) {
                return @{
                    Started = $true
                    Status  = "Started"
                    Method  = "ProtocolHandler"
                    Log     = $logTrace -join "; "
                }
            } else {
                $logTrace.Add("Protocol handler launched, but process did not appear in memory within 3 seconds")
            }
        }
        catch {
            $logTrace.Add("Protocol launch failed: $($_.Exception.Message)")
        }
    }

    # 6. All attempts failed
    return @{
        Started = $false
        Status  = "Failed"
        Log     = $logTrace -join "; "
    }
}