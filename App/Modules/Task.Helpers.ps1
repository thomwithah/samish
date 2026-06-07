#requires -Version 5.1
# ==============================================================================
# Module: Task.Helpers.ps1
# Purpose: Scheduled task wrappers (schtasks.exe), startup shortcut management,
#          helper process control, hotkey parsing, and log interval parsing.
#          Extracted from Setup.ps1 to reduce its size.
# Inputs: Consumed by Events.Setup.ps1, Logic.ps1, and Setup.ps1 via dot-sourcing.
# Outputs: Various helper function results (exit codes, parsed values, etc.).
# Error Handling: All schtasks calls wrapped in try/catch. Process stop uses
#                 fail-forward design with SilentlyContinue.
# ==============================================================================

# ----- Startup Shortcut Automation -----
function Get-StartupFolder { [Environment]::GetFolderPath("Startup") }
function Get-StartupShortcutPath { Join-Path (Get-StartupFolder) "SAMISH.lnk" }

function Create-StartupShortcut {
    param([string]$ScriptPath)

    $shortcutPath = Get-StartupShortcutPath
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)

    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$ScriptPath`""
    $shortcut.WorkingDirectory = Split-Path $ScriptPath
    $shortcut.IconLocation = "powershell.exe,0"
    $shortcut.Save()
}

function Remove-StartupShortcut {
    $shortcutPath = Get-StartupShortcutPath
    if (Test-Path -LiteralPath $shortcutPath) {
        Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
    }
}

# ----- schtasks wrappers -----
function Run-Schtasks {
    param([string]$Arguments)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "schtasks.exe"
    $psi.Arguments = $Arguments
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    return @{ ExitCode = $p.ExitCode; StdOut = $stdout; StdErr = $stderr }
}

function Install-TaskFromXml {
    param([string]$TaskNameNoSlash, [string]$XmlPath)
    if (-not (Test-Path -LiteralPath $XmlPath)) { throw "XML missing: $XmlPath" }
    return Run-Schtasks ("/Create /TN `"$TaskNameNoSlash`" /XML `"$XmlPath`" /F")
}

