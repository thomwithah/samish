#requires -Version 5.1
# ==============================================================================
# Module: Setup.Helpers.ps1
# Purpose: Core setup helpers including filesystem init, config reading,
#          event log registration, setup logging, dialog wrappers,
#          power plan opt-in flows, and install mode/restart helpers.
#          Extracted from Setup.ps1 to reduce its size.
# Inputs: Consumed by Events.Setup.ps1, Logic.ps1 via dot-sourcing from Setup.ps1.
# Outputs: Dialog results, log output, install state queries.
# Error Handling: All functions use try/catch with fail-forward.
# ==============================================================================

# ---------- Core helpers ----------

# ----- File system / install folder -----
function Ensure-InstallFolder {
    if (-not (Test-Path -LiteralPath $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }
}

function Get-UnknownPowerPlanPromptStatus {
    param([string]$PromptId)
    return @{ StatusMessage = "Unknown power plan prompt request: $PromptId" }
}

# ----- Config read helpers -----
function Get-ConfigEnableLogging {
    try {
        if (Test-Path -LiteralPath $ConfigPath) {
            $raw = Get-Content -LiteralPath $ConfigPath -Raw
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $cfg = $raw | ConvertFrom-Json
                if ($null -ne $cfg.EnableLogging) { return [bool]$cfg.EnableLogging }
            }
        }
    }
    catch {}
    return $false
}

