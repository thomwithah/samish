#requires -Version 5.1
# ==============================================================================
# Module: Events.DiagnosticsTests.ps1
# Purpose: Operating Mode test functions and event handlers for the
#          Test Sleep, Test Hibernate, Test Stop, and Refresh buttons on
#          the Diagnostics tab Page 2.
# Inputs: Script-scoped variables from Events.Diagnostics.ps1 (dot-sourced).
# Outputs: None (modifies form state, starts/stops processes for testing).
# Error Handling: All button handlers wrapped in try/catch with status updates.
# ==============================================================================

# Operating Mode Tests -- Event Wiring
# ============================================================

# ---- Resolve-TestTarget -------------------------------------
# Reads the selected item from the test target dropdown and returns a
# structured object with everything the three button handlers need.
# Callers must check .Valid before using any other field.
function Resolve-TestTarget {
    try {
        if (-not $script:ddTestTarget -or $script:ddTestTarget.SelectedIndex -lt 0) {
            return [pscustomobject]@{
                Valid             = $false
                Error             = "No target selected in the dropdown."
                IsDeviceSoftware  = $false
                ProcessName       = ""
                ConfiguredPath    = ""
                DisplayName       = ""
                WindowWakeDelayMs = 800
                ShutdownWaitMs    = 800
            }
        }

        $selected = [string]$script:ddTestTarget.SelectedItem

        # ---- Device Software target ----
        if ($selected -like "Device Software:*") {

            $procName = ""
            $configPath = ""
            $regSearch = ""
            $displayName = $selected
            $gracefulWake = 800
            $gracefulWait = 800

            try {
                if ($script:ProfileMetaById -and
                    $script:ProfileMetaById.ContainsKey($script:ActiveProfileId)) {
                    $meta = $script:ProfileMetaById[$script:ActiveProfileId]

                    $displayName = $meta.DisplayName

                    if ($meta.Raw.targets -and $meta.Raw.targets.Count -gt 0) {
                        $t = $meta.Raw.targets[0]
                        $procName = [string]$t.processName
                        $configPath = if ($t.PSObject.Properties["defaultExePath"]) { [string]$t.defaultExePath } else { "" }
                        $regSearch = if ($t.PSObject.Properties["registrySearchString"]) { [string]$t.registrySearchString } else { $procName }
                    }

                    # Pull timing defaults from the profile if present
                    if ($meta.Raw.PSObject.Properties["gracefulWindowWakeDelayMs"]) {
                        try { $gracefulWake = [int]$meta.Raw.gracefulWindowWakeDelayMs } catch {}
                    }
                    if ($meta.Raw.PSObject.Properties["gracefulShutdownWaitMs"]) {
                        try { $gracefulWait = [int]$meta.Raw.gracefulShutdownWaitMs } catch {}
                    }
                }
            }
            catch {
                # Profile metadata read failed - fall back to empty strings; the
                # caller will surface a useful error via Get-AppExecutablePath.
                Write-SetupLog "Resolve-TestTarget: profile metadata read error: $($_.Exception.Message)"
            }

            if (-not $procName) {
                return [pscustomobject]@{
                    Valid             = $false
                    Error             = "Could not resolve a process name from the selected profile."
                    IsDeviceSoftware  = $true
                    ProcessName       = ""
                    ConfiguredPath    = ""
                    DisplayName       = $displayName
                    WindowWakeDelayMs = $gracefulWake
                    ShutdownWaitMs    = $gracefulWait
                }
            }

            # Resolve the best available executable path (Config > Running process > Registry)
            $pathResult = $null
            if (Get-Command Get-AppExecutablePath -ErrorAction SilentlyContinue) {
                try {
                    $pathResult = Get-AppExecutablePath `
                        -ProcessName $procName `
                        -ConfiguredPath $configPath `
                        -RegistrySearchString $regSearch
                }
                catch {
                    Write-SetupLog "Resolve-TestTarget: Get-AppExecutablePath threw: $($_.Exception.Message)"
                }
            }

            $resolvedPath = if ($pathResult -and $pathResult.IsValid) { $pathResult.Path } else { $configPath }

            return [pscustomobject]@{
                Valid             = $true
                Error             = ""
                IsDeviceSoftware  = $true
                ProcessName       = $procName
                ConfiguredPath    = $resolvedPath
                DisplayName       = $displayName
                WindowWakeDelayMs = $gracefulWake
                ShutdownWaitMs    = $gracefulWait
                BeforeSleepMode   = $script:OperatingMode
                OnWakeAction      = "Smart"
            }
        }

        # ---- Automated App target ----
        if ($selected -like "Automated App:*") {

            $targetProcName = $selected.Replace("Automated App:", "").Trim()

            $app = $null
            if ($script:MonitoredApps) {
                $app = $script:MonitoredApps | Where-Object { $_.ProcessName -eq $targetProcName } | Select-Object -First 1
            }

            if (-not $app) {
                return [pscustomobject]@{
                    Valid             = $false
                    Error             = "Automated app '$targetProcName' not found in the current MonitoredApps list. Try reopening the test group."
                    IsDeviceSoftware  = $false
                    ProcessName       = $targetProcName
                    ConfiguredPath    = ""
                    DisplayName       = $targetProcName
                    WindowWakeDelayMs = 800
                    ShutdownWaitMs    = 800
                }
            }

            $exePath = if ($app.PSObject.Properties["ExecutablePath"]) { [string]$app.ExecutablePath } else { "" }

            # Resolve path using Get-AppExecutablePath helper
            $resolvedPath = $exePath
            if (Get-Command Get-AppExecutablePath -ErrorAction SilentlyContinue) {
                try {
                    $pathResult = Get-AppExecutablePath -ProcessName $app.ProcessName -ConfiguredPath $exePath
                    if ($pathResult -and $pathResult.IsValid) {
                        $resolvedPath = $pathResult.Path
                    }
                }
                catch {
                    Write-SetupLog "Resolve-TestTarget: Get-AppExecutablePath threw for Automated App: $($_.Exception.Message)"
                }
            }

            $beforeSleepMode = if ($app.RecoveryMode) { $app.RecoveryMode } else { $script:OperatingMode }
            $onWakeAction = if ($app.PSObject.Properties['OnWakeAction']) { $app.OnWakeAction } else { "Smart" }

            return [pscustomobject]@{
                Valid             = $true
                Error             = ""
                IsDeviceSoftware  = $false
                ProcessName       = $app.ProcessName
                ConfiguredPath    = $resolvedPath
                DisplayName       = $app.ProcessName
                WindowWakeDelayMs = 800
                ShutdownWaitMs    = 800
                BeforeSleepMode   = $beforeSleepMode
                OnWakeAction      = $onWakeAction
            }
        }

        # Fallback: the item did not match either known prefix
        return [pscustomobject]@{
            Valid             = $false
            Error             = "Unrecognised target format: '$selected'."
            IsDeviceSoftware  = $false
            ProcessName       = ""
            ConfiguredPath    = ""
            DisplayName       = $selected
            WindowWakeDelayMs = 800
            ShutdownWaitMs    = 800
        }
    }
    catch {
        Write-SetupLog "Resolve-TestTarget: unexpected error: $($_.Exception.Message)"
        return [pscustomobject]@{
            Valid             = $false
            Error             = "Unexpected error resolving target: $($_.Exception.Message)"
            IsDeviceSoftware  = $false
            ProcessName       = ""
            ConfiguredPath    = ""
            DisplayName       = ""
            WindowWakeDelayMs = 800
            ShutdownWaitMs    = 800
        }
    }
}

# ---- Update-TestButtonsTooltips --------------------------------------
# Evaluates SAMISH installation, active profile, and process running states
# to update the tooltips for the four diagnostic test buttons on Page 2.
function Update-TestButtonsTooltips {
    # Check general group availability
    $isInstalled = $false
    $deviceRunning = $false
    $hasAutomated = ($script:MonitoredApps -and $script:MonitoredApps.Count -gt 0)
    try { $isInstalled = Test-SamishInstalled } catch {}

    $profileProcName = $null
    try {
        if ($script:ProfileMetaById -and $script:ProfileMetaById.ContainsKey($script:ActiveProfileId)) {
            $meta = $script:ProfileMetaById[$script:ActiveProfileId]
            if ($meta.Raw.targets -and $meta.Raw.targets.Count -gt 0) {
                $profileProcName = [string]$meta.Raw.targets[0].processName
            }
        }
    }
    catch {}
    if ($profileProcName) {
        try {
            $deviceRunning = ($null -ne (Get-Process -Name $profileProcName -ErrorAction SilentlyContinue | Select-Object -First 1))
        }
        catch {}
    }

    $groupAvailable = ($isInstalled -or $hasAutomated -or $deviceRunning)

    # Base tooltips
    $baseSleep = "Test whether SAMISH can close this application or pause its media playback based on its configured sleep action."
    $baseWake = "Test whether SAMISH can launch this application and/or restore its media playback status based on its configured wake action."
    $baseGraceful = "Test close app (graceful) behavior, forcing a WM_CLOSE command to ask the application to close cleanly."
    $baseForce = "Test close app (classic) behavior, forcing immediate process termination."

    if (-not $groupAvailable) {
        $reason = "[Unavailable - Requires SAMISH to be installed, the active profile's device software to be running, or automated apps configured.]"
        $tipSleep = "$reason`r`n`r`n$baseSleep"
        $tipWake = "$reason`r`n`r`n$baseWake"
        $tipGraceful = "$reason`r`n`r`n$baseGraceful"
        $tipForce = "$reason`r`n`r`n$baseForce"
    }
    else {
        $target = Resolve-TestTarget
        if (-not $target.Valid) {
            $reason = "[Unavailable - No valid target selected in dropdown]"
            $tipSleep = "$reason`r`n`r`n$baseSleep"
            $tipWake = "$reason`r`n`r`n$baseWake"
            $tipGraceful = "$reason`r`n`r`n$baseGraceful"
            $tipForce = "$reason`r`n`r`n$baseForce"
        }
        else {
            $proc = Get-Process -Name $target.ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
            $running = $null -ne $proc

            if ($running) {
                $statusSleep = "[Available - Target is running]"
                $statusGraceful = "[Available - Target is running]"
                $statusForce = "[Available - Target is running]"

                if ($target.BeforeSleepMode -eq "PauseMedia") {
                    $statusWake = "[Available - Target is running (testing playback resumption)]"
                    $guidanceWake = "This will test media playback resumption on the running application."
                }
                else {
                    $statusWake = "[Unavailable - Target is running. Click 'Test Sleep/Hibernate' first.]"
                    $guidanceWake = "The application must be stopped before testing the launch action."
                }

                $guidanceSleep = "Warning: This test will attempt to close or pause the running application."
                $guidanceGraceful = "Warning: This test will attempt to gracefully close the running application."
                $guidanceForce = "Warning: This test will force-terminate the running application."

                $tipSleep = "$statusSleep`r`n`r`n$baseSleep`r`n`r`n$guidanceSleep"
                $tipWake = "$statusWake`r`n`r`n$baseWake`r`n`r`n$guidanceWake"
                $tipGraceful = "$statusGraceful`r`n`r`n$baseGraceful`r`n`r`n$guidanceGraceful"
                $tipForce = "$statusForce`r`n`r`n$baseForce`r`n`r`n$guidanceForce"
            }
            else {
                $statusSleep = "[Unavailable - Target is not running. Click 'Test Wake/Resume' first.]"
                $statusGraceful = "[Unavailable - Target is not running. Click 'Test Wake/Resume' first.]"
                $statusForce = "[Unavailable - Target is not running. Click 'Test Wake/Resume' first.]"
                
                $statusWake = "[Available - Target is not running]"

                $guidanceSleep = "The application must be running to test sleep actions."
                $guidanceGraceful = "The application must be running to test graceful close."
                $guidanceForce = "The application must be running to test force close."
                
                $pathText = if ($target.ConfiguredPath) { $target.ConfiguredPath } else { "(Auto-detect on launch)" }
                $guidanceWake = "This will attempt to launch the application using its configured path: $pathText"

                $tipSleep = "$statusSleep`r`n`r`n$baseSleep`r`n`r`n$guidanceSleep"
                $tipWake = "$statusWake`r`n`r`n$baseWake`r`n`r`n$guidanceWake"
                $tipGraceful = "$statusGraceful`r`n`r`n$baseGraceful`r`n`r`n$guidanceGraceful"
                $tipForce = "$statusForce`r`n`r`n$baseForce`r`n`r`n$guidanceForce"
            }
        }
    }

    # Set tooltips dynamically
    if ($script:btnTestStop) { $script:tooltip.SetToolTip($script:btnTestStop, $tipSleep) }
    if ($script:btnTestStart) { $script:tooltip.SetToolTip($script:btnTestStart, $tipWake) }
    if ($script:btnTestGraceful) { $script:tooltip.SetToolTip($script:btnTestGraceful, $tipGraceful) }
    if ($script:btnTestClassic) { $script:tooltip.SetToolTip($script:btnTestClassic, $tipForce) }
}

# ---- Test Graceful Stop -------------------------------------
$script:btnTestGraceful.add_Click({
        try {
            $target = Resolve-TestTarget

            if (-not $target.Valid) {
                $msg = "Cannot run test: $($target.Error)"
                Set-StatusText $msg
                Write-SetupLog "Operating Mode Test (Graceful): $msg"
                return
            }

            # Check whether the app is currently running before calling Graceful stop.
            $proc = Get-Process -Name $target.ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $proc) {
                $msg = "$($target.DisplayName) is not currently running. Nothing to stop."
                Set-StatusText $msg
                Write-SetupLog "Operating Mode Test (Graceful): $msg"
                return
            }

            Set-StatusText "Running Graceful Stop test on $($target.DisplayName)..."
            Write-SetupLog "Operating Mode Test (Graceful): starting test on $($target.DisplayName) (process: $($target.ProcessName))"

            if (-not (Get-Command Invoke-AppStopGraceful -ErrorAction SilentlyContinue)) {
                $msg = "Invoke-AppStopGraceful is not available in this session. The Graceful module may not have loaded."
                Set-StatusText $msg
                Write-SetupLog "Operating Mode Test (Graceful): $msg"
                return
            }

            $r = Invoke-AppStopGraceful `
                -ProcessName       $target.ProcessName `
                -ConfiguredPath    $target.ConfiguredPath `
                -WindowWakeDelayMs $target.WindowWakeDelayMs `
                -ShutdownWaitMs    $target.ShutdownWaitMs

            # Build a human-readable result line.
            $method = if ($r -and $r.Method) { [string]$r.Method } else { "Unknown" }
            $stopped = ($r -and $r.Stopped -eq $true)
            $errTxt = if ($r -and $r.Error) { [string]$r.Error } else { "" }

            if ($stopped) {
                $msg = "Graceful Stop test PASSED for $($target.DisplayName). Method: $method."
            }
            else {
                $msg = "Graceful Stop test did not confirm a clean stop for $($target.DisplayName). Method: $method."
                if ($errTxt) { $msg += " $errTxt" }
            }

            # Informational note when the SAMISH engine is installed (no blocking).
            if (Test-SamishInstalled) {
                $msg += "`r`n`r`nNote: SAMISH engine is installed and running. Tests are safe during active use. The engine only triggers when your system has been idle for an extended period."
            }

            Set-StatusText $msg
            Write-SetupLog "Operating Mode Test (Graceful): $msg"
        }
        catch {
            $errMsg = "Graceful Stop test encountered an unexpected error: $($_.Exception.Message)"
            Set-StatusText $errMsg
            Write-SetupLog "Operating Mode Test (Graceful): $errMsg"
        }
        finally {
            Update-TestButtonsTooltips
        }
    })

# ---- Test Classic Stop --------------------------------------
$script:btnTestClassic.add_Click({
        try {
            $target = Resolve-TestTarget

            if (-not $target.Valid) {
                $msg = "Cannot run test: $($target.Error)"
                Set-StatusText $msg
                Write-SetupLog "Operating Mode Test (Classic): $msg"
                return
            }

            # Check whether the app is currently running before calling Classic stop.
            $proc = Get-Process -Name $target.ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $proc) {
                $msg = "$($target.DisplayName) is not currently running. Nothing to stop."
                Set-StatusText $msg
                Write-SetupLog "Operating Mode Test (Classic): $msg"
                return
            }

            Set-StatusText "Running Classic Stop test on $($target.DisplayName)..."
            Write-SetupLog "Operating Mode Test (Classic): starting test on $($target.DisplayName) (process: $($target.ProcessName))"

            if (-not (Get-Command Invoke-AppStop -ErrorAction SilentlyContinue)) {
                $msg = "Invoke-AppStop is not available in this session. The Classic module may not have loaded."
                Set-StatusText $msg
                Write-SetupLog "Operating Mode Test (Classic): $msg"
                return
            }

            $r = Invoke-AppStop -ProcessName $target.ProcessName

            $stopped = ($r -and $r.Stopped -eq $true)
            $status = if ($r -and $r.Status) { [string]$r.Status } else { "Unknown" }

            if ($stopped) {
                $msg = "Classic Stop test PASSED for $($target.DisplayName). Status: $status."
            }
            else {
                $msg = "Classic Stop test did not confirm a stop for $($target.DisplayName). Status: $status."
            }

            # Informational note when the SAMISH engine is installed (no blocking).
            if (Test-SamishInstalled) {
                $msg += "`r`n`r`nNote: SAMISH engine is installed and running. Tests are safe during active use. The engine only triggers when your system has been idle for an extended period."
            }

            Set-StatusText $msg
            Write-SetupLog "Operating Mode Test (Classic): $msg"
        }
        catch {
            $errMsg = "Classic Stop test encountered an unexpected error: $($_.Exception.Message)"
            Set-StatusText $errMsg
            Write-SetupLog "Operating Mode Test (Classic): $errMsg"
        }
        finally {
            Update-TestButtonsTooltips
        }
    })

# ---- Start Test ----------------------------------------------
$script:btnTestStart.add_Click({
        try {
            $target = Resolve-TestTarget

            if (-not $target.Valid) {
                $msg = "Cannot run test: $($target.Error)"
                Set-StatusText $msg
                Write-SetupLog "Operating Mode Test (Start): $msg"
                return
            }

            # If configured for PauseMedia and already running, test playback resumption directly
            $proc = Get-Process -Name $target.ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($proc) {
                if ($target.BeforeSleepMode -eq "PauseMedia") {
                    Set-StatusText "Relaunch not required ($($target.DisplayName) is running). Testing Media Play action..."
                    $resumed = Invoke-SmtcActionForProcess -ProcessName $target.ProcessName -Action "Play"
                    if ($resumed) {
                        $msg = "Start Test PASSED for $($target.DisplayName) (Media Play command succeeded)."
                    }
                    else {
                        $msg = "Start Test did not confirm playback for $($target.DisplayName) (SMTC play command failed or no session found)."
                    }
                    Set-StatusText $msg
                    Write-SetupLog "Operating Mode Test (Start): $msg"
                    return
                }
                else {
                    $msg = "$($target.DisplayName) is already running. Click 'Stop Test' first, then click 'Start Test' to verify it relaunches."
                    Set-StatusText $msg
                    Write-SetupLog "Operating Mode Test (Start): $msg"
                    return
                }
            }

            # A valid executable path is required to start the app.
            if (-not $target.ConfiguredPath -or -not (Test-Path -LiteralPath $target.ConfiguredPath -ErrorAction SilentlyContinue)) {
                $pathMsg = "SAMISH could not locate the executable for $($target.DisplayName)."
                if ($target.ConfiguredPath) {
                    $pathMsg += "`r`n`r`nPath tried: $($target.ConfiguredPath)"
                }
                $pathMsg += "`r`n`r`nIf the application is currently installed, try launching it once so SAMISH can detect it, then re-run the Start test."
                Write-SetupLog "Operating Mode Test (Start): path not found for $($target.DisplayName). Path tried: $($target.ConfiguredPath)"
                try {
                    Show-WarningDialog -Title "SAMISH - Start Test: Path Not Found" -Message $pathMsg
                }
                catch {
                    Set-StatusText $pathMsg
                }
                return
            }

            $infoMsg = "Running Start Test for $($target.DisplayName)..."
            if ($target.OnWakeAction -eq "Smart") {
                $smartNote = "Since the Start Test button runs in an ad-hoc test context (outside of actual system sleep/wake transitions), it does not have a real pre-sleep state. For the test, if the wake action is configured as Smart Restore, the test will assume the app was playing and attempt playback restoration."
                $infoMsg = "$smartNote`r`n`r`nRunning Start Test (Smart Restore: assuming pre-sleep playback state was playing) for $($target.DisplayName)..."
                Write-SetupLog "Operating Mode Test (Start): $smartNote"
            }
            Set-StatusText $infoMsg
            Write-SetupLog "Operating Mode Test (Start): starting test for $($target.DisplayName) (process: $($target.ProcessName), path: $($target.ConfiguredPath))"

            if (-not (Get-Command Invoke-AppStart -ErrorAction SilentlyContinue)) {
                $msg = "Invoke-AppStart is not available in this session. The Classic module may not have loaded."
                Set-StatusText $msg
                Write-SetupLog "Operating Mode Test (Start): $msg"
                return
            }

            $r = Invoke-AppStart -ProcessName $target.ProcessName -ExePath $target.ConfiguredPath

            $started = ($r -and $r.Started -eq $true)
            $status = if ($r -and $r.Status) { [string]$r.Status } else { "Unknown" }
            $method = if ($r -and $r.Method) { [string]$r.Method } else { "" }
            $trace = if ($r -and $r.Log) { [string]$r.Log } else { "" }

            if ($started) {
                $msg = "Start Test PASSED for $($target.DisplayName). Status: $status"
                if ($method) { $msg += " (Method: $method)" }
                $msg += "."

                # If the app has Media Control, try to send the Play command to complete the wake test
                $shouldPlay = ($target.OnWakeAction -eq "Play" -or $target.OnWakeAction -eq "Smart")
                if ($shouldPlay) {
                    Write-SetupLog "Operating Mode Test (Start): polling SMTC session to send Play command (up to 15 seconds, retrying every 250 ms)."
                    $sessionFound = $false
                    $playConfirmed = $false
                    $processCrashed = $false

                    for ($i = 0; $i -lt 60; $i++) {
                        # Early Exit: Check if process is still running
                        $currentProc = Get-Process -Name $target.ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
                        if (-not $currentProc) {
                            $processCrashed = $true
                            break
                        }

                        $session = Get-SmtcSessionForProcess -ProcessName $target.ProcessName
                        if ($session) {
                            $sessionFound = $true
                            
                            # Send Play command
                            $resumed = Invoke-SmtcActionForProcess -ProcessName $target.ProcessName -Action "Play"
                            
                            # Sleep for 250 ms to allow playback state to transition
                            for ($s = 0; $s -lt 5; $s++) {
                                Start-Sleep -Milliseconds 50
                                try { [System.Windows.Forms.Application]::DoEvents() } catch {}
                            }
                            
                            # Verify playback state
                            $statusVal = Get-SmtcPlaybackStatus -ProcessName $target.ProcessName
                            if ($statusVal -eq 4) {
                                $playConfirmed = $true
                                break
                            }
                        }
                        else {
                            # Wait 250 ms before checking again
                            for ($s = 0; $s -lt 5; $s++) {
                                Start-Sleep -Milliseconds 50
                                try { [System.Windows.Forms.Application]::DoEvents() } catch {}
                            }
                        }
                    }

                    $loops = if ($i -ge 60) { 60 } else { $i + 1 }
                    $elapsedMs = $loops * 250
                    $timeString = if ($elapsedMs -lt 1000) { "$elapsedMs ms" } else { "$([math]::Round($elapsedMs / 1000, 2)) seconds" }

                    if ($processCrashed) {
                        $msg += " Media play failed because the application process exited or crashed during startup."
                    }
                    elseif ($playConfirmed) {
                        $logMsg = "Media Control Confirmed via SMTC after $loops loops ($timeString)."
                        Write-SetupLog "Operating Mode Test (Start): $logMsg"
                        $msg += " $logMsg"
                    }
                    elseif ($sessionFound) {
                        $msg += " Media play command sent but playback state could not be confirmed within 15 seconds ($loops loops tried)."
                    }
                    else {
                        $msg += " Warning: SMTC session not found within 15 seconds to resume playback ($loops loops tried)."
                    }
                }

                if ($method -ne "Direct" -and $trace) {
                    $msg += "`r`n`r`nDiagnostic Trace:"
                    foreach ($step in $trace.Split(";")) {
                        $trimmed = $step.Trim()
                        if ($trimmed) { $msg += "`r`n- $trimmed" }
                    }
                }
            }
            elseif ($status -eq "AlreadyRunning") {
                $msg = "$($target.DisplayName) started (or was already running) by the time the launch command fired. Status: $status."
            }
            elseif ($status -eq "PathInvalid") {
                $msg = "Start Test could not launch $($target.DisplayName). The executable path was not found or is invalid."
            }
            else {
                $msg = "Start Test did not confirm a launch for $($target.DisplayName). Status: $status."
                if ($trace) {
                    $msg += "`r`n`r`nDiagnostic Trace:"
                    foreach ($step in $trace.Split(";")) {
                        $trimmed = $step.Trim()
                        if ($trimmed) { $msg += "`r`n- $trimmed" }
                    }
                }
            }

            # Retain the Smart Restore note in the final status bar message if applicable (prepended for logical/chronological flow)
            if ($target.OnWakeAction -eq "Smart") {
                $msg = "Note: Since the Start Test button runs in an ad-hoc test context (outside of actual system sleep/wake transitions), it does not have a real pre-sleep state. For the test, if the wake action is configured as Smart Restore, the test will assume the app was playing and attempt playback restoration.`r`n`r`n$msg"
            }

            # Informational note when the SAMISH engine is installed (no blocking).
            if (Test-SamishInstalled) {
                $msg += "`r`n`r`nNote: SAMISH engine is installed and running. Tests are safe during active use. The engine only triggers when your system has been idle for an extended period."
            }

            Set-StatusText $msg
            Write-SetupLog "Operating Mode Test (Start): $msg"
        }
        catch {
            $errMsg = "Start Test encountered an unexpected error: $($_.Exception.Message)"
            Set-StatusText $errMsg
            Write-SetupLog "Operating Mode Test (Start): $errMsg"
        }
        finally {
            Update-TestButtonsTooltips
        }
    })

# ---- Stop Test -----------------------------------------------
$script:btnTestStop.add_Click({
        try {
            $target = Resolve-TestTarget

            if (-not $target.Valid) {
                $msg = "Cannot run test: $($target.Error)"
                Set-StatusText $msg
                Write-SetupLog "Operating Mode Test (Stop): $msg"
                return
            }

            # App must be running to test stop/pause actions
            $proc = Get-Process -Name $target.ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $proc) {
                $msg = "$($target.DisplayName) is not currently running. Nothing to stop."
                Set-StatusText $msg
                Write-SetupLog "Operating Mode Test (Stop): $msg"
                return
            }

            # Run the configured before-sleep stop/pause action
            $mode = $target.BeforeSleepMode
            Set-StatusText "Running Stop Test ($mode) on $($target.DisplayName)..."
            Write-SetupLog "Operating Mode Test (Stop): starting stop test ($mode) on $($target.DisplayName)"

            if ($mode -eq "PauseMedia") {
                $paused = Invoke-SmtcActionForProcess -ProcessName $target.ProcessName -Action "Pause"
                if ($paused) {
                    $msg = "Stop Test PASSED for $($target.DisplayName) (Media successfully paused)."
                }
                else {
                    $msg = "Stop Test did not confirm media pause for $($target.DisplayName) (SMTC pause command failed or no session found)."
                }
            }
            elseif ($mode -eq "Graceful") {
                if (-not (Get-Command Invoke-AppStopGraceful -ErrorAction SilentlyContinue)) {
                    $msg = "Invoke-AppStopGraceful is not available in this session. The Graceful module may not have loaded."
                    Set-StatusText $msg
                    return
                }
                $r = Invoke-AppStopGraceful `
                    -ProcessName       $target.ProcessName `
                    -ConfiguredPath    $target.ConfiguredPath `
                    -WindowWakeDelayMs $target.WindowWakeDelayMs `
                    -ShutdownWaitMs    $target.ShutdownWaitMs
                $method = if ($r -and $r.Method) { [string]$r.Method } else { "Unknown" }
                $stopped = ($r -and $r.Stopped -eq $true)
                $errTxt = if ($r -and $r.Error) { [string]$r.Error } else { "" }
                if ($stopped) {
                    $msg = "Stop Test PASSED for $($target.DisplayName) (Graceful close succeeded via $method)."
                }
                else {
                    $msg = "Stop Test did not confirm a clean stop for $($target.DisplayName). Method: $method."
                    if ($errTxt) { $msg += " $errTxt" }
                }
            }
            else {
                # Classic mode fallback
                if (-not (Get-Command Invoke-AppStop -ErrorAction SilentlyContinue)) {
                    $msg = "Invoke-AppStop is not available in this session. The Classic module may not have loaded."
                    Set-StatusText $msg
                    return
                }
                $r = Invoke-AppStop -ProcessName $target.ProcessName
                $stopped = ($r -and $r.Stopped -eq $true)
                $status = if ($r -and $r.Status) { [string]$r.Status } else { "Unknown" }
                if ($stopped) {
                    $msg = "Stop Test PASSED for $($target.DisplayName) (Classic close succeeded. Status: $status)."
                }
                else {
                    $msg = "Stop Test did not confirm a stop for $($target.DisplayName). Status: $status."
                }
            }

            # Informational note when the SAMISH engine is installed (no blocking).
            if (Test-SamishInstalled) {
                $msg += "`r`n`r`nNote: SAMISH engine is installed and running. Tests are safe during active use. The engine only triggers when your system has been idle for an extended period."
            }

            Set-StatusText $msg
            Write-SetupLog "Operating Mode Test (Stop): $msg"
        }
        catch {
            $errMsg = "Stop Test encountered an unexpected error: $($_.Exception.Message)"
            Set-StatusText $errMsg
            Write-SetupLog "Operating Mode Test (Stop): $errMsg"
        }
        finally {
            Update-TestButtonsTooltips
        }
    })
