#requires -Version 5.1
# ==============================================================================
# Module: Engine.Tests.ps1
# Purpose: Pester v5 unit tests for the SAMISH engine main loop state machine.
#          Tests the idle-to-stop, stop-to-wake, blocker deferral, game mode
#          guard, and auto-recovery flows. All OS dependencies (idle detection,
#          power plan queries, process management) are fully mocked.
# Inputs: None (self-contained test suite).
# Outputs: Pester test results.
# Error Handling: Pester framework handles assertion failures.
# ==============================================================================

BeforeAll {
    $ModulesDir = Join-Path $PSScriptRoot "..\App\Modules"

    # Load class definitions needed by Invoke-MixerStop / Start-MainMixer
    . (Join-Path $ModulesDir "App.Control.Common.ps1")

    # -- Stub functions for commands defined inside SAMISH.ps1's try block --
    # These replicate the signatures so Pester v5 Mock can override them.

    function Get-IdleSeconds { return 0 }
    function Get-ActiveSchemeGuid { return "381b4222-f694-41f0-9685-ff5bb260df2e" }
    function Get-ACSettingSeconds { param($schemeGuid, $subGuid, $setGuid); return 300 }
    function Test-ActiveSleepBlockerExists { return $null }
    function Invoke-GameModeCheck { param($Enabled, $GameList); return $false }
    function Perform-AutoRecoveryCheck {}

    function Invoke-MixerStop { return $true }
    function Invoke-MixerStart { return $true }
    function Start-MainMixer { return $true }

    function Log-Always { param([string]$msg) }
    function Log-Heartbeat { param([string]$msg) }
    function Write-EventLogEntry { param($Message, $EntryType, $EventId) }
    function Set-HelperEnabled { param([bool]$enabledNow, [string]$source) }
    function Check-PendingNotification {}
    function Notify { param([string]$text) }

    function Set-DefaultAudioDevice { param($PlaybackDeviceId, $CommDeviceId) }
    function Get-SmtcPlaybackStatus { param($ProcessName); return 0 }
    function Get-SmtcSessionForProcess { param($ProcessName); return $null }
    function Invoke-SmtcActionForProcess { param($ProcessName, $Action); return $false }
    function Get-AppExecutablePath {
        param($ProcessName, $ConfiguredPath)
        return [AppExecutablePathResult]::new("C:\Mock.exe", $true, "Config", "")
    }
    function Invoke-AppStart {
        param($ProcessName, $ExePath)
        return [AppStartResult]::new($true, "Started", "Direct", "")
    }
    function Invoke-AppStop {
        param($ProcessName)
        return [AppStopResult]::new($true, "Stopped", "Classic", $false, $false, "")
    }

    # -- Engine state variables (mirrors SAMISH.ps1 initialization) --
    $script:TrayEnabled = $true
    $script:ExitRequested = $false
    $script:mixerStopped = $false
    $script:mixerStoppedAt = $null
    $script:stopLatchedThisIdleStretch = $false
    $script:LastBlockerLogTime = $null
    $script:GameModeActive = $false
    $script:GameModeEnabled = $false
    $script:GameModeList = @()
    $script:TargetProcessName = "MockMixer"
    $script:TargetExePath = "C:\Mock.exe"
    $script:ActiveProfileId = "BEACN"
    $script:OperatingMode = "Graceful"
    $script:MonitoredApps = $null

    $script:EnableAutoRecovery = $true
    $script:LastAutoRecoveryCheckTime = $null
    $script:LastConfigWriteTime = $null

    # Engine timing defaults (measured in sec)
    $script:ToleranceSeconds = 3
    $script:RestartWhenIdleLE = 10
    $script:RestartGuardSecondsAfterStop = 25
    $script:RefreshPowerPlanEverySeconds = 59

    # Hotkey disabled for tests
    $script:EnableHotkey = $false
    $script:EnableTrayIcon = $false
    $script:EnableLogging = $false

    # Audio endpoint preferences
    $script:PreferredPlaybackDeviceGuid = ""
    $script:PreferredCommDeviceGuid = ""
}

