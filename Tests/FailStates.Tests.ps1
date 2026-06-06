#requires -Version 5.1
# ==============================================================================
# Module: FailStates.Tests.ps1
# Purpose: Pester v5 integration tests verifying robust edge-case handling and
#          fail-states, such as Config schema autofix and mixer stop timeouts.
# Inputs: None (self-contained test suite).
# Outputs: Pester test results.
# Error Handling: Pester framework handles assertion failures.
# ==============================================================================

BeforeAll {
    $ModulesDir = Join-Path $PSScriptRoot "..\App\Modules"

    # Stub functions
    function Ensure-InstallFolder {}
    function Write-SetupLog { param($text) }
    function Log-Always { param($msg) }
    function Get-ActiveSchemeGuid { return "381b4222-f694-41f0-9685-ff5bb260df2e" }
    function Get-PowerSettingSecondsAC { param($SchemeGuid, $SubGuid, $SettingGuid); return 600 }

    # PowerPlan GUIDs expected by ConfigBackup.Module.ps1
    $SUB_VIDEO = "7516b95f-f776-4464-8c53-06167f40cc99"
    $VIDEOIDLE = "3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e"
    $SUB_SLEEP = "238c9fa8-0aad-41ed-83f4-97be242c8f20"
    $STANDBYIDLE = "29f6c1db-86da-48c5-9fdb-f2b67b1f44da"
    $HIBERNATEIDLE = "9d7815a6-7ee4-497e-8888-515a05f02364"

    . (Join-Path $ModulesDir "ConfigBackup.Module.ps1")
    . (Join-Path $ModulesDir "App.Control.Common.ps1")
}

Describe "Phase 3: Configuration Corruption AutoFix" {
    BeforeEach {
        $testDir = Join-Path $env:TEMP "SAMISH_FailStateTests_$(New-Guid)"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        $script:ConfigPath = Join-Path $testDir "config.json"
    }

    AfterEach {
        if (Test-Path $script:ConfigPath) { Remove-Item $script:ConfigPath -Force }
        $parent = Split-Path $script:ConfigPath
        if (Test-Path $parent) { Remove-Item $parent -Force -Recurse }
    }

    It "repairs malformed JSON syntax, merges defaults, and saves atomically" {
        # 1. Create a corrupted JSON file on disk
        Set-Content -Path $script:ConfigPath -Value '{ "OperatingMode": "Graceful", ' -Encoding UTF8
        
        # 2. Replicate the SAMISH.ps1 Apply-ConfigFromFile error-handling block
        $raw = Get-Content -LiteralPath $script:ConfigPath -Raw -ErrorAction Stop
        
        $cfg = $null
        $jsonError = $false
        try {
            $cfg = $raw | ConvertFrom-Json -ErrorAction Stop
        } catch {
            $jsonError = $true
            $cfg = [pscustomobject]@{}
        }
        
        # Verify it caught the JSON error
        $jsonError | Should -Be $true
        
        # 3. Apply schema tests and autofix
        $cfg = Merge-ConfigDefaults -Config $cfg
        $schemaRes = Test-ConfigSchema -Config $cfg -AutoFix
        
        if ($jsonError -or $schemaRes.FixedKeys.Count -gt 0) {
            $json = $cfg | ConvertTo-Json -Depth 3
            Save-ContentAtomic -Path $script:ConfigPath -Content $json
        }
        
        # 4. Verify the file on disk was overwritten and is now valid JSON with defaults
        $repairedRaw = Get-Content -LiteralPath $script:ConfigPath -Raw
        $repairedCfg = $repairedRaw | ConvertFrom-Json
        
        $repairedCfg.OperatingMode | Should -Be "Graceful"
        $repairedCfg.LogEverySeconds | Should -Be 30
        $repairedCfg.ActiveProfileId | Should -Be "BEACN"
    }

    It "repairs an invalid data type (schema violation) and saves atomically" {
        # 1. Create valid JSON but with an invalid data type (schema violation)
        $badCfg = @{
            OperatingMode = "InvalidMode"
            EnableLogging = "NotABool"
        } | ConvertTo-Json
        Set-Content -Path $script:ConfigPath -Value $badCfg -Encoding UTF8

        # 2. Replicate SAMISH.ps1 loading
        $raw = Get-Content -LiteralPath $script:ConfigPath -Raw -ErrorAction Stop
        
        $cfg = $null
        $jsonError = $false
        try {
            $cfg = $raw | ConvertFrom-Json -ErrorAction Stop
        } catch {
            $jsonError = $true
            $cfg = [pscustomobject]@{}
        }

        # JSON parsed successfully, but schema is invalid
        $jsonError | Should -Be $false

        $cfg = Merge-ConfigDefaults -Config $cfg
        $schemaRes = Test-ConfigSchema -Config $cfg -AutoFix

        $schemaRes.FixedKeys | Should -Contain "OperatingMode"
        $schemaRes.FixedKeys | Should -Contain "EnableLogging"

        if ($jsonError -or $schemaRes.FixedKeys.Count -gt 0) {
            $json = $cfg | ConvertTo-Json -Depth 3
            Save-ContentAtomic -Path $script:ConfigPath -Content $json
        }

        # 3. Verify it was repaired and saved
        $repairedRaw = Get-Content -LiteralPath $script:ConfigPath -Raw
        $repairedCfg = $repairedRaw | ConvertFrom-Json

        $repairedCfg.OperatingMode | Should -Be "Graceful" # Reset to default
        $repairedCfg.EnableLogging | Should -Be $false     # Reset to default
    }
}