function Delete-Task {
    param([string]$TaskNameWithSlash)
    return Run-Schtasks ("/Delete /TN `"$TaskNameWithSlash`" /F")
}

function Task-Exists {
    param([string]$TaskNameWithSlash)
    return ((Run-Schtasks ("/Query /TN `"$TaskNameWithSlash`"")).ExitCode -eq 0)
}

function Test-SamishInstalled {
    try {
        if (Task-Exists -TaskNameWithSlash $TaskInteractive) { return $true }
        if (Task-Exists -TaskNameWithSlash $TaskHidden) { return $true }
    }
    catch {}
    return $false
}

function Stop-SamishTaskIfRunning {
    param(
        [ValidateSet("Hidden", "Interactive")]
        [string]$Mode
    )
    try {
        if ($Mode -eq "Interactive" -and (Task-Exists -TaskNameWithSlash $TaskInteractive)) {
            $null = Run-Schtasks ("/End /TN `"$TaskInteractive`"")
        }
        elseif ($Mode -eq "Hidden" -and (Task-Exists -TaskNameWithSlash $TaskHidden)) {
            $null = Run-Schtasks ("/End /TN `"$TaskHidden`"")
        }
    }
    catch {}
}

# ----- Helper process control -----
function Stop-RunningHelperInstances {
    param(
        [int]$WaitTimeoutMs = 2500
    )

    $selfPid = $PID
    $enginePath = $InstalledEnginePath
    $enginePathEsc = if ($enginePath) { [Regex]::Escape($enginePath) } else { "" }

    # Find candidate processes
    $procs = Get-CimInstance Win32_Process | Where-Object {
        ($_.Name -eq "powershell.exe" -or $_.Name -eq "pwsh.exe") -and
        $_.ProcessId -ne $selfPid -and
        $_.CommandLine -and (
            # Full path run
            ($enginePathEsc -and $_.CommandLine -match $enginePathEsc) -or

            # Task run (relative file name)
            ($_.CommandLine -match '(?i)(-File\s+)"?SAMISH\.ps1"?(?:\s|$)') -or

            # Generic roaming path hint
            ($_.CommandLine -match '(?i)\\AppData\\Roaming\\SAMISH\\SAMISH\.ps1')
        )
    }

    $pids = @()
    foreach ($p in $procs) {
        try {
            $pids += [int]$p.ProcessId
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        }
        catch { }
    }

    # Fallback: PID file (CIM returns null CommandLine for elevated Task Scheduler processes)
    if ($pids.Count -eq 0) {
        $pidFile = Join-Path $InstallDir "samish.pid"
        if (Test-Path -LiteralPath $pidFile) {
            try {
                $savedPid = [int](Get-Content -LiteralPath $pidFile -Raw).Trim()
                if ($savedPid -ne $selfPid) {
                    $proc = Get-Process -Id $savedPid -ErrorAction SilentlyContinue
                    if ($proc -and ($proc.ProcessName -eq "powershell" -or $proc.ProcessName -eq "pwsh")) {
                        Stop-Process -Id $savedPid -Force -ErrorAction SilentlyContinue
                        $pids += $savedPid
                    }
                }
            } catch {}
        }
    }

    # Wait (briefly) for termination so Task Scheduler (/Run) can actually restart under IgnoreNew.
    if ($pids.Count -gt 0) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while ($sw.ElapsedMilliseconds -lt $WaitTimeoutMs) {
            $still = @()
            foreach ($id in $pids) {
                if (Get-Process -Id $id -ErrorAction SilentlyContinue) { $still += $id }
            }
            if ($still.Count -eq 0) { break }
            Start-Sleep -Milliseconds 100
        }
    }

    return $pids.Count
}

# ----- Hotkey parsing -----
$VkMap = @{
    "ScrollLock" = 0x91
    "PauseBreak" = 0x13
    "F12"        = 0x7B
}

function Parse-CustomHotkeyToVk {
    param([string]$InputText)

    if ([string]::IsNullOrWhiteSpace($InputText)) { throw "Custom hotkey is blank." }
    $u = $InputText.Trim().ToUpperInvariant()

    if ($VkMap.ContainsKey($u)) { return [int]$VkMap[$u] }
    if ($u -match '^F([1-9]|1[0-9]|2[0-4])$') { return 0x70 + ([int]$matches[1] - 1) }
    if ($u -match '^[A-Z]$') { return [int][byte][char]$u }
    if ($u -match '^[0-9]$') { return 0x30 + [int]$u }
    if ($u -match '^0X[0-9A-F]+$') { return [Convert]::ToInt32($u, 16) }

    throw "Unsupported custom hotkey. Examples: F8, K, 7, or 0x91."
}

# ----- Log interval parsing -----
function Parse-LogEverySecondsOrThrow {
    param(
        [string]$RawText,
        [string]$ContextLabel = "Log interval"
    )

    $t = ($RawText | Out-String).Trim()

    if ([string]::IsNullOrWhiteSpace($t)) {
        throw "$ContextLabel must not be blank."
    }

    if ($t -notmatch '^\d+$') {
        throw "$ContextLabel must be a whole number of seconds."
    }

    $n = 0
    if (-not [int]::TryParse($t, [ref]$n)) {
        throw "$ContextLabel is out of range. Please enter a value between 0 and 2147483647 seconds."
    }

    return $n
}

function Format-SecondsToFriendlyCompact {
    param([int]$Seconds)

    if ($Seconds -lt 0) { return "Unknown" }
    if ($Seconds -eq 0) { return "Verbose (every loop)" }

    $start = Get-Date
    $end = $start.AddSeconds($Seconds)

    $years = 0
    $cursor = $start
    while ($cursor.AddYears(1) -le $end) {
        $cursor = $cursor.AddYears(1)
        $years++
    }

    $remaining = $end - $cursor

    $days = [Math]::Floor($remaining.TotalDays)
    $cursor = $cursor.AddDays($days)
    $remaining = $end - $cursor

    $hours = [Math]::Floor($remaining.TotalHours)
    $cursor = $cursor.AddHours($hours)
    $remaining = $end - $cursor

    $minutes = [Math]::Floor($remaining.TotalMinutes)
    $cursor = $cursor.AddMinutes($minutes)
    $remaining = $end - $cursor

    $secs = [Math]::Floor($remaining.TotalSeconds)

    $parts = @()
    if ($years -gt 0) { $parts += ($(if ($years -eq 1) { "1 year" } else { "$years years" })) }
    if ($days -gt 0) { $parts += ($(if ($days -eq 1) { "1 day" } else { "$days days" })) }
    if ($hours -gt 0) { $parts += ($(if ($hours -eq 1) { "1 hour" } else { "$hours hours" })) }
    if ($minutes -gt 0) { $parts += ($(if ($minutes -eq 1) { "1 minute" } else { "$minutes minutes" })) }
    if ($secs -gt 0) { $parts += ($(if ($secs -eq 1) { "1 second" } else { "$secs seconds" })) }

    if ($parts.Count -eq 0) { return "0 seconds" }
    return ($parts -join " ")
}
