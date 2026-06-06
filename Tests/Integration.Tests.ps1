#requires -Version 5.1
# ==============================================================================
# Module: Integration.Tests.ps1
# Purpose: Pester v5 integration tests for SAMISH cross-module workflows.
#          Tests the full install/uninstall sequence, config lifecycle,
#          pre-flight gating, and state-machine transitions with all
#          system dependencies (filesystem, schtasks, processes) fully mocked.
# Inputs: None (self-contained test suite).
# Outputs: Pester test results.
# Error Handling: Pester framework handles assertion failures.
# ==============================================================================

BeforeAll {
    $ModulesDir = Join-Path $PSScriptRoot "..\App\Modules"

    # Load dependencies in the correct order (mirrors Setup.ps1 boot chain)
    . (Join-Path $ModulesDir "App.Control.Common.ps1")
    . (Join-Path $ModulesDir "ConfigBackup.Module.ps1")
    . (Join-Path $ModulesDir "Validation.Module.ps1")
    . (Join-Path $ModulesDir "Logic.ps1")

    # Define stub functions for commands that exist in Setup.ps1 scope
    # These match the real signatures so Pester v5 Mock can override them.
    function Sync-SamishRuntimeFiles {}
    function Write-ConfigJson {
        param($EnableLogging, $LogEverySeconds, $EnableTrayIcon,
              $EnableHotkey, $HotkeyMode, $CustomHotkeyVirtualKey,
              $OperatingMode, $SetupPath, $ActiveProfileId,
              $ProfilesEnabled, $EnableAutoRecovery)
    }
    function Register-SamishEventSource {}
    function Delete-Task { param($TaskNameWithSlash) }
    function Install-TaskFromXml { param($TaskNameNoSlash, $XmlPath) }
    function Remove-StartupShortcut {}
    function Stop-RunningHelperInstances { return 0 }
    function Start-SamishInMode { param($Mode) }
    function Task-Exists { param($TaskNameWithSlash) return $false }
    function Get-StartupShortcutPath { return "C:\fake\shortcut.lnk" }
    function Get-SamishProcessInfo { return @{ Running = $false; Count = 0; Pids = @() } }
    function Stop-SamishTaskIfRunning { param($Mode) }
    function Write-SetupLog { param([string]$text) }
    function Get-ActiveSchemeGuid { return $null }
    function Apply-PowerPlanFixWithBackup { param($PromptUser, $AutoMode) }
    function Handle-PowerPlanPromptIfNeeded { param($result, $AutoMode) }
    function Get-NoPowerPlanChangesStatus { return @{ StatusMessage = "" } }
    function Test-PowerPlanCompatibility {
        param($DisplayOffSeconds, $SleepIdleSeconds, $HibernateIdleSeconds, $GapSeconds)
        return @{ Compatible = $true }
    }
    function Ask-PowerPlanClassicCompatOptIn { return $false }
    function Get-PowerSettingSecondsAC { param($SchemeGuid, $SubGuid, $SettingGuid) return 0 }
    function Log-Always { param([string]$msg) }
    function Save-ContentAtomic {
        param([string]$Path, [string]$Content)
        Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
    }

    # Install path constants (match Setup.ps1 definitions)
    $script:TaskHidden = "\SAMISH\SAMISH-Hidden"
    $script:TaskInteractive = "\SAMISH\SAMISH-Interactive"
    $script:TaskHiddenNoSlash = "SAMISH\SAMISH-Hidden"
    $script:TaskInteractiveNoSlash = "SAMISH\SAMISH-Interactive"
    $script:InstallDir = Join-Path $env:TEMP "SAMISH_IntegrationTests_$(New-Guid)"
    $script:SUB_VIDEO = "7516b95f-f776-4464-8c53-06167f40cc99"
    $script:SUB_SLEEP = "238c9fa8-0aad-41ed-83f4-97be242c8f20"
    $script:VIDEOIDLE = "3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e"
    $script:STANDBYIDLE = "29f6c1db-86da-48c5-9fdb-f2b67b1f44da"
    $script:HIBERNATEIDLE = "9d7815a6-7ee4-497e-8888-515a05f02364"
    $script:MinGapSeconds = 120
}

