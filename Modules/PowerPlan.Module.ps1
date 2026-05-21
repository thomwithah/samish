# ==========================================
# SAMISH Power Plan Module
# ==========================================

# ----- Load shared read utilities (Common) -----
try {
    $thisDir = Split-Path -Parent $PSCommandPath
    $commonPath = Join-Path $thisDir "PowerPlan.Read.Common.ps1"
    if (Test-Path -LiteralPath $commonPath) {
        . $commonPath
    }
} catch {
    # Best effort only
}

# Power plan GUIDs
$SUB_VIDEO      = "7516b95f-f776-4464-8c53-06167f40cc99"
$VIDEOIDLE      = "3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e"
$SUB_SLEEP      = "238c9fa8-0aad-41ed-83f4-97be242c8f20"
$STANDBYIDLE    = "29f6c1db-86da-48c5-9fdb-f2b67b1f44da"
$HIBERNATEIDLE  = "9d7815a6-7ee4-497e-8888-515a05f02364"
$MinGapSeconds  = 60

# Temporary baseline (ONLY used when both Sleep and Hibernate are disabled)
# This is intentionally isolated so it can be removed cleanly when the Power Plan Configuration UI is implemented.
$EnableTemporaryBaselineWhenNoSleep = $true
$TempBaseline_ScreenOffSeconds = 20 * 60      # 20 minutes
$TempBaseline_HibernateSeconds = 3 * 60 * 60  # 3 hours

if (-not (Get-Command Get-ActiveSchemeGuid -ErrorAction SilentlyContinue)) {
    function Get-ActiveSchemeGuid {
        $out = powercfg /getactivescheme 2>$null
        if ($out -match '([0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})') {
            return $matches[1].ToLower()
        }
        return $null
    }
}

if (-not (Get-Command Get-PowerSettingSecondsAC -ErrorAction SilentlyContinue)) {
    function Get-PowerSettingSecondsAC {
        param(
            [string]$SchemeGuid,
            [string]$SubGuid,
            [string]$SettingGuid
        )

        if ([string]::IsNullOrWhiteSpace($SchemeGuid)) { return $null }

        $out = powercfg /query $SchemeGuid $SubGuid $SettingGuid 2>$null
        $m = ($out |
            Select-String -Pattern 'Current AC Power Setting Index:\s+0x([0-9a-fA-F]+)' |
            Select-Object -First 1)

        if ($m -and $m.Matches.Count -gt 0) {
            try { return [Convert]::ToInt32($m.Matches[0].Groups[1].Value, 16) } catch { return $null }
        }
        return $null
    }
}

if (-not (Get-Command Set-PowerSettingSecondsAC -ErrorAction SilentlyContinue)) {
    function Set-PowerSettingSecondsAC {
        param(
            [string]$SchemeGuid,
            [string]$SubGuid,
            [string]$SettingGuid,
            [int]$Seconds
        )

        if ([string]::IsNullOrWhiteSpace($SchemeGuid)) { return }
        powercfg /setacvalueindex $SchemeGuid $SubGuid $SettingGuid $Seconds 2>$null | Out-Null
    }
}

function Format-SecondsToFriendly {
    param([int]$Seconds)

    if ($Seconds -eq 0) { return "Disabled" }

    $hours = [Math]::Floor($Seconds / 3600)
    $minutes = [Math]::Floor(($Seconds % 3600) / 60)
    $secs = $Seconds % 60

    $parts = @()

    if ($hours -gt 0) {
        if ($hours -eq 1) { $parts += "1 hour" } else { $parts += "$hours hours" }
    }

    if ($minutes -gt 0) {
        if ($minutes -eq 1) { $parts += "1 minute" } else { $parts += "$minutes minutes" }
    }

    # Hide 0 seconds unless it's the only unit shown
    if ($secs -gt 0 -or $parts.Count -eq 0) {
        if ($secs -eq 1) { $parts += "1 second" } else { $parts += "$secs seconds" }
    }

    return ($parts -join " ")
}

