# ==========================================
# SAMISH App Control - Common Utilities
# ==========================================

function Get-AppExecutablePath {

    param(
        [string]$ProcessName = "BEACN",
        [string]$ConfiguredPath = $null,
        [string]$RegistrySearchString = $ProcessName
    )

    # ------------------------------------------
    # 1. Try Configured Path (highest priority)
    # ------------------------------------------
    if ($ConfiguredPath -and (Test-Path $ConfiguredPath)) {
        return @{
            Path    = $ConfiguredPath
            IsValid = $true
            Source  = "Config"
            Error   = ""
        }
    }

    # ------------------------------------------
    # 2. Try Running Process
    # ------------------------------------------
    try {
        $proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($proc -and $proc.MainModule -and $proc.MainModule.FileName) {

            $p = $proc.MainModule.FileName

            if (Test-Path $p) {
                return @{
                    Path    = $p
                    IsValid = $true
                    Source  = "Process"
                    Error   = ""
                }
            }
        }
    }
    catch {
        # Access to MainModule can fail in some contexts - ignore
    }

    # ------------------------------------------
    # 3. Try Registry (Uninstall entries)
    # ------------------------------------------
    try {
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"

        $entry = Get-ItemProperty $regPath -ErrorAction SilentlyContinue |
                 Where-Object { $_.DisplayName -match $RegistrySearchString } |
                 Select-Object -First 1

        if ($entry -and $entry.DisplayIcon) {

            $p = $entry.DisplayIcon.Split(',')[0].Replace('"','')

            if (Test-Path $p) {
                return @{
                    Path    = $p
                    IsValid = $true
                    Source  = "Registry"
                    Error   = ""
                }
            }
        }
    }
    catch {
        # Registry access errors ignored safely
    }

    # ------------------------------------------
    # 4. Failure
    # ------------------------------------------
    return @{
        Path    = $null
        IsValid = $false
        Source  = "None"
        Error   = "Unable to locate executable for $ProcessName"
    }
}