# ==============================================================================
# Integration Test 1: Full Install Sequence (Hidden Mode)
# ==============================================================================

Describe "Full Install Sequence (Hidden Mode)" {

    BeforeEach {
        $script:syncCalled = $false
        $script:configWritten = $false
        $script:eventSourceRegistered = $false
        $script:tasksDeleted = @()
        $script:taskInstalled = $null
        $script:shortcutRemoved = $false
    }

    It "executes all install steps in the correct order for Hidden mode" {
        Mock Sync-SamishRuntimeFiles { $script:syncCalled = $true }
        Mock Write-ConfigJson { $script:configWritten = $true }
        Mock Register-SamishEventSource { $script:eventSourceRegistered = $true }
        Mock Delete-Task { $script:tasksDeleted += $TaskNameWithSlash }
        Mock Install-TaskFromXml { $script:taskInstalled = $TaskNameNoSlash; return @{ ExitCode = 0 } }
        Mock Remove-StartupShortcut { $script:shortcutRemoved = $true }
        Mock Stop-RunningHelperInstances { return 0 }
        Mock Start-SamishInMode {}
        Mock Get-ActiveSchemeGuid { return $null }
        Mock Write-SetupLog {}

        $result = Invoke-SamishInstall `
            -Mode "Hidden" `
            -OperatingMode "Graceful" `
            -EnableLogging $true `
            -LogEverySeconds 30 `
            -EnableTray $false `
            -EnableHotkey $false `
            -HotkeyMode "ScrollLock" `
            -CustomHotkeyVk 0x91

        $result.Success | Should -Be $true
        $result.StatusMessage | Should -Match "Install complete"

        # Verify all steps were called
        $script:syncCalled | Should -Be $true
        $script:configWritten | Should -Be $true
        $script:eventSourceRegistered | Should -Be $true
        $script:tasksDeleted.Count | Should -Be 2  # Both old tasks deleted before re-install
        $script:taskInstalled | Should -Match "Hidden"
        $script:shortcutRemoved | Should -Be $true
    }

    It "executes Interactive mode with engine start" {
        $script:engineStarted = $false

        Mock Sync-SamishRuntimeFiles {}
        Mock Write-ConfigJson {}
        Mock Register-SamishEventSource {}
        Mock Delete-Task {}
        Mock Install-TaskFromXml { return @{ ExitCode = 0 } }
        Mock Remove-StartupShortcut {}
        Mock Stop-RunningHelperInstances { return 0 }
        Mock Start-Sleep {}
        Mock Start-SamishInMode { $script:engineStarted = $true }
        Mock Get-ActiveSchemeGuid { return $null }
        Mock Write-SetupLog {}

        $result = Invoke-SamishInstall `
            -Mode "Interactive" `
            -OperatingMode "Graceful" `
            -EnableLogging $false `
            -LogEverySeconds 30 `
            -EnableTray $true `
            -EnableHotkey $true `
            -HotkeyMode "ScrollLock" `
            -CustomHotkeyVk 0x91

        $result.Success | Should -Be $true
        $script:engineStarted | Should -Be $true
    }

    It "returns failure result when Sync-SamishRuntimeFiles throws" {
        Mock Sync-SamishRuntimeFiles { throw "Engine file missing" }
        Mock Write-SetupLog {}

        $result = Invoke-SamishInstall `
            -Mode "Hidden" `
            -OperatingMode "Graceful" `
            -EnableLogging $false `
            -LogEverySeconds 30 `
            -EnableTray $false `
            -EnableHotkey $false `
            -HotkeyMode "ScrollLock" `
            -CustomHotkeyVk 0x91

        $result.Success | Should -Be $false
        $result.StatusMessage | Should -Match "Install failed"
    }
}

