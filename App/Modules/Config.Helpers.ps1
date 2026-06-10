#requires -Version 5.1
# ==============================================================================
# Module: Config.Helpers.ps1
# Purpose: Configuration read/write (Write-ConfigJson), log file selection
#          (Resolve-LogTemplatePath, Get-NewestLogMatchingTemplate,
#          Get-PreferredSamishLogPath), runtime file sync (Sync-SamishRuntimeFiles),
#          and device profile management (Get-AvailableProfiles, etc.).
#          Extracted from Setup.ps1 to reduce its size.
# Inputs: Consumed by Events.Setup.ps1, Logic.ps1 via dot-sourcing from Setup.ps1.
# Outputs: Config file writes, profile lists, file sync operations.
# Error Handling: try/catch with fail-forward for all file I/O.
# ==============================================================================

# ----- Config write helpers -----
function Write-ConfigJson {
    param(
        [bool]$EnableLogging,
        [int]$LogEverySeconds,
        [bool]$EnableTrayIcon,
        [bool]$EnableHotkey,
        [string]$HotkeyMode,
        [int]$CustomHotkeyVirtualKey,
        [string]$OperatingMode,
        [string]$SetupPath,

        [string]$ActiveProfileId = "BEACN",
        [string[]]$ProfilesEnabled = @("BEACN"),
        [bool]$EnableAutoRecovery = $true
    )

    Ensure-InstallFolder

    if ([string]::IsNullOrWhiteSpace($ActiveProfileId)) { $ActiveProfileId = "BEACN" }
    if (-not $ProfilesEnabled -or $ProfilesEnabled.Count -eq 0) { $ProfilesEnabled = @($ActiveProfileId) }

    # Preserve MonitoredApps if present in session or on disk
    $monitoredApps = @()
    $existing = $null
    if (Test-Path -LiteralPath $ConfigPath) {
        try {
            $existing = (Get-Content -LiteralPath $ConfigPath -Raw) | ConvertFrom-Json
        }
        catch {}
    }

    if ($script:MonitoredApps) {
        $monitoredApps = $script:MonitoredApps
    }
    elseif ($existing -and $existing.PSObject.Properties.Name -contains "MonitoredApps" -and $existing.MonitoredApps) {
        $monitoredApps = $existing.MonitoredApps
    }

    # Migrate old config flags in MonitoredApps to OnWakeAction
    if ($monitoredApps) {
        $monitoredApps = @(foreach ($app in $monitoredApps) {
                if ($null -eq $app.PSObject.Properties['OnWakeAction']) {
                    $onWake = "Smart"
                    if ($app.PSObject.Properties['NoRestartOnWake'] -and $app.NoRestartOnWake) {
                        $onWake = "KeepClosed"
                    }
                    elseif ($app.PSObject.Properties['ForcePlayOnWake'] -and $app.ForcePlayOnWake) {
                        $onWake = "Play"
                    }
                    $app | Add-Member -MemberType NoteProperty -Name "OnWakeAction" -Value $onWake -Force
                }
                $app
            })
    }

    $themeVal = "Normal"
    if ($null -ne $global:ThemeActiveType) {
        $themeVal = $global:ThemeActiveType
    }
    elseif ($existing -and $existing.PSObject.Properties.Name -contains "Theme" -and $existing.Theme) {
        $themeVal = $existing.Theme
    }

    # Preserve feature keys from existing config (or use defaults)
    $gameModeEnabled = $false
    $gameModeList = @()
    $wizardCompleted = $false
    $uiMode = "Full"
    $prefPlaybackGuid = ""
    $prefPlaybackName = ""
    $prefCommGuid = ""
    $prefCommName = ""

    if ($existing) {
        if ($existing.PSObject.Properties.Name -contains "GameModeEnabled") { $gameModeEnabled = [bool]$existing.GameModeEnabled }
        if ($existing.PSObject.Properties.Name -contains "GameModeList") { $gameModeList = @($existing.GameModeList) }
        if ($existing.PSObject.Properties.Name -contains "WizardCompleted") { $wizardCompleted = [bool]$existing.WizardCompleted }
        if ($existing.PSObject.Properties.Name -contains "UI_Mode") { $uiMode = [string]$existing.UI_Mode }
        if ($existing.PSObject.Properties.Name -contains "PreferredPlaybackDeviceGuid") { $prefPlaybackGuid = [string]$existing.PreferredPlaybackDeviceGuid }
        if ($existing.PSObject.Properties.Name -contains "PreferredPlaybackDeviceName") { $prefPlaybackName = [string]$existing.PreferredPlaybackDeviceName }
        if ($existing.PSObject.Properties.Name -contains "PreferredCommDeviceGuid") { $prefCommGuid = [string]$existing.PreferredCommDeviceGuid }
        if ($existing.PSObject.Properties.Name -contains "PreferredCommDeviceName") { $prefCommName = [string]$existing.PreferredCommDeviceName }
    }

    $cfg = [ordered]@{
        EnableLogging               = $EnableLogging
        LogEverySeconds             = $LogEverySeconds
        EnableTrayIcon              = $EnableTrayIcon
        EnableHotkey                = $EnableHotkey
        HotkeyMode                  = $HotkeyMode
        CustomHotkeyVirtualKey      = $CustomHotkeyVirtualKey
        OperatingMode               = $OperatingMode
        SetupPath                   = $SetupPath
        LogFile                     = $StandardLogFileTemplate
        ActiveProfileId             = $ActiveProfileId
        ProfilesEnabled             = @($ProfilesEnabled)
        MonitoredApps               = $monitoredApps
        Theme                       = $themeVal
        EnableAutoRecovery          = $EnableAutoRecovery
        GameModeEnabled             = $gameModeEnabled
        GameModeList                = $gameModeList
        WizardCompleted             = $wizardCompleted
        UI_Mode                     = $uiMode
        PreferredPlaybackDeviceGuid = $prefPlaybackGuid
        PreferredPlaybackDeviceName = $prefPlaybackName
        PreferredCommDeviceGuid     = $prefCommGuid
        PreferredCommDeviceName     = $prefCommName
    }

    $json = $cfg | ConvertTo-Json -Depth 6
    if (Get-Command Save-ContentAtomic -ErrorAction SilentlyContinue) {
        Save-ContentAtomic -Path $ConfigPath -Content $json
    }
    else {
        Set-Content -LiteralPath $ConfigPath -Value $json -Encoding UTF8
    }
}

