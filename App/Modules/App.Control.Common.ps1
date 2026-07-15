#requires -Version 5.1
# ==============================================================================
# Module: App.Control.Common.ps1
# Purpose: Shared type definitions (AppStartResult, AppStopResult,
#          AppExecutablePathResult), atomic file write utility (Save-ContentAtomic),
#          and executable path resolver (Get-AppExecutablePath).
#          Includes a lazy async UWP path cache (Get-UwpCachedPath,
#          Invoke-UwpPathRefresh) to avoid blocking Get-AppxPackage scans at startup.
# Inputs:  ProcessName, ConfiguredPath, RegistrySearchString (for path resolution).
# Outputs: AppExecutablePathResult instances. Cache flushes to config.json.
# Error Handling: All external system calls (WMI, registry, process, file I/O)
#                 are wrapped in try/catch with fail-forward behavior.
# ==============================================================================

# ------------------------------------------
# Script-scoped UWP path cache
# Populated from config.json at engine startup.
# Refreshed lazily and asynchronously on cache miss.
# ------------------------------------------
if (-not (Get-Variable -Name 'UwpPathCache' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:UwpPathCache = @{}
}
# Guard flag: prevents concurrent Get-AppxPackage scans for the same process name.
# Key = ProcessName (lowercase), Value = $true while a refresh is in flight.
if (-not (Get-Variable -Name 'UwpRefreshInProgress' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:UwpRefreshInProgress = @{}
}

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
    # 4. Try UWP / AppxPackage (Microsoft Store installs) -- cache-first, async lazy
    # ------------------------------------------
    # UWP apps install to dynamically versioned dirs under WindowsApps and cannot be
    # located via registry or hardcoded paths.
    # Strategy:
    #   a) Check $script:UwpPathCache first. If the cached path exists on disk, return it
    #      immediately (zero cost on all subsequent calls).
    #   b) If the cache is stale or empty, enqueue an async Get-AppxPackage scan on a
    #      ThreadPool thread. Return failure for this call; the cache will be warm by
    #      the next wake cycle.
    # This ensures Get-AppxPackage NEVER blocks the main thread.
    $cachedResult = Get-UwpCachedPath -ProcessName $ProcessName
    if ($cachedResult) {
        return [AppExecutablePathResult]::new($cachedResult, $true, "UwpCache", "")
    }

    # Cache miss -- enqueue async refresh (non-blocking)
    Invoke-UwpPathRefresh -ProcessName $ProcessName -RegistrySearchString $RegistrySearchString

    # ------------------------------------------
    # 5. Failure
    # ------------------------------------------
    return [AppExecutablePathResult]::new($null, $false, "None", "Unable to locate executable for $ProcessName")
}

# ------------------------------------------
# Get-UwpCachedPath
# Returns the cached UWP executable path for the given process name if it
# exists in $script:UwpPathCache AND the path still exists on disk.
# Returns $null if the cache is empty or stale (triggers async refresh).
# ------------------------------------------
function Get-UwpCachedPath {
    param([string]$ProcessName)

    try {
        $key = $ProcessName.ToLower()
        if ($script:UwpPathCache.ContainsKey($key)) {
            $cached = $script:UwpPathCache[$key]
            if (-not [string]::IsNullOrWhiteSpace($cached) -and (Test-Path -LiteralPath $cached)) {
                return $cached
            }
            # Path no longer exists on disk -- stale entry, clear it so refresh fires
            $script:UwpPathCache.Remove($key)
            if (Get-Command Log-Always -ErrorAction SilentlyContinue) {
                Log-Always ("UWP path cache stale for " + $ProcessName + " - refresh enqueued")
            }
        }
    }
    catch {
        # Fail-forward: cache read errors must not crash the caller
    }

    return $null
}

# ------------------------------------------
# Invoke-UwpPathRefresh
# Enqueues an async Get-AppxPackage scan on the .NET ThreadPool.
# On success, writes the resolved path to $script:UwpPathCache and
# flushes it atomically to config.json.
# A guard flag ($script:UwpRefreshInProgress) prevents duplicate concurrent scans.
# ------------------------------------------
function Invoke-UwpPathRefresh {
    param(
        [string]$ProcessName,
        [string]$RegistrySearchString = $ProcessName
    )

    $key = $ProcessName.ToLower()

    # Guard: skip if a refresh for this process name is already in flight
    if ($script:UwpRefreshInProgress.ContainsKey($key) -and $script:UwpRefreshInProgress[$key]) {
        return
    }

    $script:UwpRefreshInProgress[$key] = $true

    # Capture references needed inside the closure (ThreadPool runs in a separate thread)
    $cacheRef          = $script:UwpPathCache
    $inProgressRef     = $script:UwpRefreshInProgress
    $configPath        = Join-Path $env:APPDATA "SAMISH\config.json"
    $procName          = $ProcessName
    $regSearch         = $RegistrySearchString
    $cacheKey          = $key

    $workItem = [System.Threading.WaitCallback] {
        try {
            $pkg = Get-AppxPackage -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -match $regSearch -or $_.PackageFamilyName -match $regSearch } |
                   Select-Object -First 1

            if ($pkg -and $pkg.InstallLocation -and (Test-Path $pkg.InstallLocation)) {
                $candidate = Get-ChildItem -Path $pkg.InstallLocation -Filter "$procName.exe" `
                             -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

                if ($candidate -and (Test-Path $candidate.FullName)) {
                    # Write result to the shared in-memory cache
                    $cacheRef[$cacheKey] = $candidate.FullName

                    # Flush cache to config.json atomically (Rule 8)
                    try {
                        if (Test-Path -LiteralPath $configPath) {
                            $raw  = Get-Content -LiteralPath $configPath -Raw -ErrorAction Stop
                            $cfg  = $raw | ConvertFrom-Json -ErrorAction Stop

                            # Merge current in-memory cache into the config object
                            if (-not ($cfg.PSObject.Properties.Name -contains "UwpPathCache")) {
                                $cfg | Add-Member -MemberType NoteProperty -Name "UwpPathCache" -Value ([pscustomobject]@{}) -Force
                            }
                            $cfg.UwpPathCache | Add-Member -MemberType NoteProperty -Name $cacheKey `
                                               -Value $candidate.FullName -Force

                            $json = $cfg | ConvertTo-Json -Depth 6
                            $tmp  = $configPath + ".tmp"
                            Set-Content -LiteralPath $tmp -Value $json -Encoding UTF8 -ErrorAction Stop
                            Move-Item -LiteralPath $tmp -Destination $configPath -Force -ErrorAction Stop
                        }
                    }
                    catch {
                        # Config flush failed - in-memory cache is still warm; ignore
                    }
                }
            }
        }
        catch {
            # Entire refresh failed (e.g., locked-down environment) - fail-forward
        }
        finally {
            # Always clear the in-progress guard so future misses can trigger a new refresh
            $inProgressRef[$cacheKey] = $false
        }
    }

    try {
        [System.Threading.ThreadPool]::QueueUserWorkItem($workItem, $null) | Out-Null
    }
    catch {
        # ThreadPool enqueue failed - clear guard immediately
        $script:UwpRefreshInProgress[$key] = $false
    }
}