# ==============================================================================
# Integration Test 2: Install -> Uninstall State Machine
# ==============================================================================

Describe "Install then Uninstall State Machine" {

    It "install followed by uninstall returns clean state" {
        # Phase 1: Install
        Mock Sync-SamishRuntimeFiles {}
        Mock Write-ConfigJson {}
        Mock Register-SamishEventSource {}
        Mock Delete-Task {}
        Mock Install-TaskFromXml { return @{ ExitCode = 0 } }
        Mock Remove-StartupShortcut {}
        Mock Stop-RunningHelperInstances { return 0 }
        Mock Start-SamishInMode {}
        Mock Get-ActiveSchemeGuid { return $null }
        Mock Write-SetupLog {}
        Mock Start-Sleep {}

        $installResult = Invoke-SamishInstall `
            -Mode "Hidden" `
            -OperatingMode "Graceful" `
            -EnableLogging $false `
            -LogEverySeconds 30 `
            -EnableTray $false `
            -EnableHotkey $false `
            -HotkeyMode "ScrollLock" `
            -CustomHotkeyVk 0x91

        $installResult.Success | Should -Be $true

        # Phase 2: Uninstall (tasks now exist)
        Mock Task-Exists { return $true }
        Mock Test-Path { return $false }
        Mock Get-SamishProcessInfo { return @{ Running = $true } }
        Mock Stop-SamishTaskIfRunning {}
        Mock Stop-RunningHelperInstances { return 1 }

        $uninstallResult = Invoke-SamishUninstall

        $uninstallResult.Success | Should -Be $true
        $uninstallResult.StoppedCount | Should -Be 1
        $uninstallResult.StatusMessage | Should -Match "Uninstall complete"
    }
}

# ==============================================================================
# Integration Test 3: Config Lifecycle (Corrupt -> AutoFix -> Backup -> Verify)
# ==============================================================================

Describe "Config Lifecycle: Corrupt to Fixed with Backup" {

    BeforeEach {
        $script:testDir = Join-Path $env:TEMP "SAMISH_IntegTest_Config_$(New-Guid)"
        New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null
        $script:ConfigPath = Join-Path $script:testDir "config.json"
    }

    AfterEach {
        if (Test-Path $script:testDir) {
            Remove-Item $script:testDir -Force -Recurse -ErrorAction SilentlyContinue
        }
    }

    It "full lifecycle: malformed JSON -> merge defaults -> schema fix -> backup -> verify fixed" {
        # Step 1: Write corrupt JSON
        Set-Content -Path $script:ConfigPath -Value '{ "EnableLogging": "notabool", "OperatingMode": "INVALID" }' -Encoding UTF8

        # Step 2: Read and repair (mirrors SAMISH.ps1 boot Apply-ConfigFromFile logic)
        $raw = Get-Content -LiteralPath $script:ConfigPath -Raw
        $cfg = $raw | ConvertFrom-Json
        $cfg = Merge-ConfigDefaults -Config $cfg
        $schemaRes = Test-ConfigSchema -Config $cfg -AutoFix

        # Step 3: Verify schema detected and fixed the issues
        $schemaRes.FixedKeys | Should -Not -BeNullOrEmpty
        $schemaRes.FixedKeys | Should -Contain "EnableLogging"
        $schemaRes.FixedKeys | Should -Contain "OperatingMode"

        # Step 4: Create backup before persisting fix (mirrors SAMISH.ps1 backup logic)
        $ts = (Get-Date).ToString("yyyyMMdd-HHmmss")
        $backupPath = $script:ConfigPath + ".backup-$ts"
        Copy-Item -LiteralPath $script:ConfigPath -Destination $backupPath -Force

        # Step 5: Save fixed config
        $json = $cfg | ConvertTo-Json -Depth 3
        Save-ContentAtomic -Path $script:ConfigPath -Content $json

        # Verify: Backup contains original corrupt values
        $backupCfg = (Get-Content -LiteralPath $backupPath -Raw) | ConvertFrom-Json
        $backupCfg.EnableLogging | Should -Be "notabool"
        $backupCfg.OperatingMode | Should -Be "INVALID"

        # Verify: Fixed config has corrected values
        $fixedCfg = (Get-Content -LiteralPath $script:ConfigPath -Raw) | ConvertFrom-Json
        $fixedCfg.EnableLogging | Should -BeOfType [bool]
        $fixedCfg.OperatingMode | Should -Be "Graceful"

        # Verify: Merged defaults injected missing keys
        $fixedCfg.PSObject.Properties.Name | Should -Contain "EnableTrayIcon"
        $fixedCfg.PSObject.Properties.Name | Should -Contain "HotkeyMode"
        $fixedCfg.PSObject.Properties.Name | Should -Contain "ActiveProfileId"
    }
}