# ----- Log file selection helpers -----
function Resolve-LogTemplatePath {
    param([string]$TemplatePath)

    if ([string]::IsNullOrWhiteSpace($TemplatePath)) { return $null }
    $today = (Get-Date -Format "yyyyMMdd")
    return $TemplatePath.Replace("{DATE}", $today)
}

function Get-NewestLogMatchingTemplate {
    param([string]$TemplatePath)

    try {
        if ([string]::IsNullOrWhiteSpace($TemplatePath)) { return $null }

        $dir = Split-Path -Parent $TemplatePath
        if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return $null }

        $leaf = Split-Path -Leaf $TemplatePath
        $pattern = $leaf.Replace("{DATE}", "*")

        $files = Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like $pattern }

        if (-not $files -or $files.Count -eq 0) { return $null }
        return ($files | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
    }
    catch {
        return $null
    }
}

function Get-PreferredSamishLogPath {
    try {
        if (Test-Path -LiteralPath $ConfigPath) {
            $cfgRaw = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($cfgRaw)) {
                $cfg = $cfgRaw | ConvertFrom-Json -ErrorAction Stop
                if ($cfg -and ($cfg.PSObject.Properties.Name -contains "LogFile") -and $cfg.LogFile) {

                    $resolvedToday = Resolve-LogTemplatePath ([string]$cfg.LogFile)
                    if ($resolvedToday -and (Test-Path -LiteralPath $resolvedToday)) {
                        return $resolvedToday
                    }

                    $newest = Get-NewestLogMatchingTemplate -TemplatePath ([string]$cfg.LogFile)
                    if ($newest) { return $newest }
                }
            }
        }
    }
    catch {
        # swallow; fall through
    }

    $fallbackNewest = Get-NewestLogMatchingTemplate -TemplatePath $StandardLogFileTemplate
    if ($fallbackNewest) { return $fallbackNewest }

    try {
        if ($StandardLogFile -and (Test-Path -LiteralPath $StandardLogFile)) {
            return $StandardLogFile
        }
    }
    catch {}

    return $null
}

