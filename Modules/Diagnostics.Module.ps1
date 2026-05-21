# ==========================================
# SAMISH Sleep & Hibernate Diagnostics Module
# ==========================================

function Get-ActiveSleepBlockers {
    # Runs powercfg /requests and parses ALL active sleep/hibernate blockers.
    # Returns an array of blocker custom objects (Apps, Drivers, Services).

    $lines = powercfg /requests 2>$null
    if (-not $lines) { return @() }

    $blockers      = @()
    $currentSection = "UNKNOWN"  # powercfg output section (DISPLAY, SYSTEM, etc.)
    $currentType    = "Unknown"  # [PROCESS], [DRIVER], [SERVICE]

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        # Detect Section Header (e.g. DISPLAY:, SYSTEM:, EXECUTION:)
        if ($line -match '^(DISPLAY|SYSTEM|AWAYMODE|EXECUTION|PERFBOOST|ACTIVELOCKSCREEN):$') {
            $currentSection = $Matches[1]
            continue
        }

        # Detect blocker type tag  [PROCESS] / [DRIVER] / [SERVICE]
        if ($line -match '^\[(PROCESS|DRIVER|SERVICE)\]\s*(.*)$') {
            $currentType = $Matches[1]
            $rawEntry    = $Matches[2].Trim()

            # Look ahead for the reason text on the next non-empty line
            $reason = ""
            for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                $nextLine = $lines[$j].Trim()
                if ([string]::IsNullOrWhiteSpace($nextLine)) { continue }
                if ($nextLine -match '^\[\w+\]' -or
                    $nextLine -match '^(DISPLAY|SYSTEM|AWAYMODE|EXECUTION|PERFBOOST|ACTIVELOCKSCREEN):$') {
                    break
                }
                $reason = $nextLine
                $i = $j
                break
            }

            # Build the blocker object based on type
            switch ($currentType) {
                'PROCESS' {
                    $exeName  = [System.IO.Path]::GetFileName($rawEntry)
                    $procName = [System.IO.Path]::GetFileNameWithoutExtension($exeName)
                    if (-not ($blockers | Where-Object { $_.BlockerKey -eq $procName -and $_.BlockerType -eq 'App' })) {
                        $blockers += [pscustomobject]@{
                            BlockerType    = 'App'
                            DisplayName    = $procName
                            ProcessName    = $procName
                            ExecutableName = $exeName
                            Section        = $currentSection
                            Reason         = if ($reason) { $reason } else { "Active audio stream or execution request." }
                            RawEntry       = $rawEntry
                            BlockerKey     = $procName
                        }
                    }
                }
                'DRIVER' {
                    $key = "$rawEntry|$currentSection"
                    if (-not ($blockers | Where-Object { $_.BlockerKey -eq $key })) {
                        $blockers += [pscustomobject]@{
                            BlockerType    = 'Driver'
                            DisplayName    = if ($rawEntry) { $rawEntry } else { "Unknown Driver" }
                            ProcessName    = $null
                            ExecutableName = $null
                            Section        = $currentSection
                            Reason         = if ($reason) { $reason } else { "Active driver power request preventing sleep or hibernation." }
                            RawEntry       = $rawEntry
                            BlockerKey     = $key
                        }
                    }
                }
                'SERVICE' {
                    $key = "$rawEntry|$currentSection"
                    if (-not ($blockers | Where-Object { $_.BlockerKey -eq $key })) {
                        $blockers += [pscustomobject]@{
                            BlockerType    = 'Service'
                            DisplayName    = if ($rawEntry) { $rawEntry } else { "Unknown Service" }
                            ProcessName    = $rawEntry
                            ExecutableName = $null
                            Section        = $currentSection
                            Reason         = if ($reason) { $reason } else { "Active service power request preventing sleep or hibernation." }
                            RawEntry       = $rawEntry
                            BlockerKey     = $key
                        }
                    }
                }
            }
        }
    }

    return $blockers
}

