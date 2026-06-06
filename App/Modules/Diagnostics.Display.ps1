#requires -Version 5.1
# ==============================================================================
# Module: Diagnostics.Display.ps1
# Purpose: Diagnostics header builder, process/task query info, and
#          current-configuration display for the Setup UI status panel.
#          Extracted from Setup.ps1 to reduce its size.
# Inputs: Consumed by Events.Setup.ps1 via dot-sourcing from Setup.ps1.
# Outputs: Formatted diagnostics text written to the statusBox control.
# Error Handling: try/catch with fail-forward for all system queries.
# ==============================================================================

# ---------- Diagnostics Header ----------
function Get-TaskQueryInfo {
    param([string]$TaskNameNoSlash)

    $r = Run-Schtasks ("/Query /TN `"$TaskNameNoSlash`"")
    if ($r.ExitCode -ne 0) { return @{ Exists = $false; Status = "Missing" } }

    $status = "Unknown"
    $m = [Regex]::Match($r.StdOut, "(?im)^\s*Status:\s*(.+?)\s*$")
    if ($m.Success) { $status = $m.Groups[1].Value.Trim() }

    return @{ Exists = $true; Status = $status }
}

function Get-SamishProcessInfo {
    # Primary: match by CommandLine (works when CIM can read it)
    $procs = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -and (
            $_.CommandLine -match "SAMISH\\.ps1" -or
            ($InstalledEnginePath -and ($_.CommandLine -like "*$InstalledEnginePath*"))
        )
    }

    # Fallback: PID file (CIM returns null CommandLine for elevated Task Scheduler processes)
    if (-not $procs) {
        $pidFile = Join-Path $InstallDir "samish.pid"
        if (Test-Path -LiteralPath $pidFile) {
            try {
                $savedPid = [int](Get-Content -LiteralPath $pidFile -Raw).Trim()
                $proc = Get-Process -Id $savedPid -ErrorAction SilentlyContinue
                if ($proc -and $proc.ProcessName -eq "powershell") {
                    return @{ Running = $true; Count = 1; Pids = @($savedPid) }
                }
            } catch {}
        }
    }

    if (-not $procs) { return @{ Running = $false; Count = 0; Pids = @() } }
    $pids = @($procs | ForEach-Object { $_.ProcessId })
    return @{ Running = $true; Count = $pids.Count; Pids = $pids }
}
function Build-DiagnosticsHeader {
    param(
        [string]$Context = "",
        [string]$Mode = "",
        [bool]$IncludePowerPlan = $true
    )

    $shortcutPath = Get-StartupShortcutPath
    $shortcutPresent = Test-Path -LiteralPath $shortcutPath

    $hiddenTask = Get-TaskQueryInfo -TaskNameNoSlash $TaskHiddenNoSlash
    $interactiveTask = Get-TaskQueryInfo -TaskNameNoSlash $TaskInteractiveNoSlash
    $proc = Get-SamishProcessInfo

    $powerLine = ""
    if ($IncludePowerPlan) {
        $scheme = $null
        try { $scheme = Get-ActiveSchemeGuid } catch { $scheme = $null }
        $powerLine = if ($scheme) { Get-PowerPlanDiagnosticsText -SchemeGuid $scheme } else { "" }
    }

    # Load config
    $cfg = $null
    if (Test-Path -LiteralPath $ConfigPath) {
        try { $cfg = (Get-Content -LiteralPath $ConfigPath -Raw) | ConvertFrom-Json } catch {}
    }

    $installed = ($hiddenTask.Exists -or $interactiveTask.Exists)

    # Infer install mode (prefer actual task reality, then config intent)
    if ([string]::IsNullOrWhiteSpace($Mode)) {
        try {
            if ($interactiveTask.Exists) { $Mode = "Interactive" }
            elseif ($hiddenTask.Exists) { $Mode = "Hidden" }
        }
        catch {}
    }

    if ([string]::IsNullOrWhiteSpace($Mode) -and $cfg) {
        try {
            $tray = $false
            $hot = $false
            if ($cfg.PSObject.Properties.Name -contains "EnableTrayIcon") { $tray = [bool]$cfg.EnableTrayIcon }
            if ($cfg.PSObject.Properties.Name -contains "EnableHotkey") { $hot = [bool]$cfg.EnableHotkey }

            if ($tray -or $hot) { $Mode = "Interactive" }
            else { $Mode = "Hidden" }
        }
        catch {}
    }

    # Operating mode only if installed
    $operatingMode = $null
    if ($installed -and $cfg -and ($cfg.PSObject.Properties.Name -contains "OperatingMode")) {
        $operatingMode = $cfg.OperatingMode
    }

    # Status line
    $statusLine = "Status: Not installed"

    if ($installed -and $proc.Running) {
        $statusLine = "Status: SAMISH is running correctly"
    }
    elseif ($installed -and -not $proc.Running) {
        $statusLine = "Status: Installed but not currently running"
    }
    elseif (-not $installed -and $proc.Running) {
        $statusLine = "Status: Not installed (leftover SAMISH instance is running)"
    }

    $lines = @()
    $lines += $statusLine
    $lines += "=== SAMISH Diagnostics ==="

    if ($Context) { $lines += "Context: $Context" }
    $lines += "Engine: $InstalledEnginePath"

    if (-not [string]::IsNullOrWhiteSpace($Mode)) {
        $lines += "Install Mode: $Mode"
    }

    if ($installed -and $operatingMode) {
        $lines += "Operating Mode: $operatingMode"
    }

    # Logging (friendly)
    if ($cfg) {
        if ($cfg.PSObject.Properties.Name -contains "EnableLogging" -and [bool]$cfg.EnableLogging) {
            $sec = -1
            try { $sec = [int]$cfg.LogEverySeconds } catch { $sec = -1 }
            $lines += "Logging: Enabled (" + (Format-SecondsToFriendlyCompact $sec) + ")"
        }
        else {
            $lines += "Logging: Disabled"
        }
    }

    # Hotkey
    if ($cfg -and ($cfg.PSObject.Properties.Name -contains "EnableHotkey") -and [bool]$cfg.EnableHotkey) {
        if ($cfg.HotkeyMode -eq "Custom") {
            $vk = $cfg.CustomHotkeyVirtualKey
            $friendly = [System.Windows.Forms.Keys]$vk
            $lines += "Hotkey: Custom ($friendly)"
        }
        else {
            $lines += "Hotkey: " + $cfg.HotkeyMode
        }
    }
    else {
        $lines += "Hotkey: Disabled"
    }

    # Tray
    if ($cfg -and ($cfg.PSObject.Properties.Name -contains "EnableTrayIcon")) {
        $lines += "Tray Icon: " + ($(if ([bool]$cfg.EnableTrayIcon) { "Enabled" } else { "Disabled" }))
    }

    # Startup shortcut (Scheduled-task-only for Interactive)
    if (-not $installed) {
        $lines += "Startup shortcut: Not Installed"
    }
    elseif ($Mode -eq "Hidden") {
        $lines += "Startup shortcut: Not required (Hidden mode)"
    }
    elseif ($Mode -eq "Interactive") {
        if ($shortcutPresent) {
            $lines += "Startup shortcut: Present (unexpected) - should be removed ($shortcutPath)"
        }
        else {
            $lines += "Startup shortcut: Not required (Interactive uses Scheduled Task)"
        }
    }
    else {
        if ($shortcutPresent) {
            $lines += "Startup shortcut: Present (unexpected) - should be removed ($shortcutPath)"
        }
        else {
            $lines += "Startup shortcut: Not required"
        }
    }


    # Tasks -- NO "Missing"
    if (-not $installed) {
        $lines += "Task (Hidden): Not Installed"
        $lines += "Task (Interactive): Not Installed"
    }
    elseif ($Mode -eq "Interactive") {
        $lines += "Task (Interactive): " + ($(if ($interactiveTask.Exists) { "Present" } else { "Not Created" }))
        $lines += "Task (Hidden): Not Used"
    }
    elseif ($Mode -eq "Hidden") {
        $lines += "Task (Hidden): " + ($(if ($hiddenTask.Exists) { "Present" } else { "Not Created" }))
        $lines += "Task (Interactive): Not Used"
    }
    else {
        # Mode unknown: show both task states
        $lines += "Task (Interactive): " + ($(if ($interactiveTask.Exists) { "Present" } else { "Not Created" }))
        $lines += "Task (Hidden): " + ($(if ($hiddenTask.Exists) { "Present" } else { "Not Created" }))
    }

    # Process
    if (-not $installed) {
        $lines += "Process running: " + ($(if ($proc.Running) { "Yes (manual or leftover instance)" } else { "No" }))
    }
    else {
        $lines += "Process running: " + ($(if ($proc.Running) { "Yes" } else { "No" })) +
        ($(if ($proc.Running) { " | Instances: $($proc.Count) | PID(s): $($proc.Pids -join ',')" } else { "" }))
    }

    # Power plan block (only if it has content)
    if (-not [string]::IsNullOrWhiteSpace($powerLine)) {
        $lines += $powerLine
    }

    $lines += "========================="

    return ($lines -join "`r`n")
}

function Show-DiagnosticsHeader {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'TrayRequested',
        Justification = 'Passed by Events.Setup.ps1 callers; reserved for future diagnostic detail rendering')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'HotkeyRequested',
        Justification = 'Passed by Events.Setup.ps1 callers; reserved for future diagnostic detail rendering')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'LoggingRequested',
        Justification = 'Passed by Events.Setup.ps1 callers; reserved for future diagnostic detail rendering')]
    param(
        [string]$Context = "",
        [string]$Mode = "",
        [bool]$TrayRequested = $false,
        [bool]$HotkeyRequested = $false,
        [bool]$LoggingRequested = $false,

        # Default behavior: include power plan, but auto-disable if it already appears in the existing status text
        [bool]$IncludePowerPlan = $true
    )


    # Capture existing text FIRST (important for Install/Update and other flows that set status before calling this)
    $existing = $statusBox.Text

    # Auto-dedup: if the existing text already contains a "Power Plan:" block, don't repeat it in diagnostics header
    $effectiveIncludePowerPlan = $IncludePowerPlan
    try {
        if ($effectiveIncludePowerPlan -and -not [string]::IsNullOrWhiteSpace($existing)) {

            # Case 1: Existing text already includes the Power Plan block (exact or implied)
            if ($existing -match '(?m)^\s*Power Plan:\s*$' -or
                ($existing -match '(?m)^\s*Screen Off\s*=' -and $existing -match '(?m)^\s*Hibernate\s*=')) {
                $effectiveIncludePowerPlan = $false
            }

            # Case 2: Existing text already contains a power-plan warning/action (even without the block)
            if ($effectiveIncludePowerPlan -and
                $existing -match '(?i)\bpower plan\b' -and
                $existing -match '(?i)check\s*/\s*restore') {
                $effectiveIncludePowerPlan = $false
            }
        }
    }
    catch { }

    $header = Build-DiagnosticsHeader `
        -Context $Context `
        -Mode $Mode `
        -IncludePowerPlan:$effectiveIncludePowerPlan


    if ([string]::IsNullOrWhiteSpace($existing)) {
        Set-StatusText($header)
    }
    else {
        Set-StatusText($header + "`r`n`r`n--- Recent Activity ---`r`n" + $existing)
    }

    Write-SetupLogBlock $statusBox.Text
}

# ----- UI read-only status helpers -----
function Show-CurrentConfiguration {
    try {
        $lines = @()

        $warn = Get-PowerPlanReadOnlyWarnings
        if ($warn -and $warn.Count -gt 0) { $lines += $warn }

        $lines += "Loaded current configuration..."
        $lines += ""

        $configExists = Test-Path -LiteralPath $ConfigPath

        if ($configExists) {
            $hiddenTaskExists = Task-Exists -TaskNameWithSlash $TaskHidden
            $interactiveTaskExists = Task-Exists -TaskNameWithSlash $TaskInteractive

            if (-not ($hiddenTaskExists -or $interactiveTaskExists)) {
                $lines += "=== SAVED CONFIGURATION (from previous installation) ==="
            }
            else {
                $lines += "=== CURRENT CONFIGURATION ==="
            }
        }
        else {
            $lines += "=== CURRENT CONFIGURATION ==="
        }

        if ($configExists) {
            $cfg = (Get-Content -LiteralPath $ConfigPath -Raw) | ConvertFrom-Json

            $loggingEnabled = [bool]$cfg.EnableLogging
            $lines += "Logging: " + ($(if ($loggingEnabled) { "Enabled" } else { "Disabled" }))

            if ($loggingEnabled) {
                $sec = -1
                try { $sec = [int]$cfg.LogEverySeconds } catch { $sec = -1 }
                $lines += "Log Interval: " + (Format-SecondsToFriendlyCompact $sec)
            }

            $lines += "Tray Icon: " + ($(if ($cfg.EnableTrayIcon) { "Enabled" } else { "Disabled" }))

            if ($cfg.EnableHotkey) {
                if ($cfg.HotkeyMode -eq "Custom") {
                    $vk = $cfg.CustomHotkeyVirtualKey
                    $friendly = [System.Windows.Forms.Keys]$vk
                    $lines += "Hotkey: Custom ($friendly)"
                }
                else {
                    $lines += "Hotkey: " + $cfg.HotkeyMode
                }
            }
            else {
                $lines += "Hotkey: Disabled"
            }
        }
        else {
            $lines += "Config not found (not installed yet)."
        }

        $includePowerPlan = $true

        try {
            if ($warn -and ($warn -contains "Power Plan:" -or (($warn -join "`n") -match '(?m)^\s*Power Plan:\s*$'))) {
                $includePowerPlan = $false
            }
        }
        catch { }

        $lines += ""
        $lines += (Build-DiagnosticsHeader -IncludePowerPlan:$includePowerPlan)

        Set-StatusText($lines -join "`r`n")
        Write-SetupLogBlock ($lines -join "`r`n")
    }
    catch {
        Set-StatusText("Failed to read configuration.`r`n$($_.Exception.Message)")
    }
}

# ----- Layout helpers -----
function Place-Below {
    param([System.Windows.Forms.Control]$Above, [System.Windows.Forms.Control]$Below, [int]$Gap = 10)
    $Below.Location = New-Object System.Drawing.Point($Below.Location.X, ($Above.Location.Y + $Above.Height + $Gap))
}