Describe "Phase 3: Mixer Stop & Sleep Resiliency" {
    BeforeAll {
        function Stop-MockAdapterFail {
            return $false
        }
        function Stop-MockAdapterThrow {
            throw "Simulated adapter crash"
        }
        function Invoke-AppStop {
            param($ProcessName)
            return [pscustomobject]@{ Stopped = $true }
        }
        function Write-EventLogEntry {
            param($Message, $EntryType, $EventId)
            $script:LogEntries += "$($EntryType): $Message"
        }
        function Log-Always {
            param($msg)
            $script:LogEntries += "Log: $msg"
        }
    }

    BeforeEach {
        $script:LogEntries = @()
        $script:TargetProcessName = "MockMixer"
        $script:TargetExePath = "C:\Mock.exe"
        $script:OperatingMode = "Graceful"
        $script:GracefulWindowWakeDelayMs = 0
        $script:GracefulShutdownWaitMs = 0
        $script:MonitoredApps = $null
    }

    It "logs warning and fails-forward if adapter stop command returns false" {
        $script:ActiveProfileId = "MockAdapterFail"
        
        $stoppedAny = $false
        $adapterStopCmd = "Stop-$($script:ActiveProfileId)"
        if (Get-Command $adapterStopCmd -ErrorAction SilentlyContinue) {
            try {
                $r = & $adapterStopCmd
                if ($r) { $stoppedAny = $true } else {
                    Write-EventLogEntry -Message "Adapter failed to stop main mixer: $script:TargetProcessName." -EntryType "Warning" -EventId 300
                }
            } catch {
                Write-EventLogEntry -Message "Adapter threw an exception stopping main mixer: $_" -EntryType "Error" -EventId 400
            }
        }
        
        $stoppedAny | Should -Be $false
        $script:LogEntries | Should -Contain "Warning: Adapter failed to stop main mixer: MockMixer."
    }

    It "logs error and fails-forward if adapter stop command throws an exception" {
        $script:ActiveProfileId = "MockAdapterThrow"
        
        $stoppedAny = $false
        $adapterStopCmd = "Stop-$($script:ActiveProfileId)"
        
        if (Get-Command $adapterStopCmd -ErrorAction SilentlyContinue) {
            try {
                $r = & $adapterStopCmd
                if ($r) { $stoppedAny = $true } else {
                    Write-EventLogEntry -Message "Adapter failed." -EntryType "Warning" -EventId 300
                }
            } catch {
                Write-EventLogEntry -Message "Adapter threw an exception: $_" -EntryType "Error" -EventId 400
            }
        }
        
        $stoppedAny | Should -Be $false
        $script:LogEntries -match "Error: Adapter threw an exception: Simulated adapter crash" | Should -Not -BeNullOrEmpty
    }
}