function Get-SystemOverrides {
    # Returns current powercfg /requestsoverride entries as structured objects.
    $lines = powercfg /requestsoverride 2>$null
    if (-not $lines) { return @() }

    $overrides   = @()
    $currentType = $null

    foreach ($line in $lines) {
        $line = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        if ($line -match '^\[(SERVICE|PROCESS|DRIVER)\]$') {
            $currentType = $Matches[1]
            continue
        }

        if ($currentType -and $line -notmatch '^\[') {
            # Parse: <Name> <RequestType(s)>
            # e.g. "BEACN.EXE DISPLAY SYSTEM AWAYMODE"
            $parts    = $line -split '\s+'
            $name     = $parts[0]
            $requests = $parts[1..($parts.Count - 1)] -join ' '

            $overrides += [pscustomobject]@{
                OverrideType = $currentType
                Name         = $name
                Requests     = $requests
                DisplayLabel = "[$currentType] $name ($requests)"
            }
        }
    }

    return $overrides
}

function Add-SystemOverride {
    param(
        [string]$BlockerType,  # PROCESS | DRIVER | SERVICE
        [string]$Name,
        [string[]]$Requests    # e.g. @('SYSTEM','DISPLAY','AWAYMODE')
    )
    # powercfg /requestsoverride <CALLER_TYPE> <NAME> [REQUEST ...]
    $requestStr = $Requests -join ' '
    powercfg /requestsoverride $BlockerType $Name $requestStr 2>$null
}

function Remove-SystemOverride {
    param(
        [string]$BlockerType,
        [string]$Name
    )
    # Removing: call with no request types to clear the override
    powercfg /requestsoverride $BlockerType $Name 2>$null
}

function Resolve-ProcessExecutablePath {
    param(
        [string]$ProcessName,
        [string]$ExecutableName
    )

    # 1. Check running process (highest accuracy - it's currently active)
    $proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc) {
        try {
            if ($proc.MainModule -and $proc.MainModule.FileName) {
                $p = $proc.MainModule.FileName
                if (Test-Path $p) { return $p }
            }
        } catch {}
        try {
            if ($proc.Path -and (Test-Path $proc.Path)) { return $proc.Path }
        } catch {}
    }

    # 2. Search Registry (Uninstall entries)
    try {
        $regPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        foreach ($rp in $regPaths) {
            $entries = Get-ItemProperty $rp -ErrorAction SilentlyContinue |
                       Where-Object { $_.DisplayName -match $ProcessName -or $_.Publisher -match $ProcessName }
            foreach ($entry in $entries) {
                if ($entry -and $entry.DisplayIcon) {
                    $iconPath = $entry.DisplayIcon.Split(',')[0].Replace('"','').Trim()
                    if ($iconPath -match '\.exe$' -and (Test-Path $iconPath)) { return $iconPath }
                    $dir = Split-Path $iconPath -ErrorAction SilentlyContinue
                    if ($dir -and (Test-Path $dir)) {
                        $check = Join-Path $dir $ExecutableName
                        if (Test-Path $check) { return $check }
                    }
                }
                if ($entry -and $entry.InstallLocation) {
                    $check = Join-Path $entry.InstallLocation $ExecutableName
                    if (Test-Path $check) { return $check }
                }
            }
        }
    } catch {}

    # 3. Check Common Program Files Folders (shallow scan)
    $searchDirs = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:APPDATA,
        $env:LOCALAPPDATA
    )
    foreach ($sd in $searchDirs) {
        if ($sd -and (Test-Path $sd)) {
            $check = Get-ChildItem -Path $sd -Filter $ExecutableName -Recurse -Depth 2 -ErrorAction SilentlyContinue |
                     Select-Object -First 1
            if ($check -and $check.FullName -and (Test-Path $check.FullName)) {
                return $check.FullName
            }
        }
    }

    # 4. Fallback: user-guided file dialog
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title           = "Locate the executable for: $ProcessName"
    $dialog.Filter          = "Executable Files (*.exe)|*.exe"
    $dialog.FileName        = $ExecutableName
    $dialog.InitialDirectory = $env:ProgramFiles

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        if (Test-Path $dialog.FileName) { return $dialog.FileName }
    }

    return $null
}
