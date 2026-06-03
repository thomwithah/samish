#requires -Version 5.1
# ==============================================================================
# Module: Logic.Tests.ps1
# Purpose: Pester v5 unit tests for the pure business logic functions in Logic.ps1.
#          All external dependencies (filesystem, processes, registry, tasks) are
#          mocked so tests run safely without modifying the live system.
# Inputs: None (self-contained test suite).
# Outputs: Pester test results.
# Error Handling: Pester framework handles assertion failures.
# ==============================================================================

BeforeAll {
    # Load shared dependencies that Logic.ps1 expects to be present
    $ModulesDir = Join-Path $PSScriptRoot "..\App\Modules"

    # Load App.Control.Common.ps1 for class definitions (AppStartResult, etc.)
    . (Join-Path $ModulesDir "App.Control.Common.ps1")

    # Load the module under test
    . (Join-Path $ModulesDir "Logic.ps1")
}

Describe "Get-LogIntervalFromUI" {

    It "returns 0 for Verbose selection" {
        $result = Get-LogIntervalFromUI -DropdownText "Verbose (every loop)" -CustomText "30"
        $result | Should -Be 0
    }

    It "returns 30 for 30-second selection" {
        $result = Get-LogIntervalFromUI -DropdownText "Every 30 seconds" -CustomText "30"
        $result | Should -Be 30
    }

    It "returns 60 for 60-second selection" {
        $result = Get-LogIntervalFromUI -DropdownText "Every 60 seconds" -CustomText "30"
        $result | Should -Be 60
    }

    It "delegates to parser for custom values" {
        Mock Parse-LogEverySecondsOrThrow { return 45 }
        $result = Get-LogIntervalFromUI -DropdownText "Custom seconds..." -CustomText "45"
        $result | Should -Be 45
    }

    It "throws on invalid custom value" {
        Mock Parse-LogEverySecondsOrThrow { throw "Invalid value" }
        { Get-LogIntervalFromUI -DropdownText "Custom seconds..." -CustomText "abc" } | Should -Throw
    }
}

Describe "Get-HotkeyVkFromUI" {

    BeforeAll {
        # Set up the VkMap lookup table that the real app uses
        $script:VkMap = @{
            "ScrollLock" = 0x91
            "PauseBreak" = 0x13
            "F12"        = 0x7B
        }
    }

    It "returns ScrollLock VK for ScrollLock selection" {
        $result = Get-HotkeyVkFromUI -HotkeyMode "ScrollLock"
        $result | Should -Be 0x91
    }

    It "returns F12 VK for F12 selection" {
        $result = Get-HotkeyVkFromUI -HotkeyMode "F12"
        $result | Should -Be 0x7B
    }

    It "delegates to parser for Custom selection" {
        Mock Parse-CustomHotkeyToVk { return 0x77 }
        $result = Get-HotkeyVkFromUI -HotkeyMode "Custom" -CustomKeyText "F8"
        $result | Should -Be 0x77
    }
}

Describe "Invoke-SamishUninstall" {

    BeforeAll {
        # Mock all external dependencies so tests never touch the live system
        $script:TaskHidden = "\SAMISH\SAMISH-Hidden"
        $script:TaskInteractive = "\SAMISH\SAMISH-Interactive"
    }

    It "returns NothingToUninstall when no tasks, shortcuts, or processes exist" {
        Mock Task-Exists { return $false }
        Mock Get-StartupShortcutPath { return "C:\fake\shortcut.lnk" }
        Mock Test-Path { return $false }
        Mock Get-SamishProcessInfo { return @{ Running = $false } }
        Mock Write-SetupLog {}

        $result = Invoke-SamishUninstall

        $result.NothingToUninstall | Should -Be $true
        $result.StatusMessage | Should -Match "Nothing to uninstall"
    }

    It "stops processes and removes tasks when installed" {
        Mock Task-Exists { return $true }
        Mock Get-StartupShortcutPath { return "C:\fake\shortcut.lnk" }
        Mock Test-Path { return $false }
        Mock Get-SamishProcessInfo { return @{ Running = $true } }
        Mock Stop-SamishTaskIfRunning {}
        Mock Stop-RunningHelperInstances { return 2 }
        Mock Start-Sleep {}
        Mock Delete-Task {}
        Mock Remove-StartupShortcut {}
        Mock Write-SetupLog {}

        $result = Invoke-SamishUninstall

        $result.Success | Should -Be $true
        $result.StoppedCount | Should -Be 2
        $result.StatusMessage | Should -Match "Uninstall complete"
    }
}

Describe "Invoke-DiagnosticReportCompilation" {

    It "returns failure when temp directory creation fails" {
        $script:InstallDir = "C:\FakeInstallDir_DoesNotExist"
        $script:ConfigPath = "C:\FakeInstallDir_DoesNotExist\config.json"

        Mock New-Item { throw "Access denied" }
        Mock Test-Path { return $false }
        Mock Remove-Item {}
        Mock Write-SetupLog {}

        $result = Invoke-DiagnosticReportCompilation

        $result.Success | Should -Be $false
        $result.ErrorMessage | Should -Match "Could not create temporary directory"
    }
}