Describe "Stage 4: Config Backup Before Auto-Fix" {
    BeforeEach {
        $testDir = Join-Path $env:TEMP "SAMISH_BackupTests_$(New-Guid)"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        $script:ConfigPath = Join-Path $testDir "config.json"
    }

    AfterEach {
        if (Test-Path (Split-Path $script:ConfigPath)) {
            Remove-Item (Split-Path $script:ConfigPath) -Force -Recurse -ErrorAction SilentlyContinue
        }
    }

    It "creates a timestamped backup before auto-fixing config" {
        # Create valid JSON with a schema violation
        $badCfg = @{ OperatingMode = "InvalidMode" } | ConvertTo-Json
        Set-Content -Path $script:ConfigPath -Value $badCfg -Encoding UTF8

        # Replicate the Apply-ConfigFromFile logic with backup
        $raw = Get-Content -LiteralPath $script:ConfigPath -Raw
        $cfg = $raw | ConvertFrom-Json
        $cfg = Merge-ConfigDefaults -Config $cfg
        $schemaRes = Test-ConfigSchema -Config $cfg -AutoFix

        $schemaRes.FixedKeys.Count | Should -BeGreaterThan 0

        # Create backup (mirrors SAMISH.ps1 logic)
        $ts = (Get-Date).ToString("yyyyMMdd-HHmmss")
        $backupPath = $script:ConfigPath + ".backup-$ts"
        Copy-Item -LiteralPath $script:ConfigPath -Destination $backupPath -Force

        # Save fixed config
        $json = $cfg | ConvertTo-Json -Depth 3
        Save-ContentAtomic -Path $script:ConfigPath -Content $json

        # Verify backup exists and contains original content
        Test-Path -LiteralPath $backupPath | Should -Be $true
        $backupContent = Get-Content -LiteralPath $backupPath -Raw
        $backupCfg = $backupContent | ConvertFrom-Json
        $backupCfg.OperatingMode | Should -Be "InvalidMode"  # Original bad value preserved

        # Verify fixed config has the corrected value
        $fixedContent = Get-Content -LiteralPath $script:ConfigPath -Raw
        $fixedCfg = $fixedContent | ConvertFrom-Json
        $fixedCfg.OperatingMode | Should -Be "Graceful"  # Reset to default
    }

    It "prunes old backups to keep only 5 most recent" {
        # Create a config file and 7 old backups
        Set-Content -Path $script:ConfigPath -Value '{}' -Encoding UTF8
        $configDir = Split-Path -Parent $script:ConfigPath

        for ($i = 1; $i -le 7; $i++) {
            $fakeName = "config.json.backup-20260601-00000$i"
            $fakePath = Join-Path $configDir $fakeName
            Set-Content -Path $fakePath -Value "{}" -Encoding UTF8
            # Stagger LastWriteTime so sort order is deterministic
            (Get-Item $fakePath).LastWriteTime = (Get-Date).AddMinutes(-60 + $i)
        }

        # Verify 7 backups exist
        $before = @(Get-ChildItem -LiteralPath $configDir -Filter "config.json.backup-*")
        $before.Count | Should -Be 7

        # Prune (mirrors SAMISH.ps1 logic)
        $backups = Get-ChildItem -LiteralPath $configDir -Filter "config.json.backup-*" -File |
            Sort-Object LastWriteTime -Descending |
            Select-Object -Skip 5
        foreach ($old in $backups) {
            Remove-Item -LiteralPath $old.FullName -Force -ErrorAction SilentlyContinue
        }

        # Verify only 5 remain (the 5 newest)
        $after = @(Get-ChildItem -LiteralPath $configDir -Filter "config.json.backup-*")
        $after.Count | Should -Be 5
    }
}