# ==============================================================================
# Integration Test 4: Pre-flight Gating of Install
# ==============================================================================

Describe "Pre-flight Gating Blocks Install When Prerequisites Fail" {

    BeforeEach {
        $script:testDir = Join-Path $env:TEMP "SAMISH_IntegTest_PreFlight_$(New-Guid)"
        New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null
    }

    AfterEach {
        if (Test-Path $script:testDir) {
            Remove-Item $script:testDir -Force -Recurse -ErrorAction SilentlyContinue
        }
    }

    It "pre-flight failure prevents install from proceeding" {
        $emptyPkg = Join-Path $script:testDir "empty_pkg"
        New-Item -ItemType Directory -Path $emptyPkg -Force | Out-Null
        $installTarget = Join-Path $script:testDir "install"
        New-Item -ItemType Directory -Path $installTarget -Force | Out-Null

        # Run pre-flight against an empty package (no SAMISH.ps1, no XML)
        $preflight = Test-InstallPreFlight -PackageDir $emptyPkg -InstallDir $installTarget -Mode "Hidden"
        $preflight.IsValid | Should -Be $false
        $preflight.Errors.Count | Should -BeGreaterOrEqual 2

        # Simulate the gate: if pre-flight fails, do NOT call install
        $installWasCalled = $false
        if ($preflight.IsValid) {
            $installWasCalled = $true
        }
        $installWasCalled | Should -Be $false

        # Verify error message is human-readable
        $msg = Format-PreFlightResult -Result $preflight -Operation "Install"
        $msg | Should -Match "Install cannot proceed"
        $msg | Should -Match "SAMISH.ps1"
    }

    It "pre-flight success allows install to proceed" {
        $validPkg = Join-Path $script:testDir "valid_pkg"
        New-Item -ItemType Directory -Path $validPkg -Force | Out-Null
        Set-Content -Path (Join-Path $validPkg "SAMISH.ps1") -Value "# engine" -Encoding UTF8
        Set-Content -Path (Join-Path $validPkg "SAMISH-HiddenTask.xml") -Value "<xml/>" -Encoding UTF8
        New-Item -ItemType Directory -Path (Join-Path $validPkg "Modules") -Force | Out-Null

        $installTarget = Join-Path $script:testDir "install"
        New-Item -ItemType Directory -Path $installTarget -Force | Out-Null

        $preflight = Test-InstallPreFlight -PackageDir $validPkg -InstallDir $installTarget -Mode "Hidden"
        $preflight.IsValid | Should -Be $true

        # Gate passes: install would proceed
        $installWouldProceed = $preflight.IsValid
        $installWouldProceed | Should -Be $true
    }
}

# ==============================================================================
# Integration Test 5: Classic Mode Power Plan Interaction
# ==============================================================================

