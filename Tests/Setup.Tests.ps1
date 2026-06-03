#requires -Version 5.1
# ==============================================================================
# Module: Setup.Tests.ps1
# Purpose: Pester v5 AST-based static analysis tests for Setup.ps1.
#          Validates boot-order integrity: execution policy must be set before
#          any module dot-sourcing, and critical helper functions must be
#          available before they are called.
# Inputs: None (reads Setup.ps1 AST directly).
# Outputs: Pester test results.
# Error Handling: Pester framework handles assertion failures.
# ==============================================================================

BeforeAll {
    $script:SetupPath = Join-Path $PSScriptRoot "..\Setup.ps1"
    $script:SetupAst = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:SetupPath, [ref]$null, [ref]$null
    )
}

Describe "Setup.ps1 Boot Order Integrity" {

    It "should parse Setup.ps1 without syntax errors" {
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:SetupPath, [ref]$null, [ref]$parseErrors
        )
        $parseErrors.Count | Should -Be 0
    }

    It "should call Set-ExecutionPolicy before any dot-source (. path) command" {
        # Find the first Set-ExecutionPolicy call
        $allCommands = $script:SetupAst.FindAll(
            { param($ast)
                $ast -is [System.Management.Automation.Language.CommandAst]
            }, $true
        )

        $execPolicyCmd = $allCommands | Where-Object {
            $_.CommandElements[0].Value -eq "Set-ExecutionPolicy"
        } | Select-Object -First 1

        # Find all dot-source expressions (. $path or . "path")
        $dotSources = $script:SetupAst.FindAll(
            { param($ast)
                $ast -is [System.Management.Automation.Language.CommandAst] -and
                $ast.InvocationOperator -eq 'Dot'
            }, $true
        )

        $execPolicyCmd | Should -Not -BeNullOrEmpty -Because "Set-ExecutionPolicy must exist in Setup.ps1"
        $dotSources.Count | Should -BeGreaterThan 0 -Because "Setup.ps1 should dot-source modules"

        $firstDotSource = $dotSources | Sort-Object { $_.Extent.StartOffset } | Select-Object -First 1

        $execPolicyCmd.Extent.StartOffset | Should -BeLessThan $firstDotSource.Extent.StartOffset `
            -Because "Set-ExecutionPolicy must run before any module dot-sourcing to prevent load failures"
    }

    It "should not contain non-ASCII characters in source code" {
        $content = Get-Content -LiteralPath $script:SetupPath -Raw
        # Match any character outside printable ASCII (0x20-0x7E), tab (0x09), CR (0x0D), LF (0x0A)
        $nonAscii = [regex]::Matches($content, '[^\x09\x0A\x0D\x20-\x7E]')

        if ($nonAscii.Count -gt 0) {
            $examples = @()
            foreach ($match in ($nonAscii | Select-Object -First 5)) {
                $charCode = [int][char]$match.Value
                # Find the line number
                $beforeMatch = $content.Substring(0, $match.Index)
                $lineNum = ($beforeMatch -split "`n").Count
                $examples += "Line $lineNum`: char U+$($charCode.ToString('X4')) ('$($match.Value)')"
            }
            $details = $examples -join "; "
            $nonAscii.Count | Should -Be 0 -Because "source code must use ASCII only. Found: $details"
        }
    }
}

Describe "Setup.ps1 Function Definitions" {

    It "should define Complete-SamishSetupUi function" {
        $funcDefs = $script:SetupAst.FindAll(
            { param($ast)
                $ast -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $ast.Name -eq "Complete-SamishSetupUi"
            }, $true
        )
        $funcDefs.Count | Should -BeGreaterOrEqual 1
    }

    It "should define Ensure-SingleInstance function" {
        $funcDefs = $script:SetupAst.FindAll(
            { param($ast)
                $ast -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $ast.Name -eq "Ensure-SingleInstance"
            }, $true
        )
        $funcDefs.Count | Should -BeGreaterOrEqual 1
    }

    It "should define Write-SamishSetupTrace function before it is called" {
        # Validates that Write-SamishSetupTrace is defined before its first call.
        # Previously this was a known issue (called at line 76, defined at line 315)
        # but has been fixed by moving the definition to the top of the file.
        $funcDef = $script:SetupAst.FindAll(
            { param($ast)
                $ast -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $ast.Name -eq "Write-SamishSetupTrace"
            }, $true
        ) | Sort-Object { $_.Extent.StartOffset } | Select-Object -First 1

        $firstCall = $script:SetupAst.FindAll(
            { param($ast)
                $ast -is [System.Management.Automation.Language.CommandAst] -and
                $ast.CommandElements.Count -gt 0 -and
                $ast.CommandElements[0].Value -eq "Write-SamishSetupTrace"
            }, $true
        ) | Sort-Object { $_.Extent.StartOffset } | Select-Object -First 1

        if ($firstCall) {
            $funcDef | Should -Not -BeNullOrEmpty -Because "Write-SamishSetupTrace must be defined before first call"
            $funcDef.Extent.StartOffset | Should -BeLessThan $firstCall.Extent.StartOffset `
                -Because "Write-SamishSetupTrace definition must appear before its first invocation"
        }
    }
}
