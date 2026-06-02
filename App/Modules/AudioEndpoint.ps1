#requires -Version 5.1
# =============================================================================
# SAMISH Audio Endpoint Helper
# =============================================================================
# Purpose:  Gets and sets the default Windows audio playback and communications
#           devices using the MMDevice COM API. Used by the engine to restore
#           preferred audio endpoints after a sleep/wake cycle.
#
# Inputs:   Config keys: PreferredPlaybackDeviceGuid, PreferredPlaybackDeviceName,
#           PreferredCommDeviceGuid, PreferredCommDeviceName
#
# Outputs:  Get-DefaultAudioDeviceIds returns device GUIDs and names.
#           Set-DefaultAudioDevice sets the system default and returns success.
#
# Error handling: All COM calls wrapped in try/catch. Returns $null or $false
#                 on failure. Engine continues normally if audio endpoint
#                 management fails.
# =============================================================================

# Inline C# for MMDevice COM interop
# PolicyConfigClient is an undocumented COM class that Windows uses internally
# to set default audio devices. This approach is used by tools like SoundSwitch,
# AudioSwitcher, and nircmd.
$script:AudioEndpointTypeLoaded = $false
$script:AudioEndpointLoadError = $null

if (-not ([System.Management.Automation.PSTypeName]'SamishAudioEndpoint').Type) {
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace SamishAudio
{
    public class AudioDeviceItem
    {
        public string Guid { get; set; }
        public string Name { get; set; }
        public AudioDeviceItem(string guid, string name)
        {
            Guid = guid;
            Name = name;
        }
        public override string ToString()
        {
            return Name;
        }
    }
    // MMDevice COM interfaces (minimal subset needed for enumeration)
    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceEnumerator
    {
        int EnumAudioEndpoints(int dataFlow, int dwStateMask, out IMMDeviceCollection ppDevices);
        int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppEndpoint);
    }

    [Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceCollection
    {
        int GetCount(out int pcDevices);
        int Item(int nDevice, out IMMDevice ppDevice);
    }

    [Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDevice
    {
        int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
        int OpenPropertyStore(int stgmAccess, out IPropertyStore ppProperties);
        int GetId([MarshalAs(UnmanagedType.LPWStr)] out string ppstrId);
        int GetState(out int pdwState);
    }

    [Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IPropertyStore
    {
        int GetCount(out int cProps);
        int GetAt(int iProp, out PropertyKey pkey);
        int GetValue(ref PropertyKey key, out PropVariant pv);
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct PropertyKey
    {
        public Guid fmtid;
        public int pid;
        public PropertyKey(Guid fmtid, int pid) { this.fmtid = fmtid; this.pid = pid; }
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct PropVariant
    {
        public short vt;
        public short wReserved1, wReserved2, wReserved3;
        public IntPtr val1;
        public IntPtr val2;
    }

    // IPolicyConfig - undocumented COM interface for setting default device
    [Guid("F8679F50-850A-41CF-9C72-430F290290C8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IPolicyConfig
    {
        // Methods we don't use but need for vtable layout
        int GetMixFormat(string pszDeviceName, IntPtr ppFormat);
        int GetDeviceFormat(string pszDeviceName, int bDefault, IntPtr ppFormat);
        int ResetDeviceFormat(string pszDeviceName);
        int SetDeviceFormat(string pszDeviceName, IntPtr pEndpointFormat, IntPtr pMixFormat);
        int GetProcessingPeriod(string pszDeviceName, int bDefault, IntPtr pmftDefaultPeriod, IntPtr pmftMinimumPeriod);
        int SetProcessingPeriod(string pszDeviceName, IntPtr pmftPeriod);
        int GetShareMode(string pszDeviceName, IntPtr pMode);
        int SetShareMode(string pszDeviceName, IntPtr pMode);
        int GetPropertyValue(string pszDeviceName, int bFxStore, IntPtr key, IntPtr pv);
        int SetPropertyValue(string pszDeviceName, int bFxStore, IntPtr key, IntPtr pv);

        // The method we actually need:
        int SetDefaultEndpoint(
            [MarshalAs(UnmanagedType.LPWStr)] string wszDeviceId,
            int eRole);
    }

    // CLSID for PolicyConfigClient
    [ComImport, Guid("870AF99C-171D-4F9E-AF0D-E63DF40C2BC9")]
    internal class PolicyConfigClient { }

    // CLSID for MMDeviceEnumerator
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    internal class MMDeviceEnumeratorFactory { }

    public class SamishAudioEndpoint
    {
        // Role constants
        private const int eConsole = 0;        // Default playback device
        private const int eCommunications = 2; // Default communications device
        private const int eRender = 0;         // Render (output) devices
        private const int DEVICE_STATE_ACTIVE = 1;

        // PKEY_Device_FriendlyName
        private static readonly PropertyKey PKEY_FriendlyName = new PropertyKey(
            new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"), 14);

        public static string[][] GetPlaybackDevices()
        {
            var devicesList = new System.Collections.Generic.List<string[]>();
            try
            {
                var enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorFactory());
                IMMDeviceCollection collection;
                int hr = enumerator.EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, out collection);
                if (hr == 0 && collection != null)
                {
                    int count;
                    collection.GetCount(out count);
                    for (int i = 0; i < count; i++)
                    {
                        IMMDevice device;
                        collection.Item(i, out device);
                        if (device != null)
                        {
                            string id;
                            device.GetId(out id);
                            string name = GetDeviceFriendlyName(device);
                            devicesList.Add(new string[] { id, name });
                        }
                    }
                }
            }
            catch { }
            return devicesList.ToArray();
        }

        public static string[] GetDefaultPlaybackDevice()
        {
            try
            {
                var enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorFactory());
                IMMDevice device;
                int hr = enumerator.GetDefaultAudioEndpoint(eRender, eConsole, out device);
                if (hr != 0 || device == null) return null;

                string id;
                device.GetId(out id);
                string name = GetDeviceFriendlyName(device);
                return new string[] { id, name };
            }
            catch { return null; }
        }

        public static string[] GetDefaultCommDevice()
        {
            try
            {
                var enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorFactory());
                IMMDevice device;
                int hr = enumerator.GetDefaultAudioEndpoint(eRender, eCommunications, out device);
                if (hr != 0 || device == null) return null;

                string id;
                device.GetId(out id);
                string name = GetDeviceFriendlyName(device);
                return new string[] { id, name };
            }
            catch { return null; }
        }

        public static bool SetDefaultDevice(string deviceId, bool setPlayback, bool setComm)
        {
            try
            {
                var policyConfig = (IPolicyConfig)(new PolicyConfigClient());

                if (setPlayback)
                {
                    int hr1 = policyConfig.SetDefaultEndpoint(deviceId, eConsole);
                    if (hr1 != 0) return false;

                    // Also set multimedia role
                    policyConfig.SetDefaultEndpoint(deviceId, 1); // eMultimedia = 1
                }

                if (setComm)
                {
                    int hr2 = policyConfig.SetDefaultEndpoint(deviceId, eCommunications);
                    if (hr2 != 0) return false;
                }

                return true;
            }
            catch { return false; }
        }

        private static string GetDeviceFriendlyName(IMMDevice device)
        {
            try
            {
                IPropertyStore store;
                device.OpenPropertyStore(0, out store); // STGM_READ = 0
                PropVariant pv;
                var key = PKEY_FriendlyName;
                store.GetValue(ref key, out pv);
                if (pv.val1 != IntPtr.Zero)
                    return Marshal.PtrToStringUni(pv.val1);
            }
            catch { }
            return "(Unknown)";
        }
    }
}
"@ -WarningAction SilentlyContinue -ErrorAction Stop

        $script:AudioEndpointTypeLoaded = $true
    }
    catch {
        $script:AudioEndpointLoadError = $_.Exception.Message
    }
}
else {
    $script:AudioEndpointTypeLoaded = $true
}

function Get-DefaultAudioDeviceIds {
    <#
    .SYNOPSIS
        Returns the current default playback and communications audio device IDs and names.

    .OUTPUTS
        [hashtable] with keys: PlaybackGuid, PlaybackName, CommGuid, CommName.
        Returns $null if COM interop failed.
    #>

    if (-not $script:AudioEndpointTypeLoaded) {
        try { Log-Always "AudioEndpoint: COM type not loaded. Error: $($script:AudioEndpointLoadError)" } catch {}
        return $null
    }

    try {
        $playback = [SamishAudio.SamishAudioEndpoint]::GetDefaultPlaybackDevice()
        $comm = [SamishAudio.SamishAudioEndpoint]::GetDefaultCommDevice()

        $result = @{
            PlaybackGuid = if ($playback) { $playback[0] } else { "" }
            PlaybackName = if ($playback) { $playback[1] } else { "" }
            CommGuid     = if ($comm)     { $comm[0] }     else { "" }
            CommName     = if ($comm)     { $comm[1] }     else { "" }
        }

        return $result
    }
    catch {
        try { Log-Always "AudioEndpoint: Failed to get default devices: $_" } catch {}
        return $null
    }
}

function Set-DefaultAudioDevice {
    <#
    .SYNOPSIS
        Sets the default playback and/or communications audio device.

    .PARAMETER PlaybackDeviceId
        The device ID (GUID path) for the default playback device.

    .PARAMETER CommDeviceId
        The device ID (GUID path) for the default communications device.

    .OUTPUTS
        [bool] $true if at least one device was set successfully.
    #>
    param(
        [string]$PlaybackDeviceId = "",
        [string]$CommDeviceId = ""
    )

    if (-not $script:AudioEndpointTypeLoaded) {
        try { Log-Always "AudioEndpoint: COM type not loaded, cannot set device." } catch {}
        return $false
    }

    $anySet = $false

    # Set playback device
    if (-not [string]::IsNullOrWhiteSpace($PlaybackDeviceId)) {
        try {
            $result = [SamishAudio.SamishAudioEndpoint]::SetDefaultDevice($PlaybackDeviceId, $true, $false)
            if ($result) {
                try { Log-Always "AudioEndpoint: Set default playback device: $PlaybackDeviceId" } catch {}
                $anySet = $true
            }
            else {
                try { Log-Always "AudioEndpoint: Failed to set playback device: $PlaybackDeviceId" } catch {}
            }
        }
        catch {
            try { Log-Always "AudioEndpoint: Error setting playback device: $_" } catch {}
        }
    }

    # Set communications device
    if (-not [string]::IsNullOrWhiteSpace($CommDeviceId)) {
        try {
            $result = [SamishAudio.SamishAudioEndpoint]::SetDefaultDevice($CommDeviceId, $false, $true)
            if ($result) {
                try { Log-Always "AudioEndpoint: Set default comm device: $CommDeviceId" } catch {}
                $anySet = $true
            }
            else {
                try { Log-Always "AudioEndpoint: Failed to set comm device: $CommDeviceId" } catch {}
            }
        }
        catch {
            try { Log-Always "AudioEndpoint: Error setting comm device: $_" } catch {}
        }
    }

    return $anySet
}

function Get-AudioEndpoints {
    <#
    .SYNOPSIS
        Gets all active render (playback/output) audio endpoints.
    .OUTPUTS
        [array] of SamishAudio.AudioDeviceItem.
    #>
    if (-not $script:AudioEndpointTypeLoaded) {
        try { Log-Always "AudioEndpoint: COM type not loaded, cannot get device list." } catch {}
        return @()
    }

    try {
        $rawDevices = [SamishAudio.SamishAudioEndpoint]::GetPlaybackDevices()
        if (-not $rawDevices) { return @() }
        $devices = foreach ($dev in $rawDevices) {
            New-Object SamishAudio.AudioDeviceItem($dev[0], $dev[1])
        }
        return $devices
    }
    catch {
        try { Log-Always "AudioEndpoint: Failed to get audio endpoints: $_" } catch {}
        return @()
    }
}