function Get-PowerPlanDiagnosticsText {
    param([string]$SchemeGuid)

    $display = Get-PowerSettingSecondsAC -SchemeGuid $SchemeGuid -SubGuid $SUB_VIDEO -SettingGuid $VIDEOIDLE
    $sleep   = Get-PowerSettingSecondsAC -SchemeGuid $SchemeGuid -SubGuid $SUB_SLEEP -SettingGuid $STANDBYIDLE
    $hib     = Get-PowerSettingSecondsAC -SchemeGuid $SchemeGuid -SubGuid $SUB_SLEEP -SettingGuid $HIBERNATEIDLE

    $displayText = Format-SecondsToFriendly $display
    $sleepText   = Format-SecondsToFriendly $sleep
    $hibText     = Format-SecondsToFriendly $hib

    return "Power Plan:`r`nScreen Off = $displayText`r`nSleep = $sleepText`r`nHibernate = $hibText"
}

function Get-EarliestTransitionSeconds {
    param([int]$SleepIdleSeconds,[int]$HibernateIdleSeconds)

    $candidates = @()
    if ($SleepIdleSeconds -gt 0) { $candidates += $SleepIdleSeconds }
    if ($HibernateIdleSeconds -gt 0) { $candidates += $HibernateIdleSeconds }

    if ($candidates.Count -eq 0) { return 0 }
    return ($candidates | Measure-Object -Minimum).Minimum
}

function Backup-PowerPlanValues {
    param([string]$SchemeGuid,[int]$DisplayOff,[int]$SleepIdle,[int]$HibernateIdle)

    # Requires Setup.ps1 to define Ensure-InstallFolder and $PowerPlanBackupPath
    Ensure-InstallFolder

    $obj = [ordered]@{
        SchemeGuid = $SchemeGuid
        DisplayOffSeconds = $DisplayOff
        SleepIdleSeconds = $SleepIdle
        HibernateIdleSeconds = $HibernateIdle
        Timestamp = (Get-Date).ToString("s")
    } | ConvertTo-Json -Depth 3

    Set-Content -LiteralPath $PowerPlanBackupPath -Value $obj -Encoding UTF8
}

function Test-PowerPlanCompatibility {
    param([int]$DisplayOffSeconds,[int]$SleepIdleSeconds,[int]$HibernateIdleSeconds,[int]$GapSeconds)

    $earliest = Get-EarliestTransitionSeconds -SleepIdleSeconds $SleepIdleSeconds -HibernateIdleSeconds $HibernateIdleSeconds
    if ($earliest -le 0) { return @{ Compatible = $true; Earliest = 0 } }

    $ok = ($DisplayOffSeconds -gt 0) -and ($DisplayOffSeconds -le ($earliest - $GapSeconds))
    return @{ Compatible = $ok; Earliest = $earliest }
}

function Restore-PowerPlanFromBackup {

    if (-not (Test-Path -LiteralPath $PowerPlanBackupPath)) {
        $null = [System.Windows.Forms.MessageBox]::Show(
    "No power plan backup was found.",
    "SAMISH Power Plan",
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
)

        return @{ StatusMessage = "No power plan backup was found." }
    }

    $raw = Get-Content -LiteralPath $PowerPlanBackupPath -Raw
    $b = $raw | ConvertFrom-Json
    if (-not $b.SchemeGuid) { throw "Backup file is missing SchemeGuid." }

    Set-PowerSettingSecondsAC -SchemeGuid $b.SchemeGuid -SubGuid $SUB_VIDEO -SettingGuid $VIDEOIDLE -Seconds ([int]$b.DisplayOffSeconds)
    Set-PowerSettingSecondsAC -SchemeGuid $b.SchemeGuid -SubGuid $SUB_SLEEP -SettingGuid $STANDBYIDLE -Seconds ([int]$b.SleepIdleSeconds)
    Set-PowerSettingSecondsAC -SchemeGuid $b.SchemeGuid -SubGuid $SUB_SLEEP -SettingGuid $HIBERNATEIDLE -Seconds ([int]$b.HibernateIdleSeconds)

    powercfg /setactive $b.SchemeGuid 2>$null | Out-Null
    Remove-Item -LiteralPath $PowerPlanBackupPath -Force -ErrorAction SilentlyContinue

    $msg = "Power plan restored.`r`nYour previous settings have been applied."
    Write-SetupLog "Power plan restored (backup removed)."

    return @{ StatusMessage = $msg }
}