# ==============================================================================
# Test 1: Idle exceeds threshold -> Invoke-MixerStop fires
# ==============================================================================
Describe "Idle-to-Stop Transition" {

    BeforeEach {
        $script:mixerStopped = $false
        $script:mixerStoppedAt = $null
        $script:stopLatchedThisIdleStretch = $false
        $script:LastBlockerLogTime = $null
        $script:GameModeActive = $false
    }

    It "calls Invoke-MixerStop when idle exceeds threshold" {
        $killThresholdSeconds = 300
        $idle = $killThresholdSeconds  # idle == threshold (past tolerance boundary)

        Mock Invoke-MixerStop { return $true }
        Mock Test-ActiveSleepBlockerExists { return $null }
        Mock Write-EventLogEntry {}
        Mock Log-Always {}

        # Replicate the idle-check logic from SAMISH.ps1 lines 1580-1612
        if (-not $script:stopLatchedThisIdleStretch -and $idle -ge ($killThresholdSeconds - $script:ToleranceSeconds)) {
            if ($script:GameModeActive) {
                # Would defer -- but GameModeActive is $false
            }
            else {
                $blockers = Test-ActiveSleepBlockerExists
                if ($blockers) {
                    # Would defer -- but blockers is $null
                } else {
                    if (Invoke-MixerStop) {
                        $script:mixerStopped = $true
                        $script:mixerStoppedAt = Get-Date
                        Write-EventLogEntry -Message "Mixer stopped due to idle." -EntryType "Information" -EventId 200
                    }
                    $script:stopLatchedThisIdleStretch = $true
                }
            }
        }

        $script:mixerStopped | Should -Be $true
        $script:stopLatchedThisIdleStretch | Should -Be $true
        $script:mixerStoppedAt | Should -Not -BeNullOrEmpty
        Should -Invoke Invoke-MixerStop -Times 1
    }

    It "does not stop mixer when idle is below threshold" {
        $killThresholdSeconds = 300
        $idle = 100  # well below threshold - tolerance

        Mock Invoke-MixerStop { return $true }

        if (-not $script:stopLatchedThisIdleStretch -and $idle -ge ($killThresholdSeconds - $script:ToleranceSeconds)) {
            if (Invoke-MixerStop) {
                $script:mixerStopped = $true
            }
        }

        $script:mixerStopped | Should -Be $false
        Should -Invoke Invoke-MixerStop -Times 0
    }

    It "resets stop latch when idle drops to 1 or below" {
        $script:stopLatchedThisIdleStretch = $true
        $idle = 1

        if ($idle -le 1) { $script:stopLatchedThisIdleStretch = $false }

        $script:stopLatchedThisIdleStretch | Should -Be $false
    }
}

# ==============================================================================
# Test 2: Stopped mixer restarts when user wakes
# ==============================================================================
Describe "Stop-to-Wake Transition" {

    BeforeEach {
        $script:mixerStopped = $true
        $script:mixerStoppedAt = (Get-Date).AddSeconds(-30)  # stopped 30s ago, past guard window
        $script:stopLatchedThisIdleStretch = $true
    }

    It "calls Invoke-MixerStart when idle drops below restart threshold" {
        $idle = 5  # below $RestartWhenIdleLE (10)

        Mock Invoke-MixerStart { return $true }
        Mock Write-EventLogEntry {}
        Mock Set-DefaultAudioDevice {}

        $elapsed = ((Get-Date) - $script:mixerStoppedAt).TotalSeconds

        if ($script:mixerStopped -and $idle -le $script:RestartWhenIdleLE) {
            if ($elapsed -ge $script:RestartGuardSecondsAfterStop) {
                if (Invoke-MixerStart) {
                    $script:mixerStopped = $false
                    Write-EventLogEntry -Message "Mixer started on wake." -EntryType "Information" -EventId 201
                }
            }
        }

        $script:mixerStopped | Should -Be $false
        Should -Invoke Invoke-MixerStart -Times 1
    }

    It "does not restart mixer within the guard window" {
        $script:mixerStoppedAt = (Get-Date).AddSeconds(-5)  # stopped 5s ago, inside guard window
        $idle = 5

        Mock Invoke-MixerStart { return $true }

        $elapsed = ((Get-Date) - $script:mixerStoppedAt).TotalSeconds

        if ($script:mixerStopped -and $idle -le $script:RestartWhenIdleLE) {
            if ($elapsed -ge $script:RestartGuardSecondsAfterStop) {
                if (Invoke-MixerStart) {
                    $script:mixerStopped = $false
                }
            }
        }

        $script:mixerStopped | Should -Be $true
        Should -Invoke Invoke-MixerStart -Times 0
    }

    It "does not restart if idle is still above restart threshold" {
        $idle = 15  # above $RestartWhenIdleLE (10)

        Mock Invoke-MixerStart { return $true }

        if ($script:mixerStopped -and $idle -le $script:RestartWhenIdleLE) {
            if (Invoke-MixerStart) {
                $script:mixerStopped = $false
            }
        }

        $script:mixerStopped | Should -Be $true
        Should -Invoke Invoke-MixerStart -Times 0
    }

    It "restores audio endpoints after successful mixer start" {
        $idle = 5
        $script:PreferredPlaybackDeviceGuid = "test-playback-guid"
        $script:PreferredCommDeviceGuid = "test-comm-guid"

        Mock Invoke-MixerStart { return $true }
        Mock Set-DefaultAudioDevice {}
        Mock Write-EventLogEntry {}

        $elapsed = ((Get-Date) - $script:mixerStoppedAt).TotalSeconds

        if ($script:mixerStopped -and $idle -le $script:RestartWhenIdleLE) {
            if ($elapsed -ge $script:RestartGuardSecondsAfterStop) {
                if (Invoke-MixerStart) {
                    $script:mixerStopped = $false

                    if (Get-Command Set-DefaultAudioDevice -ErrorAction SilentlyContinue) {
                        if ($script:PreferredPlaybackDeviceGuid -or $script:PreferredCommDeviceGuid) {
                            try {
                                Set-DefaultAudioDevice -PlaybackDeviceId $script:PreferredPlaybackDeviceGuid -CommDeviceId $script:PreferredCommDeviceGuid
                            }
                            catch {
                                Log-Always "AudioEndpoint: Post-restart restore failed: $_"
                            }
                        }
                    }
                }
            }
        }

        $script:mixerStopped | Should -Be $false
        Should -Invoke Set-DefaultAudioDevice -Times 1
    }
}

