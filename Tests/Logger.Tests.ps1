#requires -Version 5.1
# ==============================================================================
# Module: Logger.Tests.ps1
# Purpose: Pester v5 unit tests for Logger.psm1 (Rotate-LogFileIfNeeded,
#          Resolve-SamishLogPath, Write-EventLogEntry).
# Inputs: None (self-contained test suite).
# Outputs: Pester test results.
# Error Handling: Pester framework handles assertion failures.
# ==============================================================================

BeforeAll {
    $ModulesDir = Join-Path $PSScriptRoot "..\App\Modules"
    Import-Module (Join-Path $ModulesDir "Logger.psm1") -Force
}

Describe "Resolve-SamishLogPath" {

    It "replaces {DATE} with today's date" {
        $template = "C:\Logs\samish_{DATE}.log"
        $expected = "C:\Logs\samish_$(Get-Date -Format 'yyyyMMdd').log"
        $result = Resolve-SamishLogPath -TemplatePath $template
        $result | Should -Be $expected
    }

    It "returns null for null or empty input" {
        Resolve-SamishLogPath -TemplatePath "" | Should -BeNullOrEmpty
        Resolve-SamishLogPath -TemplatePath $null | Should -BeNullOrEmpty
    }

    It "returns the path unchanged when no {DATE} placeholder exists" {
        $path = "C:\Logs\samish_static.log"
        $result = Resolve-SamishLogPath -TemplatePath $path
        $result | Should -Be $path
    }
}

Describe "Rotate-LogFileIfNeeded" {

    It "does nothing when the file does not exist" {
        Rotate-LogFileIfNeeded -Path "C:\NonExistent\fake.log"
        # Should not throw
    }

    It "does nothing when the file is under 5 MB" {
        $tempFile = Join-Path $TestDrive "small.log"
        Set-Content -LiteralPath $tempFile -Value "small content"
        Rotate-LogFileIfNeeded -Path $tempFile
        Test-Path -LiteralPath $tempFile | Should -Be $true
    }
}

Describe "Write-EventLogEntry" {

    It "does not throw when the SAMISH event source is not registered" {
        # On most dev machines, the SAMISH source won't be registered.
        # This should fail silently.
        { Write-EventLogEntry -Message "Test message" } | Should -Not -Throw
    }
}

Describe "Logger.psm1 Source File Quality" {

    It "should not contain non-ASCII characters" {
        $path = Join-Path $PSScriptRoot "..\App\Modules\Logger.psm1"
        $content = Get-Content -LiteralPath $path -Raw
        $nonAscii = [regex]::Matches($content, '[^\x09\x0A\x0D\x20-\x7E]')

        if ($nonAscii.Count -gt 0) {
            $examples = @()
            foreach ($match in ($nonAscii | Select-Object -First 5)) {
                $charCode = [int][char]$match.Value
                $beforeMatch = $content.Substring(0, $match.Index)
                $lineNum = ($beforeMatch -split "`n").Count
                $examples += "Line $lineNum`: char U+$($charCode.ToString('X4'))"
            }
            $details = $examples -join "; "
            $nonAscii.Count | Should -Be 0 -Because "source code must use ASCII only. Found: $details"
        }
    }
}
