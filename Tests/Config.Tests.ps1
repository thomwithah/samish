#requires -Version 5.1
# ==============================================================================
# Module: Config.Tests.ps1
# Purpose: Pester v5 unit tests for configuration management functions in
#          ConfigBackup.Module.ps1 (Merge-ConfigDefaults, Test-ConfigSchema).
# Inputs: None (self-contained test suite).
# Outputs: Pester test results.
# Error Handling: Pester framework handles assertion failures.
# ==============================================================================

BeforeAll {
    $ModulesDir = Join-Path $PSScriptRoot "..\App\Modules"

    # Stub functions that ConfigBackup.Module.ps1 callers depend on
    function Ensure-InstallFolder {}
    function Write-SetupLog { param($text) }
    function Get-ActiveSchemeGuid { return "381b4222-f694-41f0-9685-ff5bb260df2e" }
    function Get-PowerSettingSecondsAC { param($SchemeGuid, $SubGuid, $SettingGuid); return 600 }

    # PowerPlan GUIDs expected by ConfigBackup.Module.ps1
    $SUB_VIDEO = "7516b95f-f776-4464-8c53-06167f40cc99"
    $VIDEOIDLE = "3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e"
    $SUB_SLEEP = "238c9fa8-0aad-41ed-83f4-97be242c8f20"
    $STANDBYIDLE = "29f6c1db-86da-48c5-9fdb-f2b67b1f44da"
    $HIBERNATEIDLE = "9d7815a6-7ee4-497e-8888-515a05f02364"

    . (Join-Path $ModulesDir "ConfigBackup.Module.ps1")
}

Describe "Merge-ConfigDefaults" {

    It "injects missing keys with default values" {
        $config = [pscustomobject]@{}
        $result = Merge-ConfigDefaults -Config $config

        # Merge-ConfigDefaults returns the mutated config object
        $result.PSObject.Properties.Name | Should -Contain "EnableLogging"
        $result.PSObject.Properties.Name | Should -Contain "LogEverySeconds"
        $result.PSObject.Properties.Name | Should -Contain "EnableTrayIcon"
        $result.PSObject.Properties.Name | Should -Contain "OperatingMode"
        $result.PSObject.Properties.Name | Should -Contain "ActiveProfileId"
        $result.LogEverySeconds | Should -Be 30
        $result.OperatingMode | Should -Be "Graceful"
        $result.ActiveProfileId | Should -Be "BEACN"
    }

    It "preserves existing values when keys already exist" {
        $config = [pscustomobject]@{
            EnableLogging  = $true
            LogEverySeconds = 60
            OperatingMode  = "Classic"
        }
        $result = Merge-ConfigDefaults -Config $config

        $result.EnableLogging | Should -Be $true
        $result.LogEverySeconds | Should -Be 60
        $result.OperatingMode | Should -Be "Classic"
    }

    It "adds GameMode keys when missing" {
        $config = [pscustomobject]@{ EnableLogging = $false }
        $result = Merge-ConfigDefaults -Config $config

        $result.PSObject.Properties.Name | Should -Contain "GameModeEnabled"
        $result.PSObject.Properties.Name | Should -Contain "GameModeList"
    }
}

Describe "Test-ConfigSchema" {

    It "validates a correct config as IsValid" {
        $config = [pscustomobject]@{
            EnableLogging          = $false
            LogEverySeconds        = 30
            EnableTrayIcon         = $true
            EnableHotkey           = $true
            HotkeyMode             = "Custom"
            CustomHotkeyVirtualKey = 0x76
            OperatingMode          = "Graceful"
            EnableAutoRecovery     = $true
            ActiveProfileId        = "BEACN"
            Theme                  = "Normal"
            ProfilesEnabled        = @("BEACN")
            MonitoredApps          = @()
            GameModeEnabled        = $false
            GameModeList           = @()
            WizardCompleted        = $false
            UI_Mode                = "Full"
        }
        $result = Test-ConfigSchema -Config $config
        $result.IsValid | Should -Be $true
        $result.Errors.Count | Should -Be 0
    }

    It "detects invalid type for EnableLogging" {
        $config = [pscustomobject]@{
            EnableLogging = "not_a_bool"
        }
        $result = Test-ConfigSchema -Config $config
        $result.IsValid | Should -Be $false
        $result.Errors.Count | Should -BeGreaterThan 0
        $result.Errors[0] | Should -Match "EnableLogging"
    }

    It "detects out-of-range LogEverySeconds" {
        $config = [pscustomobject]@{
            LogEverySeconds = -5
        }
        $result = Test-ConfigSchema -Config $config
        $result.IsValid | Should -Be $false
        ($result.Errors | Where-Object { $_ -match "LogEverySeconds" }).Count | Should -BeGreaterThan 0
    }

    It "detects invalid OperatingMode enum value" {
        $config = [pscustomobject]@{
            OperatingMode = "TurboMode"
        }
        $result = Test-ConfigSchema -Config $config
        $result.IsValid | Should -Be $false
    }

    It "auto-fixes invalid values when -AutoFix is set" {
        $config = [pscustomobject]@{
            EnableLogging = "not_a_bool"
            OperatingMode = "TurboMode"
        }
        $result = Test-ConfigSchema -Config $config -AutoFix

        $result.FixedKeys | Should -Contain "EnableLogging"
        $result.FixedKeys | Should -Contain "OperatingMode"
        $config.EnableLogging | Should -Be $false
        $config.OperatingMode | Should -Be "Graceful"
    }

    It "warns about unknown config keys" {
        $config = [pscustomobject]@{
            SomeRandomKey = "value"
        }
        $result = Test-ConfigSchema -Config $config
        $result.Warnings.Count | Should -BeGreaterThan 0
        $result.Warnings[0] | Should -Match "SomeRandomKey"
    }

    It "accepts loose boolean values (0, 1, 'true', 'false')" {
        $config = [pscustomobject]@{
            EnableLogging = 1
            EnableTrayIcon = "true"
        }
        $result = Test-ConfigSchema -Config $config
        $result.IsValid | Should -Be $true
        $config.EnableLogging | Should -Be $true
        $config.EnableTrayIcon | Should -Be $true
    }

    It "migrates legacy UI_Mode value 'Basic' to 'Simple'" {
        $config = [pscustomobject]@{
            UI_Mode = "Basic"
        }
        $result = Test-ConfigSchema -Config $config
        $config.UI_Mode | Should -Be "Simple"
        $result.FixedKeys | Should -Contain "UI_Mode (Basic->Simple)"
    }
}
