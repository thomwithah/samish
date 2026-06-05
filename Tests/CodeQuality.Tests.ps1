<#
    CodeQuality.Tests.ps1
    Stage 1c: Cross-file code quality analysis for SAMISH.

    PSScriptAnalyzer cannot track cross-file variable usage in dot-sourced
    modules. This test suite provides:
      1. Verification that all named handler functions called from scriptblock
         wrappers actually exist in the codebase (catches the scope bug).
      2. PSScriptAnalyzer regression guard (baseline tracking).
      3. Zero parse-error verification across all production files.

    SAMISH convention: WinForms handlers use param($sender, $e) in named
    global: functions with [SuppressMessage] attributes.
#>

Describe 'Named Handler Function Resolution' {

    BeforeAll {
        $script:ModulesDir = Join-Path $PSScriptRoot '..\App\Modules'

        $script:ModuleFiles = Get-ChildItem -Path $script:ModulesDir -Filter '*.ps1' -File -Recurse |
            Where-Object { $_.FullName -notmatch '\\Tests\\' }

        # Find all "Handle-*" function calls inside scriptblock wrappers
        # Pattern: { Handle-SomeName @args }
        $script:HandlerCalls = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($f in $script:ModuleFiles) {
            $content = Get-Content -LiteralPath $f.FullName -Raw
            $callMatches = [regex]::Matches($content, '\{\s*(Handle-\w+)\s+@args\s*\}')
            foreach ($m in $callMatches) {
                $script:HandlerCalls.Add([PSCustomObject]@{
                    File         = $f.Name
                    FunctionName = $m.Groups[1].Value
                })
            }
        }

        # Find all function definitions matching Handle-*
        $script:HandlerDefinitions = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )

        foreach ($f in $script:ModuleFiles) {
            $content = Get-Content -LiteralPath $f.FullName -Raw
            $defMatches = [regex]::Matches($content, 'function\s+(?:global:)?(Handle-\w+)\s*\{')
            foreach ($m in $defMatches) {
                $null = $script:HandlerDefinitions.Add($m.Groups[1].Value)
            }
        }
    }

    It 'should find at least 15 named handler functions defined' {
        $script:HandlerDefinitions.Count | Should -BeGreaterOrEqual 15
    }

    It 'should find at least 15 handler call sites using { Handle-* @args }' {
        $script:HandlerCalls.Count | Should -BeGreaterOrEqual 15
    }

    It 'every { Handle-* @args } call should have a matching function definition' {
        $missing = [System.Collections.Generic.List[string]]::new()

        foreach ($call in $script:HandlerCalls) {
            if (-not $script:HandlerDefinitions.Contains($call.FunctionName)) {
                $missing.Add("$($call.File): $($call.FunctionName)")
            }
        }

        if ($missing.Count -gt 0) {
            $detail = $missing -join "`n"
            $missing.Count | Should -Be 0 -Because "these handler calls have no matching function definition:`n$detail"
        }
    }

    It 'Theme-Extension handlers must use global: scope qualifier' {
        $themeFile = $script:ModuleFiles | Where-Object { $_.Name -eq 'Theme-Extension.ps1' }
        $themeFile | Should -Not -BeNullOrEmpty

        $content = Get-Content -LiteralPath $themeFile.FullName -Raw

        # Find Handle-* function defs in Theme-Extension.ps1
        $defs = [regex]::Matches($content, 'function\s+((?:global:)?Handle-\w+)\s*\{')
        $defs.Count | Should -BeGreaterOrEqual 8

        $nonGlobal = [System.Collections.Generic.List[string]]::new()
        foreach ($d in $defs) {
            $fullName = $d.Groups[1].Value
            if ($fullName -notmatch '^global:') {
                $nonGlobal.Add($fullName)
            }
        }

        if ($nonGlobal.Count -gt 0) {
            $detail = $nonGlobal -join "`n"
            $nonGlobal.Count | Should -Be 0 -Because "Theme-Extension handlers must be global: (called from global: functions). Missing global: on:`n$detail"
        }
    }
}

