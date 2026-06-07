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

    # Primary: Language-independent registry lookup
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$SchemeGuid\$SubGuid\$SettingGuid"
        $regItem = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        if ($null -ne $regItem -and $null -ne $regItem.ACSettingIndex) {
            return [int]$regItem.ACSettingIndex
        }
    } catch {
        # Registry read failed -- fall through to powercfg parsing
    }

    # Fallback: Parse powercfg output with localized-safe regex
    $out = powercfg /query $SchemeGuid $SubGuid $SettingGuid 2>$null

    # Try the English pattern first (fastest path on English systems)
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

    # Localized fallback: match the last 0x hex value on the AC settings line
    # Works for German (Wechselstrom), French (secteur/CA), and other locales
    $m2 = ($out |
        Select-String -Pattern '0x([0-9a-fA-F]+)\s*$' |
        Select-Object -First 1)

    if ($m2 -and $m2.Matches.Count -gt 0) {
        try {
            return [Convert]::ToInt32($m2.Matches[0].Groups[1].Value, 16)
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