#requires -Version 5.1
# ==============================================================================
# Module: Logic.ps1
# Purpose: Pure business logic functions extracted from UI event handlers.
#          These functions contain no direct UI dependencies (no WinForms
#          controls, no MessageBox calls) so they can be tested in isolation.
# Inputs: Parameters passed explicitly by callers (event handlers or CLI).
# Outputs: Structured result objects (hashtables) that callers use to update UI.
# Error Handling: All functions use try/catch with fail-forward design.
#                 Errors are returned in result objects, never thrown to callers.
# ==============================================================================

# ------------------------------------------
# Install Logic
# ------------------------------------------

function Invoke-SamishInstall {
    <#
    .SYNOPSIS
        Performs SAMISH installation: syncs runtime files, writes config,
        registers event source, installs scheduled tasks, and handles
        power plan compatibility.
    .OUTPUTS
        Hashtable with keys: Success, StatusMessage, StoppedCount
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Mode,

        [Parameter(Mandatory)]
        [string]$OperatingMode,

        [Parameter(Mandatory)]
        [bool]$EnableLogging,

        [Parameter(Mandatory)]
        [int]$LogEverySeconds,

        [Parameter(Mandatory)]
        [bool]$EnableTray,

        [Parameter(Mandatory)]
        [bool]$EnableHotkey,

        [Parameter(Mandatory)]
        [string]$HotkeyMode,

        [Parameter(Mandatory)]
        [int]$CustomHotkeyVk,

        [string]$ActiveProfileId = $null,
        $ProfilesEnabled = $null,
        [bool]$EnableAutoRecovery = $false
    )

    $result = @{
        Success       = $false
        StatusMessage = ""
        PowerPlanResult = $null
    }

    try {
        Sync-SamishRuntimeFiles

        # Compute the persistent setup path inside the install directory.
        # Sync-SamishRuntimeFiles copies the setup file there; we write this
        # persistent path to config.json so it survives reboots.
        $persistentSetupPath = $script:SetupExecutablePath
        if (-not [string]::IsNullOrWhiteSpace($script:SetupExecutablePath)) {
            $setupFileName = [System.IO.Path]::GetFileName($script:SetupExecutablePath)
            $candidateInstalled = Join-Path $InstallDir $setupFileName
            if (Test-Path -LiteralPath $candidateInstalled) {
                $persistentSetupPath = $candidateInstalled
            }

            # Prefer a compiled .exe over a .ps1 script if both exist side-by-side
            # in the install directory. Running Setup.ps1 under PowerShell requires STA
            # threading and module resolution that is not guaranteed from the tray.
            if ($persistentSetupPath -and $persistentSetupPath.EndsWith(".ps1", [System.StringComparison]::OrdinalIgnoreCase)) {
                $exeSibling = [System.IO.Path]::ChangeExtension($persistentSetupPath, ".exe")
                if (Test-Path -LiteralPath $exeSibling) {
                    $persistentSetupPath = $exeSibling
                }
            }
        }

        Write-ConfigJson `
            -EnableLogging:$EnableLogging `
            -LogEverySeconds:$LogEverySeconds `
            -EnableTrayIcon:$EnableTray `
            -EnableHotkey:$EnableHotkey `
            -HotkeyMode:$HotkeyMode `
            -CustomHotkeyVirtualKey:$CustomHotkeyVk `
            -OperatingMode:$OperatingMode `
            -SetupPath:$persistentSetupPath `
            -ActiveProfileId $ActiveProfileId `
            -ProfilesEnabled $ProfilesEnabled `
            -EnableAutoRecovery:$EnableAutoRecovery

        Register-SamishEventSource

        Delete-Task -TaskNameWithSlash $TaskHidden | Out-Null
        Delete-Task -TaskNameWithSlash $TaskInteractive | Out-Null

        $HiddenXmlInstalled = Join-Path $InstallDir "SAMISH-HiddenTask.xml"
        $InteractiveXmlInstalled = Join-Path $InstallDir "SAMISH-InteractiveTask.xml"

        if ($Mode -eq "Hidden") {
            Install-TaskFromXml -TaskNameNoSlash $TaskHiddenNoSlash -XmlPath $HiddenXmlInstalled | Out-Null
            Remove-StartupShortcut
        }
        else {
            Install-TaskFromXml -TaskNameNoSlash $TaskInteractiveNoSlash -XmlPath $InteractiveXmlInstalled | Out-Null
            Remove-StartupShortcut

            Stop-RunningHelperInstances | Out-Null
            Start-Sleep -Milliseconds 300 # measured in ms
            $null = Start-SamishInMode -Mode "Interactive"
        }

        # Handle power plan compatibility
        $ppResult = $null
        if ($OperatingMode -eq "Classic") {
            $ppResult = Apply-PowerPlanFixWithBackup -PromptUser:$true -AutoMode:$true
            $ppResult = Handle-PowerPlanPromptIfNeeded -result $ppResult -AutoMode:$true
        }
        else {
            try {
                $scheme = Get-ActiveSchemeGuid
                if ($scheme) {
                    $displayOff = Get-PowerSettingSecondsAC -SchemeGuid $scheme -SubGuid $SUB_VIDEO -SettingGuid $VIDEOIDLE
                    $sleepIdle = Get-PowerSettingSecondsAC -SchemeGuid $scheme -SubGuid $SUB_SLEEP -SettingGuid $STANDBYIDLE
                    $hibIdle = Get-PowerSettingSecondsAC -SchemeGuid $scheme -SubGuid $SUB_SLEEP -SettingGuid $HIBERNATEIDLE

                    $t = Test-PowerPlanCompatibility `
                        -DisplayOffSeconds $displayOff `
                        -SleepIdleSeconds $sleepIdle `
                        -HibernateIdleSeconds $hibIdle `
                        -GapSeconds $MinGapSeconds

                    if ($t -and (-not $t.Compatible)) {
                        if (Ask-PowerPlanClassicCompatOptIn) {
                            $ppResult = Apply-PowerPlanFixWithBackup -PromptUser:$true -AutoMode:$true
                            $ppResult = Handle-PowerPlanPromptIfNeeded -result $ppResult -AutoMode:$true
                        }
                        else {
                            $ppResult = Get-NoPowerPlanChangesStatus
                        }
                    }
                }
            }
            catch {
                # Best effort only
            }
        }

        $msg = "Install complete.`r`nScheduled task created successfully."
        if ($ppResult -and $ppResult.StatusMessage) { $msg += "`r`n`r`n" + $ppResult.StatusMessage }

        if ($OperatingMode -eq "Graceful" -and $ppResult -and $ppResult.StatusMessage) {
            $generic = [string]$ppResult.StatusMessage
            if ($generic -match '(?i)may prevent SAMISH' -or $generic -match '(?i)functioning as intended') {
                $gracefulNote =
                "Your current power plan is not compatible with SAMISH Classic.

This does not affect Graceful mode.

If you switch to Classic mode, run ""Power Plan: Check / Restore"" to ensure proper behavior."

                $msg = $msg -replace [Regex]::Escape($generic), $gracefulNote
            }
        }

        $result.Success = $true
        $result.StatusMessage = $msg
        $result.PowerPlanResult = $ppResult
    }
    catch {
        $result.Success = $false
        $result.StatusMessage = "Install failed.`r`nSee details below:`r`n$($_.Exception.Message)"
        try { Write-SetupLog ("Install failed: " + $_.Exception.Message) } catch {}
    }

    return $result
}

# ------------------------------------------
# Uninstall Logic
# ------------------------------------------

function Invoke-SamishUninstall {
    <#
    .SYNOPSIS
        Performs SAMISH uninstallation: stops running instances, removes
        scheduled tasks, removes startup shortcuts, and unregisters event source.
    .OUTPUTS
        Hashtable with keys: Success, StatusMessage, StoppedCount, NothingToUninstall
    #>

    $result = @{
        Success            = $false
        StatusMessage      = ""
        StoppedCount       = 0
        NothingToUninstall = $false
    }

    try {
        $hiddenExists = Task-Exists -TaskNameWithSlash $TaskHidden
        $interactiveExists = Task-Exists -TaskNameWithSlash $TaskInteractive
        $shortcutExists = Test-Path -LiteralPath (Get-StartupShortcutPath)

        $proc = Get-SamishProcessInfo
        $runningExists = $proc -and $proc.Running

        if (-not ($hiddenExists -or $interactiveExists -or $shortcutExists -or $runningExists)) {
            $result.NothingToUninstall = $true
            $result.StatusMessage = "Nothing to uninstall.`r`nSAMISH is not currently installed or running."
            try { Write-SetupLog "Uninstall requested: nothing to uninstall." } catch {}
            return $result
        }

        # Stop running task instances first (best effort)
        try {
            if ($interactiveExists) { Stop-SamishTaskIfRunning -Mode "Interactive" }
            if ($hiddenExists) { Stop-SamishTaskIfRunning -Mode "Hidden" }
        }
        catch {}

        # Stop any running engine processes
        $stoppedCount = Stop-RunningHelperInstances
        Start-Sleep -Milliseconds 250 # measured in ms

        # Remove tasks
        Delete-Task -TaskNameWithSlash $TaskHidden | Out-Null
        Delete-Task -TaskNameWithSlash $TaskInteractive | Out-Null

        # Remove any legacy Startup shortcut
        Remove-StartupShortcut

        # Remove Event Log Source
        try {
            if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\SAMISH") {
                [System.Diagnostics.EventLog]::DeleteEventSource("SAMISH")
                try { Write-SetupLog "Unregistered SAMISH Windows Event Log source." } catch {}
            }
        }
        catch {
            try { Write-SetupLog "WARNING: Failed to unregister SAMISH Event Log source: $($_.Exception.Message)" } catch {}
        }

        $result.Success = $true
        $result.StoppedCount = $stoppedCount
        $result.StatusMessage = "Uninstall complete.`r`nStopped $stoppedCount running instance(s)."
        try { Write-SetupLog "Uninstall complete." } catch {}
    }
    catch {
        $result.Success = $false
        $result.StatusMessage = "Uninstall failed.`r`nSee details below:`r`n$($_.Exception.Message)"
        try { Write-SetupLog ("Uninstall failed: " + $_.Exception.Message) } catch {}
    }

    return $result
}

# ------------------------------------------
# Diagnostic Report Compilation
# ------------------------------------------

function Invoke-DiagnosticReportCompilation {
    <#
    .SYNOPSIS
        Compiles a sanitized diagnostic ZIP containing config files,
        power plan backups, log files, and powercfg output.
    .OUTPUTS
        Hashtable with keys: Success, ZipPath, ErrorMessage
    #>

    $result = @{
        Success      = $false
        ZipPath      = ""
        ErrorMessage = ""
    }

    $tempDiagDir = Join-Path $InstallDir "temp_diag"

    try {
        # Prepare temp directory
        try {
            if (Test-Path -LiteralPath $tempDiagDir) {
                Remove-Item -LiteralPath $tempDiagDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            New-Item -ItemType Directory -Path $tempDiagDir -Force | Out-Null
        }
        catch {
            $result.ErrorMessage = "Could not create temporary directory at $tempDiagDir.`r`n`r`nError: $_"
            try { Write-SetupLog "Diagnostics Report error: Failed to prepare temporary directory: $_" } catch {}
            return $result
        }

        # Copy settings config
        try {
            if (Test-Path -LiteralPath $ConfigPath) {
                Copy-Item -LiteralPath $ConfigPath -Destination (Join-Path $tempDiagDir "config.json") -Force
            }
        }
        catch {
            try { Write-SetupLog "Diagnostics Report error: Failed to copy config.json: $_" } catch {}
        }

        # Copy backup configuration if present
        try {
            $backupPath = Join-Path $InstallDir "powerplan_backup.json"
            if (Test-Path -LiteralPath $backupPath) {
                Copy-Item -LiteralPath $backupPath -Destination (Join-Path $tempDiagDir "powerplan_backup.json") -Force
            }
        }
        catch {
            try { Write-SetupLog "Diagnostics Report error: Failed to copy powerplan_backup.json: $_" } catch {}
        }

        # Copy active log files
        try {
            $logFiles = Get-ChildItem -Path $InstallDir -Filter "samish_*.log" -ErrorAction SilentlyContinue
            foreach ($lf in $logFiles) {
                Copy-Item -LiteralPath $lf.FullName -Destination (Join-Path $tempDiagDir $lf.Name) -Force
            }
        }
        catch {
            try { Write-SetupLog "Diagnostics Report error: Failed to copy log files: $_" } catch {}
        }

        # Run powercfg system commands and save outputs
        $commands = @{
            "powercfg_requests.txt"    = "requests"
            "powercfg_lastwake.txt"    = "lastwake"
            "powercfg_waketimers.txt"  = "waketimers"
            "powercfg_wake_armed.txt"  = "devicequery wake_armed"
            "powercfg_a.txt"           = "a"
        }
        foreach ($filename in $commands.Keys) {
            try {
                $arg = $commands[$filename]
                $destPath = Join-Path $tempDiagDir $filename
                Start-Process -FilePath "powercfg.exe" -ArgumentList $arg -NoNewWindow -Wait -RedirectStandardOutput $destPath -ErrorAction SilentlyContinue
            }
            catch {
                try { Write-SetupLog "Diagnostics Report error: Failed to capture powercfg $arg. Error: $_" } catch {}
            }
        }

        # Sanitize copied files
        try {
            $user = $env:USERNAME
            $computer = $env:COMPUTERNAME
            $filesToSanitize = Get-ChildItem -Path $tempDiagDir -File -ErrorAction SilentlyContinue
            foreach ($file in $filesToSanitize) {
                $filePath = $file.FullName
                if (Test-Path -LiteralPath $filePath) {
                    $content = Get-Content -LiteralPath $filePath -Raw -ErrorAction SilentlyContinue
                    if ($content) {
                        if ($user) {
                            $content = $content -replace [regex]::Escape($user), "[user]"
                        }
                        if ($computer) {
                            $content = $content -replace [regex]::Escape($computer), "[computer_name]"
                        }
                        $content = $content -replace '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b', "[local_ip]"

                        Set-Content -LiteralPath $filePath -Value $content -Encoding UTF8 -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
        catch {
            try { Write-SetupLog "Diagnostics Report error: Failed during file sanitization: $_" } catch {}
        }

        # Compress to ZIP archive on Desktop
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $desktopDir = [System.Environment]::GetFolderPath('Desktop')
        $zipPath = Join-Path $desktopDir "SAMISH_Diagnostics_$timestamp.zip"

        try {
            if (Test-Path -LiteralPath $zipPath) {
                Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
            }
            Compress-Archive -Path "$tempDiagDir\*" -DestinationPath $zipPath -Force
        }
        catch {
            try { Write-SetupLog "Diagnostics Report error: Compress-Archive failed, trying shell application fallback: $_" } catch {}
            try {
                $zipHeader = [byte[]]@(80, 75, 5, 6) + (,0 * 18)
                [System.IO.File]::WriteAllBytes($zipPath, $zipHeader)

                $shell = New-Object -ComObject Shell.Application
                $zipFileObj = $shell.NameSpace($zipPath)
                $srcFolderObj = $shell.NameSpace($tempDiagDir)
                $zipFileObj.CopyHere($srcFolderObj.Items())

                $waitTime = 0
                while ($zipFileObj.Items().Count -lt $srcFolderObj.Items().Count -and $waitTime -lt 5000) {
                    Start-Sleep -Milliseconds 200 # measured in ms
                    $waitTime += 200
                }
            }
            catch {
                try { Write-SetupLog "Diagnostics Report error: Shell application fallback failed: $_" } catch {}
            }
        }

        # Clean up temp folder
        try {
            if (Test-Path -LiteralPath $tempDiagDir) {
                Remove-Item -LiteralPath $tempDiagDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            try { Write-SetupLog "Diagnostics Report error: Failed to clean up temporary directory $tempDiagDir. Error: $_" } catch {}
        }

        # Check result
        if (Test-Path -LiteralPath $zipPath) {
            $result.Success = $true
            $result.ZipPath = $zipPath
        }
        else {
            $result.ErrorMessage = "Failed to generate the diagnostic report ZIP file."
        }
    }
    catch {
        $result.ErrorMessage = "Error generating diagnostic report: $($_.Exception.Message)"
        try { Write-SetupLog "Diagnostics Report error: Compilation failed: $_" } catch {}
    }

    return $result
}

# ------------------------------------------
# UI State Parsing Helpers
# ------------------------------------------

function Get-LogIntervalFromUI {
    <#
    .SYNOPSIS
        Resolves the log interval in seconds from the UI dropdown selection text.
    .OUTPUTS
        Int -- the number of seconds between log entries.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$DropdownText,

        [string]$CustomText = "30"
    )

    switch ($DropdownText) {
        "Verbose (every loop)" { return 0 }
        "Every 30 seconds"    { return 30 }
        "Every 60 seconds"    { return 60 }
        default {
            # Custom seconds -- validate via existing parser
            return (Parse-LogEverySecondsOrThrow -RawText $CustomText -ContextLabel "Log interval")
        }
    }
}

function Get-HotkeyVkFromUI {
    <#
    .SYNOPSIS
        Resolves the virtual key code from the UI hotkey dropdown selection.
    .OUTPUTS
        Int -- the virtual key code.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$HotkeyMode,

        [string]$CustomKeyText = ""
    )

    if ($HotkeyMode -eq "Custom") {
        return (Parse-CustomHotkeyToVk $CustomKeyText)
    }
    else {
        return [int]$VkMap[$HotkeyMode]
    }
}