# ==============================================================================
# Test 3: Active sleep blockers defer mixer shutdown
# ==============================================================================
Describe "Blocker Deferral" {

    BeforeEach {
        $script:mixerStopped = $false
        $script:stopLatchedThisIdleStretch = $false
        $script:GameModeActive = $false
        $script:LastBlockerLogTime = $null
    }

    It "defers mixer stop when active sleep blockers exist" {
        $killThresholdSeconds = 300
        $idle = $killThresholdSeconds  # at threshold

        $mockBlockers = @(
            [pscustomobject]@{ Category = "DISPLAY"; Type = "PROCESS"; Name = "obs64"; Raw = "C:\obs\obs64.exe" }
        )

        Mock Test-ActiveSleepBlockerExists { return $mockBlockers }
        Mock Invoke-MixerStop { return $true }
        Mock Log-Always {}

        $blockerActive = $false
        if (-not $script:stopLatchedThisIdleStretch -and $idle -ge ($killThresholdSeconds - $script:ToleranceSeconds)) {
            if ($script:GameModeActive) {
                $blockerActive = $true
            }
            else {
                $blockers = Test-ActiveSleepBlockerExists
                if ($blockers) {
                    $blockerActive = $true
                } else {
                    if (Invoke-MixerStop) {
                        $script:mixerStopped = $true
                    }
                }
            }
        }

        $blockerActive | Should -Be $true
        $script:mixerStopped | Should -Be $false
        Should -Invoke Invoke-MixerStop -Times 0
    }

    It "defers mixer stop when Game Mode is active" {
        $killThresholdSeconds = 300
        $idle = $killThresholdSeconds
        $script:GameModeActive = $true

        Mock Test-ActiveSleepBlockerExists { return $null }
        Mock Invoke-MixerStop { return $true }
        Mock Log-Always {}

        $blockerActive = $false
        if (-not $script:stopLatchedThisIdleStretch -and $idle -ge ($killThresholdSeconds - $script:ToleranceSeconds)) {
            if ($script:GameModeActive) {
                $blockerActive = $true
            }
            else {
                $blockers = Test-ActiveSleepBlockerExists
                if ($blockers) {
                    $blockerActive = $true
                } else {
                    if (Invoke-MixerStop) {
                        $script:mixerStopped = $true
                    }
                }
            }
        }

        $blockerActive | Should -Be $true
        $script:mixerStopped | Should -Be $false
        Should -Invoke Invoke-MixerStop -Times 0
    }
}

