# ==========================================
# SAMISH App Control - Common Utilities
# ==========================================

# ------------------------------------------
# Type-Safe Class Definitions
# ------------------------------------------

class AppStartResult {
    [bool]$Started
    [string]$Status
    [string]$Method
    [string]$Log

    AppStartResult() {}
    AppStartResult([bool]$started, [string]$status, [string]$method, [string]$log) {
        $this.Started = $started
        $this.Status = $status
        $this.Method = $method
        $this.Log = $log
    }
}

class AppStopResult {
    [bool]$Stopped
    [string]$Status
    [string]$Method
    [bool]$WindowRestored
    [bool]$FallbackUsed
    [string]$Error

    AppStopResult() {}
    AppStopResult([bool]$stopped, [string]$status, [string]$method, [bool]$windowRestored, [bool]$fallbackUsed, [string]$errorText) {
        $this.Stopped = $stopped
        $this.Status = $status
        $this.Method = $method
        $this.WindowRestored = $windowRestored
        $this.FallbackUsed = $fallbackUsed
        $this.Error = $errorText
    }
}

class AppExecutablePathResult {
    [string]$Path
    [bool]$IsValid
    [string]$Source
    [string]$Error

    AppExecutablePathResult() {}
    AppExecutablePathResult([string]$path, [bool]$isValid, [string]$source, [string]$errorText) {
        $this.Path = $path
        $this.IsValid = $isValid
        $this.Source = $source
        $this.Error = $errorText
    }
}

# ------------------------------------------
# Atomic Write Utility
# ------------------------------------------

function Save-ContentAtomic {
    param(
        [string]$Path,
        [string]$Content
    )

    # Temporary staging path to prevent partial or corrupted writes
    $tmpPath = $Path + ".tmp"
    try {
        # Force writing staging file to ensure operation completes before swapping
        Set-Content -LiteralPath $tmpPath -Value $Content -Encoding UTF8 -ErrorAction Stop

        # Safely overwrite or place the target file atomically
        if (Test-Path -LiteralPath $Path) {
            Move-Item -LiteralPath $tmpPath -Destination $Path -Force -ErrorAction Stop
        } else {
            Move-Item -LiteralPath $tmpPath -Destination $Path -ErrorAction Stop
        }
    }
    catch {
        # Log to Setup GUI log function if present in session
        if (Get-Command Write-SetupLog -ErrorAction SilentlyContinue) {
            Write-SetupLog "Atomic write failed: $($_.Exception.Message)"
        }
        # Log to Background Engine log function if present in session
        elseif (Get-Command Log-Always -ErrorAction SilentlyContinue) {
            Log-Always "Atomic write failed: $($_.Exception.Message)"
        }
        else {
            Write-Error "Atomic write failed: $($_.Exception.Message)"
        }

        # Cleanup staging file to avoid clutter
        if (Test-Path -LiteralPath $tmpPath) {
            Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
        }
        throw $_
    }
}

function Get-AppExecutablePath {

    param(
        [string]$ProcessName = "BEACN",
        [string]$ConfiguredPath = $null,
        [string]$RegistrySearchString = $ProcessName
    )

    # ------------------------------------------
    # 1. Try Configured Path (highest priority)
    # ------------------------------------------
    if ($ConfiguredPath -and (Test-Path $ConfiguredPath)) {
        return [AppExecutablePathResult]::new($ConfiguredPath, $true, "Config", "")
    }

    # Try UWP Execution Alias fallback
    $aliasName = if ($ConfiguredPath) { Split-Path $ConfiguredPath -Leaf } else { "$ProcessName.exe" }
    if ($aliasName -notlike "*.exe") { $aliasName += ".exe" }
    $aliasPath = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\$aliasName"
    if (Test-Path $aliasPath) {
        return [AppExecutablePathResult]::new($aliasPath, $true, "ExecutionAlias", "")
    }

    # ------------------------------------------
    # 2. Try Running Process
    # ------------------------------------------
    try {
        $proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($proc -and $proc.MainModule -and $proc.MainModule.FileName) {

            $p = $proc.MainModule.FileName

            if (Test-Path $p) {
                return [AppExecutablePathResult]::new($p, $true, "Process", "")
            }
        }
    }
    catch {
        # Access to MainModule can fail in some contexts - ignore
    }

    # ------------------------------------------
    # 3. Try Registry (Uninstall entries)
    # ------------------------------------------
    try {
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"

        $entry = Get-ItemProperty $regPath -ErrorAction SilentlyContinue |
                 Where-Object { $_.DisplayName -match $RegistrySearchString } |
                 Select-Object -First 1

        if ($entry -and $entry.DisplayIcon) {

            $p = $entry.DisplayIcon.Split(',')[0].Replace('"','')

            if (Test-Path $p) {
                return [AppExecutablePathResult]::new($p, $true, "Registry", "")
            }
        }
    }
    catch {
        # Registry access errors ignored safely
    }

    # ------------------------------------------
    # 4. Failure
    # ------------------------------------------
    return [AppExecutablePathResult]::new($null, $false, "None", "Unable to locate executable for $ProcessName")
}