# ==========================================
# SAMISH Power Plan Read Utilities (Common)
# Shared parsing helpers for powercfg output.
# PS 5.1 compatible.
# ==========================================

function Get-ActiveSchemeGuid {
    $out = powercfg /getactivescheme 2>$null
    if ($out -match '([0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})') {
        return $matches[1].ToLower()
    }
    return $null
}

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
        try {
            return [Convert]::ToInt32($m.Matches[0].Groups[1].Value, 16)
        } catch {
            return $null
        }
    }

    return $null
}

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