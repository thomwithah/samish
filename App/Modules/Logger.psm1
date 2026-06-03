#requires -Version 5.1
# ==============================================================================
# Module: Logger.psm1
# Purpose: Unified logging operations for SAMISH. Provides log file rotation,
#          date-templated path resolution, Windows Event Log writes, and
#          standard formatted log entry functions used by both the Setup UI
#          and the background engine (SAMISH.ps1).
# Inputs: Log file paths, log messages, rotation thresholds.
# Outputs: Log entries written to disk and/or Windows Event Log.
# Error Handling: All functions fail-forward silently to prevent log errors
#                 from interrupting core application flow.
# ==============================================================================

function Resolve-SamishLogPath {
    <#
    .SYNOPSIS
        Resolves a date-templated log path (e.g. samish_{DATE}.log) to today's
        concrete path and ensures the parent directory exists.
    #>
    param([string]$TemplatePath)

    if ([string]::IsNullOrWhiteSpace($TemplatePath)) { return $null }

    $today = (Get-Date -Format "yyyyMMdd")
    $resolved = $TemplatePath.Replace("{DATE}", $today)

    # Ensure directory exists
    try {
        $dir = Split-Path -Parent $resolved
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    } catch {}

    return $resolved
}

function Rotate-LogFileIfNeeded {
    <#
    .SYNOPSIS
        Rotates a log file when it exceeds 5 MB by renaming it with an
        incrementing suffix (.1, .2, ... up to .100).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        if (-not (Test-Path -LiteralPath $Path)) { return }

        $fileItem = Get-Item -LiteralPath $Path
        # 5MB = 5 * 1024 * 1024 = 5242880 bytes
        if ($fileItem.Length -le 5242880) { return }

        $dir = Split-Path -Parent $Path
        $name = Split-Path -Leaf $Path
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($name)
        $ext = [System.IO.Path]::GetExtension($name)

        $rotatedPath = $null
        for ($i = 1; $i -le 100; $i++) {
            $testName = "$baseName.$i$ext"
            $testPath = Join-Path $dir $testName
            if (-not (Test-Path -LiteralPath $testPath)) {
                $rotatedPath = $testPath
                break
            }
        }

        if (-not $rotatedPath) {
            $rotatedPath = Join-Path $dir "$baseName.100$ext"
            if (Test-Path -LiteralPath $rotatedPath) {
                Remove-Item -LiteralPath $rotatedPath -Force -ErrorAction SilentlyContinue
            }
        }

        if ($rotatedPath) {
            [System.IO.File]::Move($Path, $rotatedPath)
        }
    }
    catch {
        # Fail silently -- log rotation failure must not interrupt the application
    }
}

function Write-EventLogEntry {
    <#
    .SYNOPSIS
        Writes an entry to the Windows Application Event Log under the SAMISH
        source. Fails silently if the source is not registered.
    #>
    param(
        [string]$Message,
        [System.Diagnostics.EventLogEntryType]$EntryType = "Information",
        [int]$EventId = 100
    )

    try {
        if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\SAMISH") {
            [System.Diagnostics.EventLog]::WriteEntry("SAMISH", $Message, $EntryType, $EventId)
        }
    }
    catch {
        # Fail-safe silently to standard file logs
    }
}

Export-ModuleMember -Function Resolve-SamishLogPath, Rotate-LogFileIfNeeded, Write-EventLogEntry
