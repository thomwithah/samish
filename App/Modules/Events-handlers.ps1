# ---------- Events Bootstrapper ----------
$AudioEndpointPsm1 = Join-Path $PSScriptRoot "AudioEndpoint.psm1"
$AudioEndpointPs1  = Join-Path $PSScriptRoot "AudioEndpoint.ps1"
if (Test-Path -LiteralPath $AudioEndpointPsm1) {
    Import-Module $AudioEndpointPsm1 -Force -ErrorAction SilentlyContinue
}
elseif (Test-Path -LiteralPath $AudioEndpointPs1) {
    . $AudioEndpointPs1
}

$GameModeGuardPsm1 = Join-Path $PSScriptRoot "GameModeGuard.psm1"
$GameModeGuardPs1  = Join-Path $PSScriptRoot "GameModeGuard.ps1"
if (Test-Path -LiteralPath $GameModeGuardPsm1) {
    Import-Module $GameModeGuardPsm1 -Force -ErrorAction SilentlyContinue
}
elseif (Test-Path -LiteralPath $GameModeGuardPs1) {
    . $GameModeGuardPs1
}

. "$PSScriptRoot\Logic.ps1"
. "$PSScriptRoot\ConfigBackup.Module.ps1"
. "$PSScriptRoot\Events.UI.Effects.ps1"
. "$PSScriptRoot\Events.Setup.ps1"
. "$PSScriptRoot\Events.Diagnostics.ps1"
 
# Initialise tooltips on load
Update-TestButtonsTooltips