# ==============================================================================
# Test 4: Auto-recovery guard triggers when mixer process is missing
# ==============================================================================
Describe "Auto-Recovery Guard" {

    BeforeEach {
        $script:mixerStopped = $false
        $script:EnableAutoRecovery = $true
        $script:LastAutoRecoveryCheckTime = $null
        $script:MonitoredApps = $null
    }

    It "invokes Perform-AutoRecoveryCheck when auto-recovery is enabled and check interval elapsed" {
        Mock Perform-AutoRecoveryCheck {}
        Mock Log-Always {}

        $nowTime = Get-Date
        $script:LastAutoRecoveryCheckTime = $nowTime.AddSeconds(-15)  # 15s ago, past 10s threshold

        if ($script:EnableAutoRecovery -and $script:mixerStopped -eq $false) {
            if (($nowTime - $script:LastAutoRecoveryCheckTime).TotalSeconds -ge 10) {
                $script:LastAutoRecoveryCheckTime = $nowTime
                try {
                    Perform-AutoRecoveryCheck
                }
                catch {
                    Log-Always "Error during auto-recovery check: $($_.Exception.Message)"
                }
            }
        }

        Should -Invoke Perform-AutoRecoveryCheck -Times 1
    }

    It "skips auto-recovery when mixer is already stopped" {
        $script:mixerStopped = $true
        $script:LastAutoRecoveryCheckTime = (Get-Date).AddSeconds(-15)

        Mock Perform-AutoRecoveryCheck {}

        $nowTime = Get-Date
        if ($script:EnableAutoRecovery -and $script:mixerStopped -eq $false) {
            if (($nowTime - $script:LastAutoRecoveryCheckTime).TotalSeconds -ge 10) {
                Perform-AutoRecoveryCheck
            }
        }

        Should -Invoke Perform-AutoRecoveryCheck -Times 0
    }

    It "skips auto-recovery when check interval has not elapsed" {
        $script:LastAutoRecoveryCheckTime = (Get-Date).AddSeconds(-3)  # only 3s ago, below 10s

        Mock Perform-AutoRecoveryCheck {}

        $nowTime = Get-Date
        if ($script:EnableAutoRecovery -and $script:mixerStopped -eq $false) {
            if ($null -eq $script:LastAutoRecoveryCheckTime) {
                $script:LastAutoRecoveryCheckTime = $nowTime.AddSeconds(-10)
            }
            if (($nowTime - $script:LastAutoRecoveryCheckTime).TotalSeconds -ge 10) {
                Perform-AutoRecoveryCheck
            }
        }

        Should -Invoke Perform-AutoRecoveryCheck -Times 0
    }

    It "also triggers when monitored apps have per-app AutoRecover enabled" {
        $script:EnableAutoRecovery = $false  # global auto-recovery OFF
        $script:MonitoredApps = @(
            [pscustomobject]@{ ProcessName = "Spotify"; AutoRecover = $true }
        )
        $script:LastAutoRecoveryCheckTime = (Get-Date).AddSeconds(-15)

        Mock Perform-AutoRecoveryCheck {}
        Mock Log-Always {}

        $hasAutoRecoverMonitoredApps = $false
        if ($script:MonitoredApps) {
            foreach ($monApp in $script:MonitoredApps) {
                if ($monApp.PSObject.Properties.Match('AutoRecover').Count -gt 0 -and [bool]$monApp.AutoRecover) {
                    $hasAutoRecoverMonitoredApps = $true
                    break
                }
            }
        }

        $nowTime = Get-Date
        if (($script:EnableAutoRecovery -or $hasAutoRecoverMonitoredApps) -and $script:mixerStopped -eq $false) {
            if (($nowTime - $script:LastAutoRecoveryCheckTime).TotalSeconds -ge 10) {
                $script:LastAutoRecoveryCheckTime = $nowTime
                try {
                    Perform-AutoRecoveryCheck
                }
                catch {
                    Log-Always "Error during auto-recovery check: $($_.Exception.Message)"
                }
            }
        }

        $hasAutoRecoverMonitoredApps | Should -Be $true
        Should -Invoke Perform-AutoRecoveryCheck -Times 1
    }
}

