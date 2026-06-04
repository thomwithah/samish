#requires -Version 5.1
# ==============================================================================
# Module: WizardSync.Tests.ps1
# Purpose: Pester v5 unit and integration tests for First-Run Wizard answers persistence
#          and GUI state synchronization flow.
# Inputs: None (self-contained test suite).
# Outputs: Pester test results.
# Error Handling: Pester framework handles assertion failures.
# ==============================================================================

BeforeAll {
    $script:RealAppDir = Join-Path $PSScriptRoot "..\App"
    $script:TestAppDir = Join-Path $PSScriptRoot "App"
    $script:TempConfigPath = [System.IO.Path]::GetTempFileName()

    # Stub/mock functions needed for FirstRunWizard.ps1 and Setup.ps1 loading
    function Write-SamishSetupTrace { param($Message, $Level) }
    function Save-ContentAtomic { param($Path, $Content) Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8 }
    function Set-BrandTheme { param($Form, $IsCustom) }
    function Task-Exists { param($TaskNameWithSlash) }
    function Complete-SamishSetupUi { param($Form) }

    # Copy App directory to Tests\App so dot-sourced setup loads adapters and profiles correctly
    if (Test-Path -LiteralPath $script:TestAppDir) {
        Remove-Item -LiteralPath $script:TestAppDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $script:TestAppDir -Force | Out-Null
    Copy-Item -Path "$script:RealAppDir\*" -Destination $script:TestAppDir -Recurse -Force

    # Load FirstRunWizard.ps1 from the test app directory
    . (Join-Path $script:TestAppDir "Modules\FirstRunWizard.ps1")
}

AfterAll {
    if (Test-Path -LiteralPath $script:TempConfigPath) {
        Remove-Item -LiteralPath $script:TempConfigPath -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $script:TestAppDir) {
        Remove-Item -LiteralPath $script:TestAppDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "First-Run Wizard Answer Persistence" {
    
    BeforeEach {
        if (Test-Path -LiteralPath $script:TempConfigPath) {
            Remove-Item -LiteralPath $script:TempConfigPath -Force -ErrorAction SilentlyContinue
        }
        # Create empty config
        "{}" | Set-Content -LiteralPath $script:TempConfigPath -Encoding UTF8
    }

    It "should write ActiveProfileId as DEMO when ManageMixer is false" {
        $mockAnswers = [pscustomobject]@{
            UI_Mode          = "Simple"
            ManageMixer      = $false
            MixerDetected    = $false
            DetectedMixers   = @()
            InstallMode      = "Interactive"
            PauseBrowsers    = $false
            BrowsersDetected = @()
        }

        Mock Show-FirstRunWizard { return $mockAnswers }

        $result = Invoke-FirstRunWizardIfNeeded -ConfigPath $script:TempConfigPath -PackageDir $script:TestAppDir

        $result | Should -Not -BeNull
        
        $savedConfig = Get-Content -LiteralPath $script:TempConfigPath -Raw | ConvertFrom-Json
        $savedConfig.ActiveProfileId | Should -Be "DEMO"
        $savedConfig.ProfilesEnabled | Should -Contain "DEMO"
    }

    It "should set EnableTrayIcon and EnableHotkey to true when InstallMode is Interactive" {
        $mockAnswers = [pscustomobject]@{
            UI_Mode          = "Simple"
            ManageMixer      = $false
            MixerDetected    = $false
            DetectedMixers   = @()
            InstallMode      = "Interactive"
            PauseBrowsers    = $false
            BrowsersDetected = @()
        }

        Mock Show-FirstRunWizard { return $mockAnswers }

        $result = Invoke-FirstRunWizardIfNeeded -ConfigPath $script:TempConfigPath -PackageDir $script:TestAppDir
        
        $savedConfig = Get-Content -LiteralPath $script:TempConfigPath -Raw | ConvertFrom-Json
        $savedConfig.EnableTrayIcon | Should -Be $true
        $savedConfig.EnableHotkey | Should -Be $true
    }

    It "should set EnableTrayIcon and EnableHotkey to false when InstallMode is Hidden" {
        $mockAnswers = [pscustomobject]@{
            UI_Mode          = "Simple"
            ManageMixer      = $false
            MixerDetected    = $false
            DetectedMixers   = @()
            InstallMode      = "Hidden"
            PauseBrowsers    = $false
            BrowsersDetected = @()
        }

        Mock Show-FirstRunWizard { return $mockAnswers }

        $result = Invoke-FirstRunWizardIfNeeded -ConfigPath $script:TempConfigPath -PackageDir $script:TestAppDir
        
        $savedConfig = Get-Content -LiteralPath $script:TempConfigPath -Raw | ConvertFrom-Json
        $savedConfig.EnableTrayIcon | Should -Be $false
        $savedConfig.EnableHotkey | Should -Be $false
    }
}

Describe "GUI State Synchronization after Wizard" {

    BeforeAll {
        $script:ConfigDir = Join-Path $env:APPDATA "SAMISH"
        $script:OriginalConfigPath = Join-Path $script:ConfigDir "config.json"
        # Ensure the APPDATA folder exists
        if (-not (Test-Path -LiteralPath $script:ConfigDir)) {
            New-Item -ItemType Directory -Path $script:ConfigDir -Force | Out-Null
        }
    }

    It "should synchronize Interactive install mode and DEMO profile from config.json when global:IsWizardJustCompleted is true" {
        # Clear error stream first
        $error.Clear()

        # 1. Back up existing config
        $backupExists = Test-Path -LiteralPath $script:OriginalConfigPath
        if ($backupExists) {
            if (Test-Path -LiteralPath "$script:OriginalConfigPath.tmp_test") {
                Remove-Item -LiteralPath "$script:OriginalConfigPath.tmp_test" -Force -ErrorAction SilentlyContinue
            }
            Rename-Item -LiteralPath $script:OriginalConfigPath -NewName "config.json.tmp_test" -Force
        }

        # 2. Write a fresh wizard-completed config with Interactive mode and DEMO profile
        $testConfig = @{
            WizardCompleted = $true
            UI_Mode         = "Simple"
            ActiveProfileId = "DEMO"
            ProfilesEnabled = @("DEMO")
            EnableTrayIcon  = $true
            EnableHotkey    = $true
            Theme           = "Normal"
        } | ConvertTo-Json
        Set-Content -LiteralPath $script:OriginalConfigPath -Value $testConfig -Encoding UTF8

        # 3. Set global variables to bypass ShowDialog and mock tasks
        $global:SamishScreenshotMode = $true
        $global:IsWizardJustCompleted = $true
        $global:SamishSkipShowDialog = $true

        # Helper to find profile radio button recursively
        function Get-RadioButtonByTag {
            param($parent, $tag)
            foreach ($ctl in $parent.Controls) {
                if ($ctl -is [System.Windows.Forms.RadioButton] -and $ctl.Tag -eq $tag) {
                    return $ctl
                }
                $res = Get-RadioButtonByTag -parent $ctl -tag $tag
                if ($res) { return $res }
            }
            return $null
        }

        # Mock Task-Exists to simulate no scheduled tasks are installed on the system
        Mock Task-Exists { return $false }

        # Mock Complete-SamishSetupUi so it doesn't dispose our controls/form before we can inspect them
        Mock Complete-SamishSetupUi {
            # Do nothing
        }

        try {
            # 4. Dot-source Setup.ps1 to trigger UI building
            . (Join-Path $PSScriptRoot "..\Setup.ps1")

            Write-Host "Errors during Setup.ps1 dot-sourcing: $($error | Out-String)"

            # Force window handle creation for the form and mode group so RadioButton mutual exclusion is active
            $null = $form.Handle
            $null = $modeGroup.Handle
            $null = $rbHidden.Handle
            $null = $rbInteractive.Handle

            # 5. Invoke Apply-UIFromConfigIfPresent manually since ShowDialog was skipped
            Apply-UIFromConfigIfPresent

            # Print debug info
            Write-Host "All controls in form recursively:"
            function Dump-Controls {
                param($parent, $indent = "")
                foreach ($c in $parent.Controls) {
                    Write-Host "$indent- Name: '$($c.Name)', Type: '$($c.GetType().Name)', Text: '$($c.Text)', Tag: '$($c.Tag)', Checked: $(if ($c -is [System.Windows.Forms.RadioButton] -or $c -is [System.Windows.Forms.CheckBox]) { $c.Checked } else { '' })"
                    Dump-Controls -parent $c -indent "$indent  "
                }
            }
            Dump-Controls -parent $form

            # 6. Assertions on UI states
            $rbInteractive | Should -Not -BeNull
            $rbInteractive.Checked | Should -Be $true
            $rbHidden.Checked | Should -Be $false

            $demoRadio = Get-RadioButtonByTag -parent $form -tag "DEMO"
            $demoRadio | Should -Not -BeNull
            $demoRadio.Checked | Should -Be $true
        }
        finally {
            # Clean up the test config and restore backup
            if (Test-Path -LiteralPath $script:OriginalConfigPath) {
                Remove-Item -LiteralPath $script:OriginalConfigPath -Force -ErrorAction SilentlyContinue
            }
            if ($backupExists) {
                Rename-Item -LiteralPath "$script:OriginalConfigPath.tmp_test" -NewName "config.json" -Force
            }
            # Manually dispose form if it was created
            if ($form) {
                try { $form.Dispose() } catch {}
            }
            $global:SamishScreenshotMode = $false
            $global:IsWizardJustCompleted = $null
            $global:SamishSkipShowDialog = $null
        }
    }
}