function PowerPlan_ApplyTemporaryBaselineIfNoSleep {
    param(
        [string]$SchemeGuid,
        [int]$DisplayOffSeconds,
        [int]$SleepIdleSeconds,
        [int]$HibernateIdleSeconds,

        [Nullable[bool]]$UserAcceptedBaseline = $null
    )

    if (-not $EnableTemporaryBaselineWhenNoSleep) { return $null }

    # Only apply when BOTH sleep and hibernate are disabled
    if (-not (($SleepIdleSeconds -eq 0) -and ($HibernateIdleSeconds -eq 0))) { return $null }

    # ✅ Use unified backup detection
    $b = Get-PowerPlanBackupInfo

    if ($b.Exists -and $b.IsValid) {

        $prompt =
            "Sleep and hibernate are currently disabled.`r`n`r`n" +
            "A previous power plan backup already exists.`r`n`r`n" +
            "You can either restore your previous settings OR apply a temporary baseline again.`r`n`r`n" +
            "Apply the temporary baseline now?"

        if ($null -eq $UserAcceptedBaseline) {
            return @{
                NeedsPrompt   = $true
                PromptId      = "TempBaseline"
                PromptTitle   = "SAMISH Power Plan"
                PromptText    = $prompt
                PromptButtons = "YesNo"
                PromptIcon    = "Question"
            }
        }

        if ($UserAcceptedBaseline -ne $true) {
            return @{
                StatusMessage = "No changes were made.`r`n`r`nYour current power plan remains unchanged."
            }
        }

        # ✅ If YES, fall through and apply baseline below
    }

    # ✅ Standard baseline prompt (no backup or invalid backup)
    $prompt =
        "Sleep and hibernate are currently disabled.`r`n`r`n" +
        "SAMISH works best when at least one sleep state is enabled.`r`n`r`n" +
        "SAMISH can back up your existing power profile and apply a temporary baseline.`r`n`r`n" +
        "Temporary baseline settings:`r`n" +
        "- Screen Off: 20 minutes`r`n" +
        "- Hibernate: 3 hours`r`n`r`n" +
        "Would you like SAMISH to apply these settings now?"

    if ($null -eq $UserAcceptedBaseline) {
        return @{
            NeedsPrompt   = $true
            PromptId      = "TempBaseline"
            PromptTitle   = "SAMISH Power Plan"
            PromptText    = $prompt
            PromptButtons = "YesNo"
            PromptIcon    = "Question"
        }
    }

    if ($UserAcceptedBaseline -ne $true) {
        return @{
            StatusMessage =
                "Your current power plan does not use sleep or hibernate.`r`n`r`n" +
                "SAMISH is designed to assist when the system enters or exits sleep or hibernation.`r`n`r`n" +
                "If you want SAMISH to be effective, consider enabling sleep or hibernation in your power settings.`r`n`r`n" +
                "You can use ""Power Plan: Check / Restore"" to review your settings and apply recommended changes where applicable."
        }
    }

    # ✅ Apply baseline
    Backup-PowerPlanValues -SchemeGuid $SchemeGuid -DisplayOff $DisplayOffSeconds -SleepIdle $SleepIdleSeconds -HibernateIdle $HibernateIdleSeconds

    Set-PowerSettingSecondsAC -SchemeGuid $SchemeGuid -SubGuid $SUB_VIDEO -SettingGuid $VIDEOIDLE -Seconds $TempBaseline_ScreenOffSeconds
    Set-PowerSettingSecondsAC -SchemeGuid $SchemeGuid -SubGuid $SUB_SLEEP -SettingGuid $HIBERNATEIDLE -Seconds $TempBaseline_HibernateSeconds
    Set-PowerSettingSecondsAC -SchemeGuid $SchemeGuid -SubGuid $SUB_SLEEP -SettingGuid $STANDBYIDLE -Seconds 0

    powercfg /setactive $SchemeGuid 2>$null | Out-Null

    $msg =
        "Applied temporary baseline power plan settings (backup created):`r`n" +
        "Screen Off = 20 minutes`r`n" +
        "Hibernate = 3 hours`r`n`r`n" +
        "You can adjust these in Windows Power Options if you prefer.`r`n" +
        "After adjusting, run ""Power Plan: Check / Restore"" to verify compatibility and apply recommended changes where applicable."

    Write-SetupLog "Power plan baseline applied (ScreenOff=20m, Hibernate=3h), backup created."

    return @{ StatusMessage = $msg }
}
function Apply-PowerPlanFixWithBackup {
    param(
        [bool]$PromptUser,
        [bool]$AutoMode,
        [Nullable[bool]]$UserAcceptedBaseline = $null,
        [Nullable[bool]]$UserAcceptedCompatFix = $null
    )

    $scheme = Get-ActiveSchemeGuid
    if (-not $scheme) { return $null }

    $displayOff = Get-PowerSettingSecondsAC -SchemeGuid $scheme -SubGuid $SUB_VIDEO -SettingGuid $VIDEOIDLE
    $sleepIdle  = Get-PowerSettingSecondsAC -SchemeGuid $scheme -SubGuid $SUB_SLEEP -SettingGuid $STANDBYIDLE
    $hibIdle    = Get-PowerSettingSecondsAC -SchemeGuid $scheme -SubGuid $SUB_SLEEP -SettingGuid $HIBERNATEIDLE
    if ($null -eq $displayOff -or $null -eq $sleepIdle -or $null -eq $hibIdle) { return $null }

    # 1) Temporary baseline handling (only when both sleep and hibernate disabled)
    $baselineResult = PowerPlan_ApplyTemporaryBaselineIfNoSleep `
        -SchemeGuid $scheme `
        -DisplayOffSeconds $displayOff `
        -SleepIdleSeconds $sleepIdle `
        -HibernateIdleSeconds $hibIdle `
        -UserAcceptedBaseline $UserAcceptedBaseline

    if ($baselineResult) { return $baselineResult }

    # 2) Compatibility check
    $test = Test-PowerPlanCompatibility `
        -DisplayOffSeconds $displayOff `
        -SleepIdleSeconds $sleepIdle `
        -HibernateIdleSeconds $hibIdle `
        -GapSeconds $MinGapSeconds

    if ($test.Compatible) {
        return @{
            StatusMessage = "Power plan is already compatible with SAMISH."
        }
    }

    $earliest = [int]$test.Earliest

    # Normal screen-off-only target (clamped to at least 60 seconds)
    $desiredDisplayOff = [Math]::Max(60, $earliest - $MinGapSeconds)

    # 3) Edge-case detection:
    # If Screen Off is already at 1 minute (60s) and the earliest sleep/hibernate is also 1 minute (60s),
    # then screen-off-only fix is impossible (would require < 60s).
    $minEdge = ($displayOff -eq 60) -and ($earliest -eq 60) -and ($desiredDisplayOff -eq 60)

    if ($minEdge) {

        # Only propose changing timers that are currently 1 minute; leave Disabled (0) as Disabled.
        $proposeSleep = ($sleepIdle -eq 60)
        $proposeHib   = ($hibIdle   -eq 60)

        # If neither is 1 minute (unlikely given earliest==60), fall back to normal prompt
        if (-not $proposeSleep -and -not $proposeHib) {
            $minEdge = $false
        }
    }

    if ($minEdge) {

        $sleepCurrentText = Format-SecondsToFriendly $sleepIdle
        $hibCurrentText   = Format-SecondsToFriendly $hibIdle

        $proposedLines = @()
        $proposedLines += "- Screen Off: 1 minute (no change)"

        if ($sleepIdle -eq 60)     { $proposedLines += "- Sleep: 2 minutes" }
        if ($hibIdle   -eq 60)     { $proposedLines += "- Hibernate: 2 minutes" }

        $prompt =
            "Your current power plan may not be compatible with SAMISH.`r`n`r`n" +
            "SAMISH requires Screen Off to occur at least 1 minute before Sleep or Hibernate.`r`n`r`n" +
            "Current settings:`r`n" +
            "- Screen Off: " + (Format-SecondsToFriendly $displayOff) + "`r`n" +
            "- Sleep: " + $sleepCurrentText + "`r`n" +
            "- Hibernate: " + $hibCurrentText + "`r`n`r`n" +
            "Screen Off cannot be set lower than 1 minute.`r`n`r`n" +
            "Proposed adjustment:`r`n" +
            ($proposedLines -join "`r`n") + "`r`n`r`n" +
            "Note: Windows may automatically adjust Hibernate when you change Screen Off in Power Options.`r`n`r`n" +
            "Apply these changes now?"

        if ($null -eq $UserAcceptedCompatFix) {
            return @{
                NeedsPrompt   = $true
                PromptId      = "CompatFixMinEdge"
                PromptTitle   = "SAMISH Power Plan Fix"
                PromptText    = $prompt
                PromptButtons = "YesNo"
                PromptIcon    = "Warning"
            }
        }

        if ($UserAcceptedCompatFix -ne $true) {
            return @{
                StatusMessage =
                    "No compatibility changes were applied.`r`n`r`n" +
                    "Your current power plan may prevent SAMISH from functioning as intended.`r`n`r`n" +
                    "To fix this later, increase Sleep and/or Hibernate to 2 minutes, then run ""Power Plan: Check / Restore"" again."
            }
        }

        # Apply edge-case fix (backup first)
        Backup-PowerPlanValues -SchemeGuid $scheme -DisplayOff $displayOff -SleepIdle $sleepIdle -HibernateIdle $hibIdle

        # Screen Off remains at 60 (no change), but we do not re-set it unless it isn't already 60.
        if ($displayOff -ne 60) {
            Set-PowerSettingSecondsAC -SchemeGuid $scheme -SubGuid $SUB_VIDEO -SettingGuid $VIDEOIDLE -Seconds 60
        }

        if ($sleepIdle -eq 60) {
            Set-PowerSettingSecondsAC -SchemeGuid $scheme -SubGuid $SUB_SLEEP -SettingGuid $STANDBYIDLE -Seconds 120
        }

        if ($hibIdle -eq 60) {
            Set-PowerSettingSecondsAC -SchemeGuid $scheme -SubGuid $SUB_SLEEP -SettingGuid $HIBERNATEIDLE -Seconds 120
        }

        powercfg /setactive $scheme 2>$null | Out-Null

        $doneLines = @()
        $doneLines += "Power plan updated successfully."
        $doneLines += ""
        $doneLines += "Screen Off remains: 1 minute"
        if ($sleepIdle -eq 60) { $doneLines += "Sleep set to: 2 minutes" }
        if ($hibIdle   -eq 60) { $doneLines += "Hibernate set to: 2 minutes" }

        return @{ StatusMessage = ($doneLines -join "`r`n") }
    }

    # 4) Normal compatibility fix (Screen Off only)
    $prompt =
        "Your current power plan may not be compatible with SAMISH.`r`n`r`n" +
        "SAMISH requires Screen Off to occur at least 1 minute before Sleep or Hibernate.`r`n`r`n" +
        "Current settings:`r`n" +
        "- Screen Off: " + (Format-SecondsToFriendly $displayOff) + "`r`n" +
        "- Sleep: " + (Format-SecondsToFriendly $sleepIdle) + "`r`n" +
        "- Hibernate: " + (Format-SecondsToFriendly $hibIdle) + "`r`n`r`n" +
        "Proposed adjustment:`r`n" +
        "- Screen Off: " + (Format-SecondsToFriendly $desiredDisplayOff) + "`r`n`r`n" +
        "Apply this change now?"

    if ($null -eq $UserAcceptedCompatFix) {
        return @{
            NeedsPrompt   = $true
            PromptId      = "CompatFix"
            PromptTitle   = "SAMISH Power Plan Fix"
            PromptText    = $prompt
            PromptButtons = "YesNo"
            PromptIcon    = "Warning"
        }
    }

    if ($UserAcceptedCompatFix -ne $true) {
        return @{
            StatusMessage =
                "No compatibility changes were applied.`r`n`r`n" +
                "Your current power plan may prevent SAMISH from functioning as intended.`r`n`r`n" +
                "To fix this later, run ""Power Plan: Check / Restore"" and follow the recommended changes."
        }
    }

    # Apply fix (backup first)
    Backup-PowerPlanValues -SchemeGuid $scheme -DisplayOff $displayOff -SleepIdle $sleepIdle -HibernateIdle $hibIdle

    Set-PowerSettingSecondsAC -SchemeGuid $scheme -SubGuid $SUB_VIDEO -SettingGuid $VIDEOIDLE -Seconds $desiredDisplayOff
    powercfg /setactive $scheme 2>$null | Out-Null

    return @{
        StatusMessage =
            "Power plan updated successfully.`r`n`r`n" +
            "New Screen Off setting: " + (Format-SecondsToFriendly $desiredDisplayOff)
    }
}
function Get-PowerPlanBackupInfo {
    # Returns: @{ Exists = bool; IsValid = bool; SchemeGuid = string; Error = string }

    if (-not (Test-Path -LiteralPath $PowerPlanBackupPath)) {
        return @{ Exists = $false; IsValid = $false; SchemeGuid = ""; Error = "Missing" }
    }

    try {
        $raw = Get-Content -LiteralPath $PowerPlanBackupPath -Raw -ErrorAction Stop

        if ([string]::IsNullOrWhiteSpace($raw)) {
            return @{ Exists = $true; IsValid = $false; SchemeGuid = ""; Error = "Empty" }
        }

        $obj = $raw | ConvertFrom-Json -ErrorAction Stop

        if ($null -eq $obj -or [string]::IsNullOrWhiteSpace($obj.SchemeGuid)) {
            return @{ Exists = $true; IsValid = $false; SchemeGuid = ""; Error = "Missing SchemeGuid" }
        }

        return @{ Exists = $true; IsValid = $true; SchemeGuid = [string]$obj.SchemeGuid; Error = "" }
    }
    catch {
        return @{ Exists = $true; IsValid = $false; SchemeGuid = ""; Error = $_.Exception.Message }
    }
}
function PowerPlan_CheckOrRestore {

    $b = Get-PowerPlanBackupInfo

    if ($b.Exists -and -not $b.IsValid) {

        $msg =
            "A power plan backup file was found, but it appears to be invalid or corrupted.`r`n`r`n" +
            "SAMISH cannot restore this backup.`r`n`r`n" +
            "You may delete the backup file and create a new one by applying a power plan fix."

        Write-SetupLog ("Power plan backup parse error: " + $b.Error)

        return @{ StatusMessage = $msg }
    }

    if ($b.Exists -and $b.IsValid) {

        $prompt =
            "SAMISH found a previous power plan backup.`r`n`r`n" +
            "Restore your previous settings now?`r`n" +
            "(Backup will be removed.)`r`n`r`n" +
            "If you choose No, SAMISH will continue and check/fix compatibility as needed."

        return @{
            NeedsPrompt   = $true
            PromptId      = "RestoreBackup"
            PromptTitle   = "SAMISH Power Plan"
            PromptText    = $prompt
            PromptButtons = "YesNo"
            PromptIcon    = "Question"
        }
    }

    return Apply-PowerPlanFixWithBackup -PromptUser:$true -AutoMode:$false
}