Describe 'Cross-File Variable Connectivity' {

    BeforeAll {
        $script:ModulesDir = Join-Path $PSScriptRoot '..\App\Modules'
        $script:AppDir     = Join-Path $PSScriptRoot '..\App'

        $script:ProductionFiles = @(
            Get-ChildItem -Path $script:AppDir -Filter '*.ps1' -File
            Get-ChildItem -Path $script:ModulesDir -Filter '*.ps1' -File -Recurse
        ) | Where-Object { $_.FullName -notmatch '\\Tests\\' }

        # Build a codebase-wide index of all variable names that appear in the source.
        # We use simple regex for reliability: find all $varName and $scope:varName patterns.
        $script:AllVarReferences = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )

        foreach ($f in $script:ProductionFiles) {
            $content = Get-Content -LiteralPath $f.FullName -Raw
            # Match $varName, $script:varName, $global:varName etc
            # Exclude property access ($obj.Prop would match $obj)
            $varMatches = [regex]::Matches($content, '\$(?:(?:script|global|local|private|using|env):)?(\w+)')
            foreach ($m in $varMatches) {
                $null = $script:AllVarReferences.Add($m.Groups[1].Value)
            }
        }
    }

    It 'PSScriptAnalyzer PSUseDeclaredVarsMoreThanAssignments warnings should all be accounted for' {
        # Run PSScriptAnalyzer to get the current warnings
        $settingsPath = Join-Path $PSScriptRoot '..\.github\workflows\PSScriptAnalyzerSettings.psd1'
        if (-not (Test-Path $settingsPath)) {
            Set-ItResult -Skipped -Because 'PSScriptAnalyzer settings not found'
            return
        }

        $files = Get-ChildItem -Path (Join-Path $PSScriptRoot '..\App\Modules') -Filter '*.ps1' -Recurse
        $warnings = @()
        foreach ($f in $files) {
            $warnings += @(Invoke-ScriptAnalyzer -Path $f.FullName -Settings $settingsPath -Severity Warning, Error |
                Where-Object { $_.RuleName -eq 'PSUseDeclaredVarsMoreThanAssignments' })
        }

        # For each warning, check if the variable IS referenced somewhere in the codebase.
        # If it is, the warning is a false positive (cross-file usage).
        # If it is NOT, it's a genuine orphan we should track.
        $genuineOrphans = [System.Collections.Generic.List[string]]::new()
        $falsePositives = [System.Collections.Generic.List[string]]::new()

        # Known accepted orphans: variables we've audited and confirmed are intentionally unused
        $acceptedOrphans = @(
            'changed'       # ConfigBackup.Module.ps1:68 - flag set but function returns $Config directly
            'isFocused'     # Events.UI.Effects.ps1:21 - computed but only $isActive is used (defensive code)
            'targetStatus'  # Events.DiagnosticsTests.ps1:639 - documents intended SMTC status, checks use literal 4
            'cmdResult'     # Events.DiagnosticsTests.ps1:654 - captures return for future use, currently unchecked
        )

        foreach ($w in $warnings) {
            $varName = ''
            if ($w.Message -match "The variable '(\w+)'") {
                $varName = $Matches[1]
            }

            if ($varName -in $acceptedOrphans) {
                # Known and audited - skip
                continue
            }

            if ($script:AllVarReferences.Contains($varName)) {
                $falsePositives.Add("$($w.ScriptName):$($w.Line) - `$$varName (cross-file usage found)")
            }
            else {
                $genuineOrphans.Add("$($w.ScriptName):$($w.Line) - `$$varName (NOT found anywhere in codebase)")
            }
        }

        # Genuine orphans that are NOT in acceptedOrphans are bugs
        if ($genuineOrphans.Count -gt 0) {
            $detail = $genuineOrphans -join "`n"
            $genuineOrphans.Count | Should -Be 0 -Because "these variables are genuinely unused (not found in any file):`n$detail"
        }
    }
}

Describe 'Production File Parse Integrity' {

    BeforeAll {
        $script:ModulesDir = Join-Path $PSScriptRoot '..\App\Modules'
        $script:AppDir     = Join-Path $PSScriptRoot '..\App'

        $script:ProductionFiles = @(
            Get-ChildItem -Path $script:AppDir -Filter '*.ps1' -File
            Get-ChildItem -Path $script:ModulesDir -Filter '*.ps1' -File -Recurse
        ) | Where-Object { $_.FullName -notmatch '\\Tests\\' }
    }

    It 'should have no parse errors in any production file' {
        $parseErrors = [System.Collections.Generic.List[string]]::new()

        foreach ($f in $script:ProductionFiles) {
            $tokens = $null
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $f.FullName, [ref]$tokens, [ref]$errors
            )
            if ($errors -and $errors.Count -gt 0) {
                foreach ($err in $errors) {
                    $parseErrors.Add("$($f.Name):$($err.Extent.StartLineNumber) - $($err.Message)")
                }
            }
        }

        if ($parseErrors.Count -gt 0) {
            $detail = $parseErrors -join "`n"
            $parseErrors.Count | Should -Be 0 -Because "these files have parse errors:`n$detail"
        }
    }
}

Describe 'PSScriptAnalyzer Warning Regression Guard' {

    BeforeAll {
        $settingsPath = Join-Path $PSScriptRoot '..\.github\workflows\PSScriptAnalyzerSettings.psd1'
        $script:HasSettings = Test-Path -LiteralPath $settingsPath

        if ($script:HasSettings) {
            $modulesDir = Join-Path $PSScriptRoot '..\App\Modules'
            $files = Get-ChildItem -Path $modulesDir -Filter '*.ps1' -Recurse

            $script:LintResults = @()
            foreach ($f in $files) {
                $script:LintResults += @(Invoke-ScriptAnalyzer -Path $f.FullName -Settings $settingsPath -Severity Warning, Error)
            }
        }
    }

    It 'should have PSScriptAnalyzer settings file' {
        $script:HasSettings | Should -BeTrue
    }

    It 'should have zero $sender assignment warnings (PSAvoidAssignmentToAutomaticVariable)' {
        if (-not $script:HasSettings) {
            Set-ItResult -Skipped -Because 'PSScriptAnalyzer settings file not found'
            return
        }
        $senderWarnings = @($script:LintResults | Where-Object {
            $_.RuleName -eq 'PSAvoidAssignmentToAutomaticVariable' -and
            $_.Message -match 'sender'
        })

        if ($senderWarnings.Count -gt 0) {
            $detail = ($senderWarnings | ForEach-Object { "$($_.ScriptName):$($_.Line)" }) -join "`n"
            $senderWarnings.Count | Should -Be 0 -Because "sender warnings remain at:`n$detail"
        }
    }

    It 'total PSScriptAnalyzer warnings should not exceed baseline of 21' {
        if (-not $script:HasSettings) {
            Set-ItResult -Skipped -Because 'PSScriptAnalyzer settings file not found'
            return
        }
        $count = $script:LintResults.Count
        $count | Should -BeLessOrEqual 21 -Because "current baseline is 21 warnings; if this increased, a regression was introduced"
    }
}