Describe "Classic Mode Install Triggers Power Plan Check" {

    It "Classic mode invokes power plan fix workflow" {
        $script:ppFixCalled = $false
        $script:ppPromptHandled = $false

        Mock Sync-SamishRuntimeFiles {}
        Mock Write-ConfigJson {}
        Mock Register-SamishEventSource {}
        Mock Delete-Task {}
        Mock Install-TaskFromXml { return @{ ExitCode = 0 } }
        Mock Remove-StartupShortcut {}
        Mock Stop-RunningHelperInstances { return 0 }
        Mock Start-SamishInMode {}
        Mock Write-SetupLog {}
        Mock Start-Sleep {}
        Mock Apply-PowerPlanFixWithBackup {
            $script:ppFixCalled = $true
            return @{ StatusMessage = "Power plan updated." }
        }
        Mock Handle-PowerPlanPromptIfNeeded {
            $script:ppPromptHandled = $true
            return @{ StatusMessage = "Power plan updated." }
        }

        $result = Invoke-SamishInstall `
            -Mode "Hidden" `
            -OperatingMode "Classic" `
            -EnableLogging $false `
            -LogEverySeconds 30 `
            -EnableTray $false `
            -EnableHotkey $false `
            -HotkeyMode "ScrollLock" `
            -CustomHotkeyVk 0x91

        $result.Success | Should -Be $true
        $script:ppFixCalled | Should -Be $true
        $script:ppPromptHandled | Should -Be $true
        $result.StatusMessage | Should -Match "Power plan"
    }

    It "Graceful mode skips power plan fix when compatible" {
        Mock Sync-SamishRuntimeFiles {}
        Mock Write-ConfigJson {}
        Mock Register-SamishEventSource {}
        Mock Delete-Task {}
        Mock Install-TaskFromXml { return @{ ExitCode = 0 } }
        Mock Remove-StartupShortcut {}
        Mock Stop-RunningHelperInstances { return 0 }
        Mock Start-SamishInMode {}
        Mock Get-ActiveSchemeGuid { return "381b4222-f694-41f0-9685-ff5bb260df2e" }
        Mock Get-PowerSettingSecondsAC { return 1800 }
        Mock Write-SetupLog {}
        Mock Start-Sleep {}
        Mock Test-PowerPlanCompatibility { return @{ Compatible = $true } }
        Mock Apply-PowerPlanFixWithBackup {}

        $result = Invoke-SamishInstall `
            -Mode "Hidden" `
            -OperatingMode "Graceful" `
            -EnableLogging $false `
            -LogEverySeconds 30 `
            -EnableTray $false `
            -EnableHotkey $false `
            -HotkeyMode "ScrollLock" `
            -CustomHotkeyVk 0x91

        $result.Success | Should -Be $true
        # Should NOT mention power plan when compatible
        Should -Invoke Apply-PowerPlanFixWithBackup -Times 0
    }
}

# ==============================================================================
# Integration Test 6: Uninstall with Nothing Installed
# ==============================================================================

Describe "Uninstall Edge Cases" {

    It "returns NothingToUninstall when system is completely clean" {
        Mock Task-Exists { return $false }
        Mock Get-StartupShortcutPath { return "C:\fake\shortcut.lnk" }
        Mock Test-Path { return $false }
        Mock Get-SamishProcessInfo { return @{ Running = $false; Count = 0; Pids = @() } }
        Mock Write-SetupLog {}

        $result = Invoke-SamishUninstall

        $result.NothingToUninstall | Should -Be $true
        $result.Success | Should -Be $false  # NothingToUninstall means Success stays false
    }

    It "handles process stop failure gracefully during uninstall" {
        Mock Task-Exists { return $true }
        Mock Get-StartupShortcutPath { return "C:\fake\shortcut.lnk" }
        Mock Test-Path { return $false }
        Mock Get-SamishProcessInfo { return @{ Running = $true } }
        Mock Stop-SamishTaskIfRunning { throw "Access denied" }
        Mock Stop-RunningHelperInstances { return 0 }
        Mock Start-Sleep {}
        Mock Delete-Task {}
        Mock Remove-StartupShortcut {}
        Mock Write-SetupLog {}

        # Should not throw -- fail-forward
        $result = Invoke-SamishUninstall

        $result.Success | Should -Be $true
        $result.StatusMessage | Should -Match "Uninstall complete"
    }
}
