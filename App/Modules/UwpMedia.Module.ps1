# ==========================================
# SAMISH UWP SMTC Media Module
# ==========================================

# Developer Note: UWP WinRT API types require the System.Runtime.WindowsRuntime 
# assembly. Runspace threads must explicitly load this assembly. 
# Asynchronous SMTC operations are bound by a timeout threshold of 500 ms 
# to keep the caller thread responsive.

function Wait-UwpAsync {
    param(
        [Parameter(Mandatory = $true)]
        $AsyncOp,
        [Parameter(Mandatory = $true)]
        [Type]$ResultType
    )
    try {
        [void][System.Reflection.Assembly]::LoadWithPartialName("System.Runtime.WindowsRuntime")
        $asTaskMethods = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq "AsTask" }
        $asTaskMethod = $asTaskMethods | Where-Object {
            $params = $_.GetParameters()
            $params.Count -eq 1 -and $params[0].ParameterType.Name -eq 'IAsyncOperation`1'
        }
        if (-not $asTaskMethod) { return $null }
        $genericMethod = $asTaskMethod.MakeGenericMethod($ResultType)
        $task = $genericMethod.Invoke($null, @($AsyncOp))
        
        # Wait with 500 ms timeout to ensure thread responsiveness
        [void]$task.Wait(500)
        return $task.Result
    }
    catch {
        return $null
    }
}

function Get-SmtcSessionManager {
    try {
        [void][System.Reflection.Assembly]::LoadWithPartialName("System.Runtime.WindowsRuntime")
        $smtcType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
        $asyncOp = $smtcType::RequestAsync()
        return Wait-UwpAsync -AsyncOp $asyncOp -ResultType ($smtcType)
    }
    catch {}
    return $null
}

function Get-SmtcSessionForProcess {
    param([string]$ProcessName)
    if ([string]::IsNullOrWhiteSpace($ProcessName)) { return $null }
    try {
        $manager = Get-SmtcSessionManager
        if (-not $manager) { return $null }
        $sessions = $manager.GetSessions()
        foreach ($session in $sessions) {
            $sourceApp = $session.SourceAppUserModelId
            if (-not $sourceApp) { continue }
            $cleanName = $sourceApp
            if ($cleanName -match "([^\\]+)\.exe$") {
                $cleanName = $Matches[1]
            }
            elseif ($cleanName -match "^([^\!]+)\!") {
                $cleanName = $Matches[1]
            }
            if ($cleanName -match "^Spotify") { $cleanName = "spotify" }
            elseif ($cleanName -match "Chrome") { $cleanName = "chrome" }
            elseif ($cleanName -match "Edge") { $cleanName = "msedge" }
            elseif ($cleanName -match "Firefox") { $cleanName = "firefox" }

            if ($cleanName.ToLower() -eq $ProcessName.ToLower()) {
                return $session
            }
        }
    }
    catch {}
    return $null
}

function Get-SmtcPlaybackStatus {
    param([string]$ProcessName)
    $session = Get-SmtcSessionForProcess -ProcessName $ProcessName
    if (-not $session) { return 0 }
    try {
        $playbackInfo = $session.GetPlaybackInfo()
        if ($playbackInfo) {
            return [int]$playbackInfo.PlaybackStatus
        }
    }
    catch {}
    return 0
}

function Invoke-SmtcActionForProcess {
    param(
        [string]$ProcessName,
        [string]$Action
    )
    $session = Get-SmtcSessionForProcess -ProcessName $ProcessName
    if (-not $session) { return $false }
    try {
        if ($Action -eq "Pause") {
            $asyncOp = $session.TryPauseAsync()
            return Wait-UwpAsync -AsyncOp $asyncOp -ResultType ([bool])
        }
        elseif ($Action -eq "Play") {
            $asyncOp = $session.TryPlayAsync()
            return Wait-UwpAsync -AsyncOp $asyncOp -ResultType ([bool])
        }
    }
    catch {}
    return $false
}