# Windows Event Log Helper
function Register-SamishEventSource {
    try {
        if (-not (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\SAMISH")) {
            [System.Diagnostics.EventLog]::CreateEventSource("SAMISH", "Application")
            Write-SetupLog "Registered SAMISH as a Windows Event Log source."
        }
    }
    catch {
        Write-SetupLog "WARNING: Failed to register SAMISH as an Event Log source: $($_.Exception.Message)"
    }
}

# Logging helpers (Rotate-LogFileIfNeeded imported from Logger.psm1)

function Write-SetupLog {
    param([string]$text)

    $enabled = $false
    try {
        if ($script:cbLogging -and $script:cbLogging.Checked) { $enabled = $true }
        else { $enabled = (Get-ConfigEnableLogging) }
    }
    catch {}

    if (-not $enabled) { return }

    try {
        Rotate-LogFileIfNeeded -Path $StandardLogFile
        Add-Content -Path $StandardLogFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $text"
    }
    catch {}
}

function Write-SetupLogBlock {
    param([string]$textBlock)

    $enabled = $false
    try {
        if ($script:cbLogging -and $script:cbLogging.Checked) {
            $enabled = $true
        }
        else {
            $enabled = (Get-ConfigEnableLogging)
        }
    }
    catch {}

    if (-not $enabled) { return }

    try {
        Rotate-LogFileIfNeeded -Path $StandardLogFile
        Add-Content -Path $StandardLogFile -Value (
            "`r`n==== " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " ====`r`n" +
            $textBlock + "`r`n"
        )
    }
    catch {}
}

# ----- Dialog helpers (DRY) -----
function Show-InfoDialog {
    param(
        [string]$Message,
        [string]$Title = "Information"
    )

    try {
        [System.Windows.Forms.MessageBox]::Show(
            $Message,
            $Title,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    catch {}
}

function Show-WarningDialog {
    param(
        [string]$Message,
        [string]$Title = "Warning"
    )

    try {
        [System.Windows.Forms.MessageBox]::Show(
            $Message,
            $Title,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
    }
    catch {}
}

function Show-ErrorDialog {
    param(
        [string]$Message,
        [string]$Title = "Error"
    )

    try {
        [System.Windows.Forms.MessageBox]::Show(
            $Message,
            $Title,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    catch {}
}

function Show-YesNoDialog {
    param(
        [string]$Message,
        [string]$Title,
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Question
    )

    try {
        return [System.Windows.Forms.MessageBox]::Show(
            $Message,
            $Title,
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            $Icon
        )
    }
    catch {
        return [System.Windows.Forms.DialogResult]::No
    }
}

# ----- Tools helpers (DRY) -----
function Get-VerifiedPreferredLogPathOrShowMessageBox {
    try {
        $path = Get-PreferredSamishLogPath

        if ($path -and (Test-Path -LiteralPath $path)) {
            return $path
        }

        Show-InfoDialog `
            -Title "Log Not Found" `
            -Message "No SAMISH log files were found.`r`n`r`nEnable logging and run SAMISH, then try again."

        return $null
    }
    catch {
        Show-ErrorDialog `
            -Title "Error" `
            -Message ("Failed to locate log:`r`n" + $_.Exception.Message)

        return $null
    }
}

function Format-CleanResetStatusMessage {
    param(
        [int]$StoppedCount,
        [bool]$TrayRestarted
    )

    if ($TrayRestarted) {
        if ($StoppedCount -eq 0) {
            return "SAMISH was not running.`r`nTray instance started."
        }
        elseif ($StoppedCount -eq 1) {
            return "Clean reset complete.`r`n1 instance restarted."
        }
        else {
            return "Clean reset complete.`r`n$StoppedCount instances restarted."
        }
    }
    else {
        if ($StoppedCount -eq 0) {
            return "No running SAMISH instances were found.`r`nSystem is already clean."
        }
        elseif ($StoppedCount -eq 1) {
            return "Clean reset complete.`r`n1 running instance was stopped."
        }
        else {
            return "Clean reset complete.`r`n$StoppedCount running instances were stopped."
        }
    }
}

function Get-NoPowerPlanChangesText {
    return "No power plan changes were made."
}

function Get-NoPowerPlanChangesStatus {
    return @{ StatusMessage = (Get-NoPowerPlanChangesText) }
}

# ----- Power plan opt-in helpers (DRY) -----
function Get-PowerPlanClassicCompatOptInPromptText {
    return @"
You are currently using Graceful mode. Graceful mode does not require Classic power plan compatibility.

Classic mode works best when Screen Off occurs at least 60 seconds before Sleep/Hibernate.

Would you like to make your current power plan Classic-compatible now anyway?

A backup will be created before any changes are applied.
"@
}

function Ask-PowerPlanClassicCompatOptIn {
    $res = [System.Windows.Forms.MessageBox]::Show(
        (Get-PowerPlanClassicCompatOptInPromptText),
        "Power Plan Compatibility",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )

    return ($res -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Invoke-GracefulClassicCompatOptInFlow {
    param(
        $InitialResult,
        [bool]$AutoMode
    )

    if (-not $InitialResult -or -not $InitialResult.NeedsPrompt) {
        return $InitialResult
    }

    if (-not (Ask-PowerPlanClassicCompatOptIn)) {
        return (Get-NoPowerPlanChangesStatus)
    }

    $result = Handle-PowerPlanPromptIfNeeded -result $InitialResult -AutoMode:$AutoMode
    if ($result -and $result.NeedsPrompt) {
        $result = Handle-PowerPlanPromptIfNeeded -result $result -AutoMode:$AutoMode
    }

    return $result
}

function Get-ActiveInstallModeForReset {
    # Prefer installed task reality; fall back to config intent; final fallback: UI selection.
    try {
        if (Task-Exists -TaskNameWithSlash $TaskInteractive) { return "Interactive" }
        if (Task-Exists -TaskNameWithSlash $TaskHidden) { return "Hidden" }
    }
    catch {}

    try {
        if (Test-Path -LiteralPath $ConfigPath) {
            $cfg = (Get-Content -LiteralPath $ConfigPath -Raw) | ConvertFrom-Json
            if ($cfg) {
                $tray = $false
                $hot = $false
                if ($cfg.PSObject.Properties.Name -contains "EnableTrayIcon") { $tray = [bool]$cfg.EnableTrayIcon }
                if ($cfg.PSObject.Properties.Name -contains "EnableHotkey") { $hot = [bool]$cfg.EnableHotkey }
                if ($tray -or $hot) { return "Interactive" }
                return "Hidden"
            }
        }
    }
    catch {}

    # Final fallback: current UI selection (best effort)
    if ($rbInteractive.Checked) { return "Interactive" }
    return "Hidden"
}

function Start-SamishInMode {
    param(
        [ValidateSet("Hidden", "Interactive")]
        [string]$Mode
    )

    # Task-only start. Do not start engine directly.
    try {
        if ($Mode -eq "Interactive") {
            if (Task-Exists -TaskNameWithSlash $TaskInteractive) {
                return Run-Schtasks ("/Run /TN `"$TaskInteractive`"")
            }
            return @{ ExitCode = 2; StdOut = ""; StdErr = "Interactive task is not installed." }
        }

        if ($Mode -eq "Hidden") {
            if (Task-Exists -TaskNameWithSlash $TaskHidden) {
                return Run-Schtasks ("/Run /TN `"$TaskHidden`"")
            }
            return @{ ExitCode = 2; StdOut = ""; StdErr = "Hidden task is not installed." }
        }
    }
    catch {
        return @{ ExitCode = 1; StdOut = ""; StdErr = ("Failed to start via scheduled task: " + $_.Exception.Message) }
    }

}
