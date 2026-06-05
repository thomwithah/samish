#requires -Version 5.1
# ==============================================================================
# Module: UwpMedia.Tests.ps1
# Purpose: Pester v5 unit tests verifying state-aware SMTC command dispatch
#          inside Invoke-SmtcActionForProcess. Confirms that Play and Pause
#          commands are skipped when the session is already in the target state,
#          and dispatched when a state change is actually needed.
# Inputs: None (self-contained test suite).
# Outputs: Pester test results.
# Error Handling: Pester framework handles assertion failures.
# ==============================================================================

BeforeAll {
    $ModulesDir = Join-Path $PSScriptRoot "..\App\Modules"

    # Stub Get-SmtcSessionManager so the module loads without WinRT available.
    function Get-SmtcSessionManager { return $null }

    # Stub Wait-UwpAsync before dot-sourcing (required for module load).
    function Wait-UwpAsync { param($AsyncOp, $ResultType); return $true }

    . (Join-Path $ModulesDir "UwpMedia.Module.ps1")

    # Re-define Wait-UwpAsync AFTER dot-sourcing so it overrides the module's
    # own copy. Records the AsyncOp sentinel and returns $true so callers succeed.
    # This is the version that actually runs during tests.
    function Wait-UwpAsync {
        param($AsyncOp, $ResultType)
        $script:LastAsyncOp = $AsyncOp
        return $true
    }

    # Build a minimal fake SMTC session object with a controllable PlaybackStatus.
    # TryPlayAsync and TryPauseAsync each return a distinct sentinel string so
    # tests can verify which async path -- if any -- was reached.
    function New-FakeSmtcSession {
        param([int]$Status)
        # Embed the status as a NoteProperty on the session itself so the
        # GetPlaybackInfo ScriptMethod can read it via $this without needing
        # a closure over a local variable.
        $fakeSession = [PSCustomObject]@{ CapturedStatus = $Status }
        $fakeSession | Add-Member -MemberType ScriptMethod -Name GetPlaybackInfo -Value {
            return [PSCustomObject]@{ PlaybackStatus = $this.CapturedStatus }
        }
        $fakeSession | Add-Member -MemberType ScriptMethod -Name TryPlayAsync    -Value { return "SENTINEL_PLAY" }
        $fakeSession | Add-Member -MemberType ScriptMethod -Name TryPauseAsync   -Value { return "SENTINEL_PAUSE" }
        return $fakeSession
    }
}

Describe "Invoke-SmtcActionForProcess -- state-aware dispatch" {

    BeforeEach {
        # Reset the sentinel before every test.
        $script:LastAsyncOp = $null
    }

    Context "When no SMTC session is found for the process" {
        BeforeEach {
            Mock Get-SmtcSessionForProcess { return $null }
        }

        It "returns false and does not reach any async call" {
            $result = Invoke-SmtcActionForProcess -ProcessName "spotify" -Action "Play"
            $result           | Should -Be $false
            $script:LastAsyncOp | Should -BeNullOrEmpty
        }
    }

    # -----------------------------------------------------------------------
    # Play action
    # -----------------------------------------------------------------------
    Context "Play action -- session already Playing (status 4)" {
        BeforeEach {
            $fakeSession = New-FakeSmtcSession -Status 4
            Mock Get-SmtcSessionForProcess { return $fakeSession }
        }

        It "returns true and skips TryPlayAsync (sentinel is null)" {
            $result = Invoke-SmtcActionForProcess -ProcessName "spotify" -Action "Play"
            $result              | Should -Be $true
            # Guard returned early; Wait-UwpAsync was never called, so no sentinel.
            $script:LastAsyncOp | Should -BeNullOrEmpty
        }
    }

    Context "Play action -- session Paused (status 5)" {
        BeforeEach {
            $fakeSession = New-FakeSmtcSession -Status 5
            Mock Get-SmtcSessionForProcess { return $fakeSession }
        }

        It "returns true and dispatches TryPlayAsync (sentinel is SENTINEL_PLAY)" {
            $result = Invoke-SmtcActionForProcess -ProcessName "spotify" -Action "Play"
            $result              | Should -Be $true
            $script:LastAsyncOp | Should -Be "SENTINEL_PLAY"
        }
    }

    Context "Play action -- session Stopped (status 3)" {
        BeforeEach {
            $fakeSession = New-FakeSmtcSession -Status 3
            Mock Get-SmtcSessionForProcess { return $fakeSession }
        }

        It "returns true and dispatches TryPlayAsync (sentinel is SENTINEL_PLAY)" {
            $result = Invoke-SmtcActionForProcess -ProcessName "chrome" -Action "Play"
            $result              | Should -Be $true
            $script:LastAsyncOp | Should -Be "SENTINEL_PLAY"
        }
    }

    # -----------------------------------------------------------------------
    # Pause action
    # -----------------------------------------------------------------------
    Context "Pause action -- session already Paused (status 5)" {
        BeforeEach {
            $fakeSession = New-FakeSmtcSession -Status 5
            Mock Get-SmtcSessionForProcess { return $fakeSession }
        }

        It "returns true and skips TryPauseAsync (sentinel is null)" {
            $result = Invoke-SmtcActionForProcess -ProcessName "chrome" -Action "Pause"
            $result              | Should -Be $true
            $script:LastAsyncOp | Should -BeNullOrEmpty
        }
    }

    Context "Pause action -- session already Stopped (status 3)" {
        BeforeEach {
            $fakeSession = New-FakeSmtcSession -Status 3
            Mock Get-SmtcSessionForProcess { return $fakeSession }
        }

        It "returns true and skips TryPauseAsync (sentinel is null)" {
            $result = Invoke-SmtcActionForProcess -ProcessName "chrome" -Action "Pause"
            $result              | Should -Be $true
            $script:LastAsyncOp | Should -BeNullOrEmpty
        }
    }

    Context "Pause action -- session currently Playing (status 4)" {
        BeforeEach {
            $fakeSession = New-FakeSmtcSession -Status 4
            Mock Get-SmtcSessionForProcess { return $fakeSession }
        }

        It "returns true and dispatches TryPauseAsync (sentinel is SENTINEL_PAUSE)" {
            $result = Invoke-SmtcActionForProcess -ProcessName "spotify" -Action "Pause"
            $result              | Should -Be $true
            $script:LastAsyncOp | Should -Be "SENTINEL_PAUSE"
        }
    }

    # -----------------------------------------------------------------------
    # Unknown status (0) -- guard should not block; command must be attempted
    # -----------------------------------------------------------------------
    Context "Play action -- status Unknown (0)" {
        BeforeEach {
            $fakeSession = New-FakeSmtcSession -Status 0
            Mock Get-SmtcSessionForProcess { return $fakeSession }
        }

        It "dispatches TryPlayAsync when status is unknown" {
            $result = Invoke-SmtcActionForProcess -ProcessName "spotify" -Action "Play"
            $result              | Should -Be $true
            $script:LastAsyncOp | Should -Be "SENTINEL_PLAY"
        }
    }

    Context "Pause action -- status Unknown (0)" {
        BeforeEach {
            $fakeSession = New-FakeSmtcSession -Status 0
            Mock Get-SmtcSessionForProcess { return $fakeSession }
        }

        It "dispatches TryPauseAsync when status is unknown" {
            $result = Invoke-SmtcActionForProcess -ProcessName "chrome" -Action "Pause"
            $result              | Should -Be $true
            $script:LastAsyncOp | Should -Be "SENTINEL_PAUSE"
        }
    }
}
