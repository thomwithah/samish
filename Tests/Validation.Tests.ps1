#requires -Version 5.1
# ==============================================================================
# Module: Validation.Tests.ps1
# Purpose: Pester v5 unit tests for the Validation.Module.ps1 pre-flight checks.
# Inputs: None (self-contained test suite).
# Outputs: Pester test results.
# Error Handling: Pester framework handles assertion failures.
# ==============================================================================

BeforeAll {
    $ModulesDir = Join-Path $PSScriptRoot "..\App\Modules"
    . (Join-Path $ModulesDir "Validation.Module.ps1")
}

Describe "Test-InstallPreFlight" {
    BeforeEach {
        $script:testDir = Join-Path $env:TEMP "SAMISH_ValidationTests_$(New-Guid)"
        New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null

        # Create a minimal valid package structure
        $script:pkgDir = Join-Path $script:testDir "pkg"
        New-Item -ItemType Directory -Path $script:pkgDir -Force | Out-Null
        Set-Content -Path (Join-Path $script:pkgDir "SAMISH.ps1") -Value "# engine" -Encoding UTF8
        Set-Content -Path (Join-Path $script:pkgDir "SAMISH-HiddenTask.xml") -Value "<xml/>" -Encoding UTF8
        Set-Content -Path (Join-Path $script:pkgDir "SAMISH-InteractiveTask.xml") -Value "<xml/>" -Encoding UTF8
        New-Item -ItemType Directory -Path (Join-Path $script:pkgDir "Modules") -Force | Out-Null

        $script:installDir = Join-Path $script:testDir "install"
        New-Item -ItemType Directory -Path $script:installDir -Force | Out-Null
    }

    AfterEach {
        if (Test-Path $script:testDir) {
            Remove-Item $script:testDir -Force -Recurse -ErrorAction SilentlyContinue
        }
    }

    It "passes all checks with a valid package structure" {
        $result = Test-InstallPreFlight -PackageDir $script:pkgDir -InstallDir $script:installDir -Mode "Hidden"
        $result.IsValid | Should -Be $true
        $result.Errors.Count | Should -Be 0
    }

    It "returns error when SAMISH.ps1 is missing from package" {
        Remove-Item (Join-Path $script:pkgDir "SAMISH.ps1") -Force
        $result = Test-InstallPreFlight -PackageDir $script:pkgDir -InstallDir $script:installDir -Mode "Hidden"
        $result.IsValid | Should -Be $false
        $result.Errors | Should -Contain ($result.Errors | Where-Object { $_ -match "SAMISH.ps1 not found" })
    }

    It "returns error when Hidden XML template is missing" {
        Remove-Item (Join-Path $script:pkgDir "SAMISH-HiddenTask.xml") -Force
        $result = Test-InstallPreFlight -PackageDir $script:pkgDir -InstallDir $script:installDir -Mode "Hidden"
        $result.IsValid | Should -Be $false
        $result.Errors | Should -Contain ($result.Errors | Where-Object { $_ -match "SAMISH-HiddenTask.xml" })
    }

    It "returns error when Interactive XML template is missing" {
        Remove-Item (Join-Path $script:pkgDir "SAMISH-InteractiveTask.xml") -Force
        $result = Test-InstallPreFlight -PackageDir $script:pkgDir -InstallDir $script:installDir -Mode "Interactive"
        $result.IsValid | Should -Be $false
        $result.Errors | Should -Contain ($result.Errors | Where-Object { $_ -match "SAMISH-InteractiveTask.xml" })
    }

    It "returns warning when Modules directory is missing from package" {
        Remove-Item (Join-Path $script:pkgDir "Modules") -Force -Recurse
        $result = Test-InstallPreFlight -PackageDir $script:pkgDir -InstallDir $script:installDir -Mode "Hidden"
        # Should still be valid (warning, not error)
        $result.IsValid | Should -Be $true
        $result.Warnings | Should -Contain ($result.Warnings | Where-Object { $_ -match "Modules directory not found" })
    }

    It "accumulates multiple errors when multiple files are missing" {
        Remove-Item (Join-Path $script:pkgDir "SAMISH.ps1") -Force
        Remove-Item (Join-Path $script:pkgDir "SAMISH-HiddenTask.xml") -Force
        $result = Test-InstallPreFlight -PackageDir $script:pkgDir -InstallDir $script:installDir -Mode "Hidden"
        $result.IsValid | Should -Be $false
        $result.Errors.Count | Should -BeGreaterOrEqual 2
    }
}

Describe "Test-UninstallPreFlight" {
    It "passes when schtasks.exe is available" {
        $result = Test-UninstallPreFlight -InstallDir (Join-Path $env:APPDATA "SAMISH")
        # schtasks.exe should always be present on Windows
        $result.IsValid | Should -Be $true
    }
}

Describe "Format-PreFlightResult" {
    It "returns null when there are no errors or warnings" {
        $result = [pscustomobject]@{ IsValid = $true; Errors = @(); Warnings = @() }
        $formatted = Format-PreFlightResult -Result $result -Operation "Install"
        $formatted | Should -BeNullOrEmpty
    }

    It "formats errors into a readable string" {
        $result = [pscustomobject]@{
            IsValid  = $false
            Errors   = @("Missing file A", "Missing file B")
            Warnings = @()
        }
        $formatted = Format-PreFlightResult -Result $result -Operation "Install"
        $formatted | Should -Match "Install cannot proceed"
        $formatted | Should -Match "Missing file A"
        $formatted | Should -Match "Missing file B"
    }

    It "formats warnings into a readable string" {
        $result = [pscustomobject]@{
            IsValid  = $true
            Errors   = @()
            Warnings = @("Not running as admin")
        }
        $formatted = Format-PreFlightResult -Result $result -Operation "Uninstall"
        $formatted | Should -Match "Warnings"
        $formatted | Should -Match "Not running as admin"
    }
}
