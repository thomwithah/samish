#requires -Version 5.1
# ==============================================================================
# Module: Diagnostics.Tests.ps1
# Purpose: Pester v5 unit tests for the diagnostics module
#          (Diagnostics.Module.ps1). Validates blocker parsing, override
#          parsing, and telemetry data collection with mocked powercfg output.
# Inputs: None (self-contained test suite).
# Outputs: Pester test results.
# Error Handling: Pester framework handles assertion failures.
# ==============================================================================

BeforeAll {
    $ModulesDir = Join-Path $PSScriptRoot "..\App\Modules"

    # Stub functions expected by Diagnostics.Module.ps1
    function Write-SetupLog { param($text) }
    function Get-ActiveSchemeGuid { return "381b4222-f694-41f0-9685-ff5bb260df2e" }

    . (Join-Path $ModulesDir "Diagnostics.Module.ps1")
}

Describe "Get-ActiveSleepBlockers" {

    It "returns empty array when powercfg /requests shows no blockers and no apps running" {
        Mock powercfg {
            return @(
                "DISPLAY:",
                "None.",
                "",
                "SYSTEM:",
                "None.",
                "",
                "AWAYMODE:",
                "None.",
                "",
                "EXECUTION:",
                "None.",
                "",
                "PERFBOOST:",
                "None."
            )
        }
        Mock Get-Process { return $null }
        Mock Get-SmtcSessionManager { return $null }

        $result = Get-ActiveSleepBlockers
        $result | Should -HaveCount 0
    }

    It "parses a PROCESS blocker correctly" {
        Mock powercfg {
            return @(
                "DISPLAY:",
                "None.",
                "",
                "SYSTEM:",
                "[PROCESS] \Device\HarddiskVolume3\Program Files\Chrome\chrome.exe",
                "",
                "AWAYMODE:",
                "None.",
                "",
                "EXECUTION:",
                "None.",
                "",
                "PERFBOOST:",
                "None."
            )
        }

        $result = Get-ActiveSleepBlockers
        $result | Should -Not -BeNullOrEmpty
        $result[0].BlockerType | Should -Be "App"
        $result[0].ProcessName | Should -Be "chrome"
    }
}

Describe "Get-SystemOverrides" {

    It "returns empty array when powercfg /requestsoverride has no entries" {
        Mock powercfg {
            return @(
                "[PROCESS]",
                "",
                "[SERVICE]",
                "",
                "[DRIVER]",
                ""
            )
        }

        $result = Get-SystemOverrides
        $result | Should -HaveCount 0
    }
}

Describe "Source File Quality" {

    It "Diagnostics.Module.ps1 should not contain non-ASCII characters" {
        $path = Join-Path $PSScriptRoot "..\App\Modules\Diagnostics.Module.ps1"
        $content = Get-Content -LiteralPath $path -Raw
        $nonAscii = [regex]::Matches($content, '[^\x09\x0A\x0D\x20-\x7E]')

        if ($nonAscii.Count -gt 0) {
            $examples = @()
            foreach ($match in ($nonAscii | Select-Object -First 5)) {
                $charCode = [int][char]$match.Value
                $beforeMatch = $content.Substring(0, $match.Index)
                $lineNum = ($beforeMatch -split "`n").Count
                $examples += "Line $lineNum`: char U+$($charCode.ToString('X4')) ('$($match.Value)')"
            }
            $details = $examples -join "; "
            $nonAscii.Count | Should -Be 0 -Because "source code must use ASCII only. Found: $details"
        }
    }

    It "Events.Diagnostics.ps1 should not contain non-ASCII characters" {
        $path = Join-Path $PSScriptRoot "..\App\Modules\Events.Diagnostics.ps1"
        $content = Get-Content -LiteralPath $path -Raw
        $nonAscii = [regex]::Matches($content, '[^\x09\x0A\x0D\x20-\x7E]')

        if ($nonAscii.Count -gt 0) {
            $examples = @()
            foreach ($match in ($nonAscii | Select-Object -First 5)) {
                $charCode = [int][char]$match.Value
                $beforeMatch = $content.Substring(0, $match.Index)
                $lineNum = ($beforeMatch -split "`n").Count
                $examples += "Line $lineNum`: char U+$($charCode.ToString('X4')) ('$($match.Value)')"
            }
            $details = $examples -join "; "
            $nonAscii.Count | Should -Be 0 -Because "source code must use ASCII only. Found: $details"
        }
    }
}