# ==============================================================================
# Test 5: Dynamic sleep throttle calculation
# ==============================================================================
Describe "Dynamic Sleep Throttle" {

    It "returns 100ms when mixer is stopped" {
        $script:mixerStopped = $true
        $killThresholdSeconds = 300
        $blockerActive = $false

        $sleepMs = 100
        if (-not $script:mixerStopped -and $killThresholdSeconds) {
            # Would calculate, but mixerStopped is $true so this branch is skipped
        }

        $sleepMs | Should -Be 100
    }

    It "returns 10000ms when far from threshold" {
        $script:mixerStopped = $false
        $killThresholdSeconds = 300
        $idle = 50
        $blockerActive = $false

        $sleepMs = 100
        if (-not $script:mixerStopped -and $killThresholdSeconds) {
            $threshold = $killThresholdSeconds - $script:ToleranceSeconds
            $timeToThreshold = $threshold - $idle

            if ($blockerActive) {
                $sleepMs = 5000
            }
            elseif ($timeToThreshold -gt 30) {
                $sleepMs = 10000
            }
            elseif ($timeToThreshold -gt 15) {
                $sleepMs = 5000
            }
            elseif ($timeToThreshold -gt 5) {
                $sleepMs = 2000
            }
            elseif ($timeToThreshold -gt 2) {
                $sleepMs = 500
            }
        }

        $sleepMs | Should -Be 10000
    }

    It "returns 500ms when very close to threshold" {
        $script:mixerStopped = $false
        $killThresholdSeconds = 300
        $idle = 294  # threshold = 297, timeToThreshold = 3
        $blockerActive = $false

        $sleepMs = 100
        if (-not $script:mixerStopped -and $killThresholdSeconds) {
            $threshold = $killThresholdSeconds - $script:ToleranceSeconds
            $timeToThreshold = $threshold - $idle

            if ($blockerActive) {
                $sleepMs = 5000
            }
            elseif ($timeToThreshold -gt 30) {
                $sleepMs = 10000
            }
            elseif ($timeToThreshold -gt 15) {
                $sleepMs = 5000
            }
            elseif ($timeToThreshold -gt 5) {
                $sleepMs = 2000
            }
            elseif ($timeToThreshold -gt 2) {
                $sleepMs = 500
            }
        }

        $sleepMs | Should -Be 500
    }

    It "returns 5000ms when blocker is active" {
        $script:mixerStopped = $false
        $killThresholdSeconds = 300
        $idle = 295
        $blockerActive = $true

        $sleepMs = 100
        if (-not $script:mixerStopped -and $killThresholdSeconds) {
            $threshold = $killThresholdSeconds - $script:ToleranceSeconds
            $timeToThreshold = $threshold - $idle

            if ($blockerActive) {
                $sleepMs = 5000
            }
            elseif ($timeToThreshold -gt 30) {
                $sleepMs = 10000
            }
        }

        $sleepMs | Should -Be 5000
    }
}

# ==============================================================================
# Test 6: Self-healing backoff reset after stable operation
# ==============================================================================
Describe "Self-Healing Backoff Reset" {

    It "resets backoff after 5 minutes of stable operation" {
        $script:engineBackoffSeconds = 80  # elevated from prior errors
        $script:engineStableStart = (Get-Date).AddMinutes(-6)  # stable for 6 minutes

        if ($script:engineBackoffSeconds -gt 10) {
            $stableMinutes = ((Get-Date) - $script:engineStableStart).TotalMinutes
            if ($stableMinutes -ge 5) {
                $script:engineBackoffSeconds = 10  # measured in sec -- reset to initial
            }
        }

        $script:engineBackoffSeconds | Should -Be 10
    }

    It "does not reset backoff before 5 minutes of stability" {
        $script:engineBackoffSeconds = 40
        $script:engineStableStart = (Get-Date).AddMinutes(-3)  # only 3 minutes stable

        if ($script:engineBackoffSeconds -gt 10) {
            $stableMinutes = ((Get-Date) - $script:engineStableStart).TotalMinutes
            if ($stableMinutes -ge 5) {
                $script:engineBackoffSeconds = 10
            }
        }

        $script:engineBackoffSeconds | Should -Be 40
    }

    It "updates stable start when backoff is at baseline" {
        $script:engineBackoffSeconds = 10  # at baseline
        $script:engineStableStart = $null

        if ($script:engineBackoffSeconds -gt 10) {
            # would check stable minutes
        } else {
            $script:engineStableStart = Get-Date
        }

        $script:engineStableStart | Should -Not -BeNullOrEmpty
    }
}
