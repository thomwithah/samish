# ==========================================
# SAMISH Sleep & Hibernate Diagnostics Module
# ==========================================

function Get-ActiveSleepBlockers {
    param(
        [string[]]$AutomatedAppNames = @()
    )
    # Runs powercfg /requests and parses ALL active sleep/hibernate blockers.
    # Returns an array of blocker custom objects (Apps, Drivers, Services).

    $rawLines = powercfg /requests 2>$null
    $lines = if ($rawLines) { @($rawLines) } else { @() }

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

    # Discover common browser/media apps that are running but might not be blocking sleep
    $discoveredApps = @()
    $commonApps = @("chrome", "msedge", "firefox", "spotify", "vlc", "itunes")
    foreach ($appName in $commonApps) {
        $procs = Get-Process -Name $appName -ErrorAction SilentlyContinue
        if ($procs) {
            $proc = $procs[0]
            $displayName = $proc.ProcessName
            $dispName = switch ($displayName.ToLower()) {
                "chrome" { "Google Chrome" }
                "msedge" { "Microsoft Edge" }
                "firefox" { "Firefox" }
                "spotify" { "Spotify" }
                "vlc" { "VLC Media Player" }
                "itunes" { "iTunes" }
                default { $displayName }
            }
            $discoveredApps += [pscustomobject]@{
                ProcessName    = $proc.ProcessName
                DisplayName    = $dispName
                ExecutableName = "$($proc.ProcessName).exe"
                Reason         = "Not actively blocking sleep (idle)."
            }
        }
    }

    # Query active WinRT SMTC session sources
    try {
        [void][System.Reflection.Assembly]::LoadWithPartialName("System.Runtime.WindowsRuntime")
        $smtcType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType=WindowsRuntime]
        $asTaskMethods = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq "AsTask" }
        $asyncOp = $smtcType::RequestAsync()
        $asTaskMethod = $asTaskMethods | Where-Object {
            $params = $_.GetParameters()
            $params.Count -eq 1 -and $params[0].ParameterType.Name -eq 'IAsyncOperation`1'
        }
        # Double backtick for PowerShell string escaping of the generic class name in AsTask matching
        $genericMethod = $asTaskMethod.MakeGenericMethod($smtcType)
        $task = $genericMethod.Invoke($null, @($asyncOp))
        $task.Wait()
        $manager = $task.Result
        if ($manager) {
            $sessions = $manager.GetSessions()
            foreach ($session in $sessions) {
                $sourceApp = $session.SourceAppUserModelId
                if ($sourceApp) {
                    $cleanName = $sourceApp
                    if ($cleanName -match "([^\\]+)\.exe$") {
                        $cleanName = $Matches[1]
                    }
                    elseif ($cleanName -match "^([^\!]+)\!") {
                        $cleanName = $Matches[1]
                    }
                    if ($cleanName -match "^Spotify") { $cleanName = "spotify" }
                    elseif ($cleanName -match "Chrome") { $cleanName = "chrome" }
                    elseif ($cleanName -match "Edge") { $cleanName = "msedge" }
                    elseif ($cleanName -match "Firefox") { $cleanName = "firefox" }

                    $procs = Get-Process -Name $cleanName -ErrorAction SilentlyContinue
                    if ($procs) {
                        $proc = $procs[0]
                        if (-not ($discoveredApps | Where-Object { $_.ProcessName.ToLower() -eq $cleanName.ToLower() })) {
                            $dispName = switch ($cleanName.ToLower()) {
                                "chrome" { "Google Chrome" }
                                "msedge" { "Microsoft Edge" }
                                "firefox" { "Firefox" }
                                "spotify" { "Spotify" }
                                "vlc" { "VLC Media Player" }
                                "itunes" { "iTunes" }
                                default { $proc.ProcessName }
                            }
                            $discoveredApps += [pscustomobject]@{
                                ProcessName    = $proc.ProcessName
                                DisplayName    = $dispName
                                ExecutableName = "$($proc.ProcessName).exe"
                                Reason         = "Not actively blocking sleep (idle)."
                            }
                        }
                    }
                }
            }
        }
    }
    catch {}

    # Append non-blocking discovered apps to the blockers list if not already present
    foreach ($app in $discoveredApps) {
        # Skip if the idle app is already automated by SAMISH
        if ($AutomatedAppNames -and ($AutomatedAppNames -contains $app.ProcessName)) {
            continue
        }
        $existing = $blockers | Where-Object { $_.ProcessName -eq $app.ProcessName -and $_.BlockerType -eq "App" }
        if (-not $existing) {
            $blockers += [pscustomobject]@{
                BlockerType    = "App"
                DisplayName    = $app.DisplayName
                ProcessName    = $app.ProcessName
                ExecutableName = $app.ExecutableName
                Section        = "NONE"
                Reason         = $app.Reason
                RawEntry       = $app.ExecutableName
                BlockerKey     = $app.ProcessName
                IsNotBlocking  = $true
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
            # Note: The name may contain spaces (e.g. "Legacy Kernel Caller" or "BECAN Mic").
            # The request types are always the trailing tokens that match standard power request keywords.
            $parts = $line -split '\s+'
            
            $requestKeywords = @('DISPLAY', 'SYSTEM', 'AWAYMODE', 'EXECUTION', 'PERFBOOST', 'ACTIVELOCKSCREEN')
            $nameTokens = @()
            $requestTokens = @()
            
            # Read tokens from right to left
            $inRequests = $true
            for ($i = $parts.Count - 1; $i -ge 0; $i--) {
                $token = $parts[$i]
                if ($inRequests -and $i -gt 0 -and ($requestKeywords -contains $token.ToUpper())) {
                    $requestTokens = @($token) + $requestTokens
                }
                else {
                    $inRequests = $false
                    $nameTokens = @($token) + $nameTokens
                }
            }
            
            $name = $nameTokens -join ' '
            $requests = $requestTokens -join ' '

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

function Get-SystemPowerDiagnostics {
    # Gathers system-wide telemetry using elevated powercfg calls
    
    # 1. System Sleep Support
    $sleepSupportLines = powercfg /a 2>$null
    $sleepSupport = @()
    if ($sleepSupportLines) {
        $activeSection = $false
        foreach ($line in $sleepSupportLines) {
            $line = $line.Trim()
            if ($line -match "The following sleep states are available on this system:") {
                $activeSection = $true
                continue
            }
            if ($activeSection -and $line -match "The following sleep states are not available on this system:") {
                $activeSection = $false
                break
            }
            if ($activeSection -and (-not [string]::IsNullOrWhiteSpace($line))) {
                $sleepSupport += $line
            }
        }
    }

    # 2. Last Wake Source
    $lastWakeLines = powercfg /lastwake 2>$null
    $lastWake = "Unknown"
    if ($lastWakeLines) {
        foreach ($line in $lastWakeLines) {
            if ($line -match "^\s*Type:\s*(.+)$") {
                $lastWake = $Matches[1].Trim()
            }
            if ($line -match "^\s*Friendly Name:\s*(.+)$") {
                $lastWake = $Matches[1].Trim()
                break # Friendly name is usually the most descriptive
            }
        }
        if ($lastWake -eq "Unknown" -and $lastWakeLines.Count -ge 2) {
            $lastWake = $lastWakeLines[1].Trim()
        }
    }

    # 2.5 Historical Sleep/Wake cycles (Kernel-Power Event Logs)
    $historyList = @()
    try {
        $events = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName=@('Microsoft-Windows-Kernel-Power', 'Microsoft-Windows-Power-Troubleshooter'); Id=@(1,42)} -MaxEvents 100 -ErrorAction SilentlyContinue
        if ($events) {
            # Sort events descending (newest first)
            $events = @($events) | Sort-Object TimeCreated -Descending
            
            $i = 0
            while ($i -lt $events.Count) {
                $e = $events[$i]
                if ($e.Id -eq 1) {
                    $wakeTime = $e.TimeCreated
                    
                    # Parse Wake Source friendly text
                    $wakeSource = "Unknown"
                    try {
                        $xml = [xml]$e.ToXml()

                        # 1. Try WakeSourceText (most descriptive — e.g. device name or timer owner)
                        $sourceNode = $xml.SelectSingleNode("//*[local-name()='Data'][@Name='WakeSourceText']")
                        if ($sourceNode -and -not [string]::IsNullOrEmpty($sourceNode.InnerText.Trim())) {
                            $wakeSource = $sourceNode.InnerText.Trim()
                        }

                        # 2. Try WakeTimerOwner (set when a scheduled task or app triggered the wake)
                        if ([string]::IsNullOrEmpty($wakeSource) -or $wakeSource -eq "Unknown") {
                            $timerOwnerNode = $xml.SelectSingleNode("//*[local-name()='Data'][@Name='WakeTimerOwner']")
                            $timerContextNode = $xml.SelectSingleNode("//*[local-name()='Data'][@Name='WakeTimerContext']")
                            $ownerText = if ($timerOwnerNode) { $timerOwnerNode.InnerText.Trim() } else { "" }
                            $contextText = if ($timerContextNode) { $timerContextNode.InnerText.Trim() } else { "" }
                            if (-not [string]::IsNullOrEmpty($ownerText)) {
                                $wakeSource = if (-not [string]::IsNullOrEmpty($contextText)) {
                                    "Wake Timer: $ownerText ($contextText)"
                                } else {
                                    "Wake Timer: $ownerText"
                                }
                            }
                        }

                        # 3. Try WakeSourceType numeric code (hardware device types)
                        if ([string]::IsNullOrEmpty($wakeSource) -or $wakeSource -eq "Unknown") {
                            $typeNode = $xml.SelectSingleNode("//*[local-name()='Data'][@Name='WakeSourceType']")
                            if ($typeNode) {
                                $wakeSource = switch ($typeNode.InnerText.Trim()) {
                                    "1" { "Power Button" }
                                    "2" { "Sleep Timer" }
                                    "3" { "Screen Input / Lid" }
                                    "4" { "Hardware Device" }
                                    "5" { "Wake Timer" }
                                    "6" { "RTC Alarm" }
                                    "7" { "Battery / Charge" }
                                    default { "" }  # fall through to state-based decoding
                                }
                            }
                        }

                        # 4. Decode EffectiveState / TargetState and HiberPagesWritten for friendly fallback
                        if ([string]::IsNullOrEmpty($wakeSource) -or $wakeSource -eq "Unknown") {
                            $effectiveStateNode = $xml.SelectSingleNode("//*[local-name()='Data'][@Name='EffectiveState']")
                            $targetStateNode    = $xml.SelectSingleNode("//*[local-name()='Data'][@Name='TargetState']")
                            $hiberPagesNode     = $xml.SelectSingleNode("//*[local-name()='Data'][@Name='HiberPagesWritten']")

                            $effectiveState = if ($effectiveStateNode) { [int]$effectiveStateNode.InnerText } else { -1 }
                            $targetState    = if ($targetStateNode)    { [int]$targetStateNode.InnerText }    else { -1 }
                            $hiberPages     = if ($hiberPagesNode)     { [int64]$hiberPagesNode.InnerText }   else { 0 }

                            # EffectiveState/TargetState: 0=S0(Working), 1=S1, 2=S2, 3=S3(Sleep), 4=S4(Hibernate), 5=S5(Off)
                            # HiberPagesWritten > 0 is the strongest signal of a real hibernate cycle
                            if ($hiberPages -gt 0 -or $effectiveState -eq 4 -or $targetState -eq 4) {
                                $wakeSource = "Resume from Hibernate"
                            } elseif ($effectiveState -eq 3 -or $targetState -eq 3) {
                                $wakeSource = "Resume from Sleep (S3)"
                            } elseif ($effectiveState -eq 1 -or $effectiveState -eq 2) {
                                $wakeSource = "Resume from Light Sleep (S$effectiveState)"
                            } elseif ($effectiveState -eq 0) {
                                $wakeSource = "Fast Resume (Connected Standby)"
                            } else {
                                $wakeSource = "Resume (source not logged)"
                            }
                        }
                    } catch {
                        $wakeSource = "Unknown (parse error)"
                    }
                    
                    $sleepTime = $null
                    $durationStr = "N/A"
                    
                    # Find the next oldest Sleep event (Event 42)
                    $j = $i + 1
                    while ($j -lt $events.Count) {
                        if ($events[$j].Id -eq 42) {
                            $sleepTime = $events[$j].TimeCreated
                            $i = $j # Skip past this sleep event in outer loop
                            break
                        }
                        $j++
                    }
                    
                    if ($sleepTime) {
                        $diff = $wakeTime - $sleepTime
                        $durationStr = "{0:d2}:{1:d2}:{2:d2}" -f $diff.Hours, $diff.Minutes, $diff.Seconds
                        if ($diff.Days -gt 0) {
                            $durationStr = "{0}d " -f $diff.Days + $durationStr
                        }
                    }
                    
                    $historyList += [pscustomobject]@{
                        SleepTime   = if ($sleepTime) { $sleepTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "Unknown" }
                        WakeTime    = $wakeTime.ToString("yyyy-MM-dd HH:mm:ss")
                        Duration    = $durationStr
                        WakeSource  = $wakeSource
                    }
                    
                    if ($historyList.Count -ge 5) { break }
                }
                $i++
            }
        }
    } catch {}

    # 3. Armed Wake Devices
    $armedDevicesLines = powercfg /devicequery wake_armed 2>$null
    $armedDevices = @()
    if ($armedDevicesLines) {
        foreach ($line in $armedDevicesLines) {
            if (-not [string]::IsNullOrWhiteSpace($line) -and $line -ne "NONE") {
                $armedDevices += $line.Trim()
            }
        }
    }

    # 4. Active Wake Timers
    $wakeTimersLines = powercfg /waketimers 2>$null
    $wakeTimers = @()
    if ($wakeTimersLines) {
        $currentTimer = ""
        foreach ($line in $wakeTimersLines) {
            if ($line -match "^Timer set by (.+)$") {
                if ($currentTimer) { $wakeTimers += $currentTimer }
                $currentTimer = $line.Trim()
            }
            elseif ($line -match "^\s+Reason:\s*(.+)$") {
                $currentTimer += " - " + $Matches[1].Trim()
            }
        }
        if ($currentTimer) { $wakeTimers += $currentTimer }
    }

    return [pscustomobject]@{
        SleepSupport = $sleepSupport
        LastWake = $lastWake
        ArmedDevices = $armedDevices
        WakeTimers = $wakeTimers
        SleepHistory = $historyList
    }
}