# ----- Package sync helpers -----
function Sync-SamishRuntimeFiles {
    Ensure-InstallFolder

    foreach ($name in $RuntimeFiles) {
        $src = Join-Path $PackageDir $name
        $dst = Join-Path $InstallDir $name
        if (Test-Path -LiteralPath $src) {
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
    }

    $srcModules = Join-Path $PackageDir "Modules"
    $dstModules = Join-Path $InstallDir "Modules"

    if (Test-Path -LiteralPath $srcModules) {
        if (Test-Path -LiteralPath $dstModules) {
            Remove-Item -LiteralPath $dstModules -Recurse -Force -ErrorAction SilentlyContinue
        }
        Copy-Item -LiteralPath $srcModules -Destination $dstModules -Recurse -Force
    }

    $srcProfiles = Join-Path $PackageDir "Profiles"
    $dstProfiles = Join-Path $InstallDir "Profiles"

    if (Test-Path -LiteralPath $srcProfiles) {
        if (Test-Path -LiteralPath $dstProfiles) {
            Remove-Item -LiteralPath $dstProfiles -Recurse -Force -ErrorAction SilentlyContinue
        }
        Copy-Item -LiteralPath $srcProfiles -Destination $dstProfiles -Recurse -Force
    }

    $srcAssets = Join-Path $PackageDir "Assets"
    $dstAssets = Join-Path $InstallDir "Assets"

    if (Test-Path -LiteralPath $srcAssets) {
        if (Test-Path -LiteralPath $dstAssets) {
            Remove-Item -LiteralPath $dstAssets -Recurse -Force -ErrorAction SilentlyContinue
        }
        Copy-Item -LiteralPath $srcAssets -Destination $dstAssets -Recurse -Force
    }

    # Copy the setup executable to the persistent install directory so that
    # the tray icon "Open Settings" click survives reboots and source deletions.
    if (-not [string]::IsNullOrWhiteSpace($script:SetupExecutablePath) -and (Test-Path -LiteralPath $script:SetupExecutablePath)) {
        try {
            $setupFileName = [System.IO.Path]::GetFileName($script:SetupExecutablePath)
            $dstSetup = Join-Path $InstallDir $setupFileName
            Copy-Item -LiteralPath $script:SetupExecutablePath -Destination $dstSetup -Force
        }
        catch {
            # Fail-forward: setup copy failure should not block installation
        }
    }

    if (-not (Test-Path -LiteralPath $InstalledEnginePath)) {
        throw "SAMISH.ps1 was not copied to %APPDATA%\SAMISH. Ensure SAMISH.ps1 exists in the package folder."
    }
}

# ----- Device Profiles (scaffold) -----
$script:ActiveProfileId = "BEACN"
$script:ProfilesEnabled = @("BEACN")
$script:ProfileMetaById = @{}

function Get-ProfileDirectoryForSetup {
    $pkg = Join-Path $PackageDir "Profiles"
    if (Test-Path -LiteralPath $pkg) { return $pkg }

    $installed = Join-Path $InstallDir "Profiles"
    if (Test-Path -LiteralPath $installed) { return $installed }

    return $null
}

function Get-AvailableProfiles {
    $dir = Get-ProfileDirectoryForSetup
    if (-not $dir) { return @() }

    $files = Get-ChildItem -LiteralPath $dir -Filter "*.json" -File -ErrorAction SilentlyContinue
    if (-not $files) { return @() }

    $profiles = @()
    foreach ($f in $files) {
        try {
            $raw = Get-Content -LiteralPath $f.FullName -Raw
            if ([string]::IsNullOrWhiteSpace($raw)) { continue }
            $p = $raw | ConvertFrom-Json
            if (-not $p.id) { continue }

            $profiles += [pscustomobject]@{
                Id          = [string]$p.id
                DisplayName = $(if ($p.displayName) { [string]$p.displayName } else { [string]$p.id })
                Path        = $f.FullName
                Raw         = $p
            }
        }
        catch {}
    }

    $order = @("BEACN", "Voicemeeter", "GoXLR", "WaveLink", "Custom", "DEMO")
    $sortedProfiles = $profiles | Sort-Object {
        $idx = $order.IndexOf($_.Id)
        if ($idx -lt 0) { 0.5 } else { $idx }
    }

    return @($sortedProfiles)
}

function Load-ProfileSelectionFromConfigIntoSetup {
    $script:ActiveProfileId = "BEACN"
    $script:ProfilesEnabled = @("BEACN")

    try {
        if (Test-Path -LiteralPath $ConfigPath) {
            $cfg = (Get-Content -LiteralPath $ConfigPath -Raw) | ConvertFrom-Json
            if ($cfg) {
                if ($cfg.PSObject.Properties.Name -contains "ProfilesEnabled") {
                    $arr = @()
                    foreach ($x in $cfg.ProfilesEnabled) { if ($x) { $arr += [string]$x } }
                    if ($arr.Count -gt 0) { $script:ProfilesEnabled = $arr }
                }
                if ($cfg.PSObject.Properties.Name -contains "ActiveProfileId") {
                    $id = [string]$cfg.ActiveProfileId
                    if (-not [string]::IsNullOrWhiteSpace($id)) { $script:ActiveProfileId = $id }
                }
            }
        }
    }
    catch {}

    if (-not $script:ProfilesEnabled -or $script:ProfilesEnabled.Count -eq 0) {
        $script:ProfilesEnabled = @($script:ActiveProfileId)
    }
}
