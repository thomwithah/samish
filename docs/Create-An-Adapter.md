# Developer Guide: How to Create a Custom Device Adapter

SAMISH utilizes an extensible, profile-driven adapter architecture. You can easily add support for unsupported audio routers, software mixers, or hardware interfaces by creating a new **Profile configuration** and an **Adapter script**.

Follow this step-by-step guide to implement a custom adapter.

---

## Step 1: Create a Profile JSON File

Every supported device has a JSON file located in the `App/Profiles/` directory.

Create a new file (e.g., `App/Profiles/MyMixer.json`) using the following schema:

```json
{
  "ProfileId": "MY_MIXER",
  "DisplayName": "My Custom Mixer",
  "ProcessName": "MyMixerApp",
  "ConfiguredPath": "C:\\Program Files\\MyMixer\\MyMixerApp.exe",
  "OperatingMode": "Graceful",
  "DelayOnWakeMs": 1500,
  "ShutdownWaitMs": 3000,
  "Description": "Automates sleep and recovery for My Custom Mixer interface.",
  "Tooltip": "Recommended configuration: Use Graceful shutdown mode to preserve routing states."
}
```

### Profile Fields Explained:
* **`ProfileId`:** A unique, uppercase string identifying the profile (e.g., `MY_MIXER`). This ID links the configuration to your PowerShell adapter functions.
* **`ProcessName`:** The name of the mixer executable process (without the `.exe` extension).
* **`OperatingMode`:** Default recovery mode (`Graceful` closes the app via UI handles, while `Classic` terminates it instantly).
* **`DelayOnWakeMs`:** Buffer time (in milliseconds) the helper waits after system wake before attempting to restart the software.
* **`ShutdownWaitMs`:** Buffer time (in milliseconds) the helper waits for the application to close before forcing a shutdown.

---

## Step 2: Create the Adapter Script

Next, create a matching PowerShell script in `App/Modules/Adapters/` named `Adapter.ProfileId.ps1`.
For example, if your `ProfileId` is `MY_MIXER`, name the file:
`App/Modules/Adapters/Adapter.MY_MIXER.ps1`

Your script **must** implement two functions matching the names:
* `Stop-<ProfileId>Adapter`
* `Start-<ProfileId>Adapter`

### Reference Implementation (`Adapter.MY_MIXER.ps1`):



```powershell
#requires -Version 5.1
# ==============================================================================
# SAMISH Device Adapter: MY_MIXER
# ==============================================================================
# Purpose: Manages the shutdown and startup cycle for My Custom Mixer software.
#
# Inputs:
#   Stop-MY_MIXERAdapter:
#     -ProcessName: Executable process name to stop (e.g., "MyMixerApp").
#     -ConfiguredPath: Full path to the executable.
#     -OperatingMode: Shutdown mode (Graceful vs Classic).
#     -WindowWakeDelayMs: Time buffer in milliseconds.
#     -ShutdownWaitMs: Shutdown timeout in milliseconds.
#
#   Start-MY_MIXERAdapter:
#     -ProcessName: Executable process name to launch.
#     -ConfiguredPath: Full path to the executable.
#
# Outputs:
#   Returns $true upon successful execution.
#
# Error Handling:
#   Utilizes try/catch fail-forward wrappers to ensure errors do not crash the engine.
# ==============================================================================

function Stop-MY_MIXERAdapter {
    param(
        [string]$ProcessName,
        [string]$ConfiguredPath,
        [string]$OperatingMode,
        [int]$WindowWakeDelayMs,
        [int]$ShutdownWaitMs
    )

    try {
        Log-Always "MY_MIXER ADAPTER: Stop requested for $ProcessName in $OperatingMode mode."
        
        # Insert custom stop logic here (e.g., custom API calls or process control)
        # For simple process closure, you can call standard helper functions:
        if ($OperatingMode -eq "Graceful") {
            # measured in ms (timeout)
            $stopped = Invoke-AppStopGraceful -ProcessName $ProcessName -TimeoutMs $ShutdownWaitMs
        } else {
            $stopped = Stop-Process -Name $ProcessName -Force -ErrorAction SilentlyContinue
        }

        return $true
    }
    catch {
        Log-Always "MY_MIXER stop error: $_"
        return $false
    }
}

function Start-MY_MIXERAdapter {
    param(
        [string]$ProcessName,
        [string]$ConfiguredPath
    )

    try {
        Log-Always "MY_MIXER ADAPTER: Start requested for $ProcessName at '$ConfiguredPath'."
        
        # Invoke-AppStart is a core helper that handles version path falls and UWP execution aliases
        $launched = Invoke-AppStart -ProcessName $ProcessName -ConfiguredPath $ConfiguredPath
        
        return $launched
    }
    catch {
        Log-Always "MY_MIXER start error: $_"
        return $false
    }
}
```

---

## Step 3: Register and Test the Adapter

Once both files are created:
1. Re-open or refresh the SAMISH Setup window.
2. Under **Device Settings**, your new profile ("My Custom Mixer") will dynamically appear in the profile selection panel.
3. Test your adapter immediately using the **Operating Mode Tests** panel in the Diagnostics drawer (click `Test Graceful` or `Start Test` to confirm your custom functions trigger successfully).
