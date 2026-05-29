# ==========================================
# SAMISH CLI Installer Engine
# ==========================================

function Write-CliLine {
    param([string]$Text = "")
    try { Write-Host $Text } catch {}
}

function Invoke-CliInstallRoute {
    Write-CliLine "SAMISH CLI Install"
    Write-CliLine "InstallMode: $InstallMode"
    Write-CliLine "OperatingMode: $OperatingMode"
    Write-CliLine ""

    try {
        $stoppedCount = Stop-RunningHelperInstances
        if ($stoppedCount -gt 0) { Write-CliLine "Stopped $stoppedCount running SAMISH instance(s) before install." }
        else { Write-CliLine "No running SAMISH instances detected." }
        Write-CliLine ""
    }
    catch {
        Write-CliLine "WARNING: Failed to stop running SAMISH instances: $($_.Exception.Message)"
        Write-CliLine "Proceeding anyway (tasks will still be updated)."
        Write-CliLine ""
    }

    Write-CliLine "Syncing runtime files to %APPDATA%\SAMISH..."
    Sync-SamishRuntimeFiles

    Write-CliLine "Registering Windows Event Log source..."
    Register-SamishEventSource

    $vk = 0x91
    if ($EnableHotkey) {
        try {
            if ($HotkeyMode -eq "Custom") { $vk = Parse-CustomHotkeyToVk $CustomHotkey }
            else { $vk = [int]$VkMap[$HotkeyMode] }
        }
        catch {
            Write-CliLine "WARNING: Hotkey parsing failed ($($_.Exception.Message)). Hotkey will be disabled."
            $EnableHotkey = $false
            $vk = 0x91
        }
    }

    if ($InstallMode -eq "Hidden") {
        if ($EnableTrayIcon -or $EnableHotkey) {
            Write-CliLine "NOTE: Hidden mode selected. Tray icon / hotkey state will be written as-configured."
        }
        # Tray icon and hotkey are optional; respect the value from config or CLI flags.
        # Do NOT force-disable here - the GUI and config are the source of truth.
    }

    Write-CliLine "Writing config.json (explicit CLI configuration)..."
    Write-ConfigJson `
        -EnableLogging:$([bool]$EnableLogging) `
        -LogEverySeconds:$([int]$LogEverySeconds) `
        -EnableTrayIcon:$([bool]$EnableTrayIcon) `
        -EnableHotkey:$([bool]$EnableHotkey) `
        -HotkeyMode:$HotkeyMode `
        -CustomHotkeyVirtualKey:$vk `
        -OperatingMode:$OperatingMode `
        -SetupPath:$script:SetupExecutablePath `
        -EnableAutoRecovery:$EnableAutoRecovery

    Write-CliLine "Installing Scheduled Task..."
    Delete-Task -TaskNameWithSlash $TaskHidden | Out-Null
    Delete-Task -TaskNameWithSlash $TaskInteractive | Out-Null

    $HiddenXmlInstalled = Join-Path $InstallDir "SAMISH-HiddenTask.xml"
    $InteractiveXmlInstalled = Join-Path $InstallDir "SAMISH-InteractiveTask.xml"

    if ($InstallMode -eq "Hidden") {
        Install-TaskFromXml -TaskNameNoSlash $TaskHiddenNoSlash -XmlPath $HiddenXmlInstalled | Out-Null
        Remove-StartupShortcut
    }
    else {
        Install-TaskFromXml -TaskNameNoSlash $TaskInteractiveNoSlash -XmlPath $InteractiveXmlInstalled | Out-Null
        Remove-StartupShortcut 
    }

    Write-CliLine "Install complete."
    Write-CliLine ""
    Write-CliLine "Done."
}
