#requires -Version 5.1
# ==============================================================================
# Module: Validation.Module.ps1
# Purpose: Pre-flight validation checks for install/uninstall operations.
#          Returns structured results that callers use to warn users before
#          proceeding. All checks are non-destructive probes.
# Inputs: Called with the current package and install directory paths.
# Outputs: Structured result objects (PSCustomObject) with IsValid, Errors,
#          and Warnings arrays.
# Error Handling: All checks use try/catch with fail-forward design.
#                 Individual check failures are captured in the result object,
#                 never thrown to callers.
# ==============================================================================

function Test-InstallPreFlight {
    <#
    .SYNOPSIS
        Runs all pre-flight checks required before an install/update operation.
        Returns a result object indicating whether it is safe to proceed.

    .PARAMETER PackageDir
        Path to the source package directory (where SAMISH.ps1 and XML templates live).

    .PARAMETER InstallDir
        Path to the target install directory (typically %APPDATA%\SAMISH).

    .PARAMETER Mode
        Install mode: "Hidden" or "Interactive". Determines which XML template is required.

    .OUTPUTS
        [PSCustomObject] with:
          IsValid   : $true if all critical checks pass (safe to proceed)
          Errors    : Array of critical failure strings (install will fail)
          Warnings  : Array of non-critical advisory strings (install may succeed with limitations)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$PackageDir,

        [Parameter(Mandatory)]
        [string]$InstallDir,

        [ValidateSet("Hidden", "Interactive")]
        [string]$Mode = "Hidden"
    )

    $errors   = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()

    # 1. Engine script must exist in package
    try {
        $enginePath = Join-Path $PackageDir "SAMISH.ps1"
        if (-not (Test-Path -LiteralPath $enginePath)) {
            $errors.Add("SAMISH.ps1 not found in the package directory ($PackageDir). The install cannot copy the engine to the target location.")
        }
    }
    catch {
        $errors.Add("Failed to check for SAMISH.ps1: $($_.Exception.Message)")
    }

    # 2. XML task template must exist for the selected mode
    try {
        $xmlName = if ($Mode -eq "Hidden") { "SAMISH-HiddenTask.xml" } else { "SAMISH-InteractiveTask.xml" }
        $xmlPath = Join-Path $PackageDir $xmlName
        if (-not (Test-Path -LiteralPath $xmlPath)) {
            $errors.Add("Task template '$xmlName' not found in the package directory ($PackageDir). The scheduled task cannot be created without this file.")
        }
    }
    catch {
        $errors.Add("Failed to check for XML task template: $($_.Exception.Message)")
    }

    # 3. Install directory must be writable
    try {
        if (-not (Test-Path -LiteralPath $InstallDir)) {
            # Directory does not exist yet; check if we can create it
            try {
                New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
                # Clean up the probe directory only if we just created it and it is empty
                $children = @(Get-ChildItem -LiteralPath $InstallDir -Force -ErrorAction SilentlyContinue)
                if ($children.Count -eq 0) {
                    Remove-Item -LiteralPath $InstallDir -Force -ErrorAction SilentlyContinue
                }
            }
            catch {
                $errors.Add("Cannot create install directory ($InstallDir). Check folder permissions or disk space. Details: $($_.Exception.Message)")
            }
        }
        else {
            # Directory exists; probe write access with a temp file
            $probePath = Join-Path $InstallDir ".samish_preflight_probe"
            try {
                Set-Content -LiteralPath $probePath -Value "probe" -Encoding ASCII -ErrorAction Stop
                Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
            }
            catch {
                $errors.Add("Install directory ($InstallDir) is not writable. Check folder permissions. Details: $($_.Exception.Message)")
            }
        }
    }
    catch {
        $errors.Add("Failed to verify install directory access: $($_.Exception.Message)")
    }

    # 4. schtasks.exe must be accessible
    try {
        $schtasks = Get-Command "schtasks.exe" -ErrorAction SilentlyContinue
        if (-not $schtasks) {
            $errors.Add("schtasks.exe not found on the system PATH. SAMISH requires Windows Task Scheduler to register its background service.")
        }
    }
    catch {
        $warnings.Add("Could not verify schtasks.exe availability: $($_.Exception.Message)")
    }

    # 5. Advisory: Admin privileges (not critical, but some features need it)
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            $warnings.Add("Setup is not running as Administrator. Some features (Event Log registration, device wake control) may be limited.")
        }
    }
    catch {
        # Fail-forward: inability to check admin status is not critical
    }

    # 6. Advisory: Modules directory must exist in package
    try {
        $modulesPath = Join-Path $PackageDir "Modules"
        if (-not (Test-Path -LiteralPath $modulesPath)) {
            $warnings.Add("Modules directory not found in the package ($PackageDir). The engine may not function correctly without its modules.")
        }
    }
    catch {
        # Fail-forward: non-critical check
    }

    return [pscustomobject]@{
        IsValid  = ($errors.Count -eq 0)
        Errors   = @($errors)
        Warnings = @($warnings)
    }
}

function Test-UninstallPreFlight {
    <#
    .SYNOPSIS
        Runs pre-flight checks before an uninstall operation.

    .PARAMETER InstallDir
        Path to the install directory (typically %APPDATA%\SAMISH).

    .OUTPUTS
        [PSCustomObject] with IsValid, Errors, Warnings arrays.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'InstallDir',
        Justification = 'Reserved for API symmetry with Test-InstallPreFlight and future directory-level checks')]
    param(
        [Parameter(Mandatory)]
        [string]$InstallDir
    )

    $errors   = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()

    # 1. schtasks.exe must be accessible (needed to delete tasks)
    try {
        $schtasks = Get-Command "schtasks.exe" -ErrorAction SilentlyContinue
        if (-not $schtasks) {
            $errors.Add("schtasks.exe not found on the system PATH. SAMISH cannot remove its scheduled tasks without Task Scheduler access.")
        }
    }
    catch {
        $warnings.Add("Could not verify schtasks.exe availability: $($_.Exception.Message)")
    }

    # 2. Advisory: Admin privileges for Event Log source removal
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            $warnings.Add("Setup is not running as Administrator. Event Log source removal and telemetry restore may be limited.")
        }
    }
    catch {
        # Fail-forward
    }

    return [pscustomobject]@{
        IsValid  = ($errors.Count -eq 0)
        Errors   = @($errors)
        Warnings = @($warnings)
    }
}

function Format-PreFlightResult {
    <#
    .SYNOPSIS
        Formats a pre-flight result object into a human-readable string
        suitable for display in the status box or a dialog.

    .PARAMETER Result
        The result object from Test-InstallPreFlight or Test-UninstallPreFlight.

    .PARAMETER Operation
        The operation name for the header ("Install" or "Uninstall").

    .OUTPUTS
        [string] Formatted message, or $null if there is nothing to report.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Result,

        [string]$Operation = "Install"
    )

    if ($Result.Errors.Count -eq 0 -and $Result.Warnings.Count -eq 0) {
        return $null
    }

    $lines = [System.Collections.Generic.List[string]]::new()

    if ($Result.Errors.Count -gt 0) {
        $lines.Add("$Operation cannot proceed:")
        $lines.Add("")
        foreach ($err in $Result.Errors) {
            $lines.Add("  - $err")
        }
    }

    if ($Result.Warnings.Count -gt 0) {
        if ($lines.Count -gt 0) { $lines.Add("") }
        $lines.Add("Warnings:")
        $lines.Add("")
        foreach ($warn in $Result.Warnings) {
            $lines.Add("  - $warn")
        }
    }

    return ($lines -join "`r`n")
}
