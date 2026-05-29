# ==========================================
# SAMISH Native Methods
# ==========================================
# Developer Note: Native methods must use Global: scope modifiers or class checks 
# before calling Add-Type to prevent Type-Redefinition exceptions if Setup is 
# run multiple times within the same PowerShell host process context.
# Compilation steps are expected to complete in under 150 ms.

$swNative = [System.Diagnostics.Stopwatch]::StartNew()

try {
    if (-not ([System.Management.Automation.PSTypeName]'SamishConsoleHelper').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class SamishConsoleHelper {
  [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@ -ErrorAction Stop
    }
} catch {
    if (Get-Command Write-SamishSetupTrace -ErrorAction SilentlyContinue) {
        Write-SamishSetupTrace -Message "Failed to compile SamishConsoleHelper. OS policies may block runtime C# compilation. Details: $($_.Exception.Message)" -Level "WARN"
    }
}

try {
    if (-not ([System.Management.Automation.PSTypeName]'SamishShellApi').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class SamishShellApi {
    [DllImport("shell32.dll", SetLastError = true)]
    public static extern int SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string AppID);
}
"@ -ErrorAction Stop
    }
} catch {
    if (Get-Command Write-SamishSetupTrace -ErrorAction SilentlyContinue) {
        Write-SamishSetupTrace -Message "Failed to compile SamishShellApi. Details: $($_.Exception.Message)" -Level "WARN"
    }
}

try {
    if (-not ([System.Management.Automation.PSTypeName]'PowerEventArgs').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Windows.Forms;

public class PowerEventArgs : EventArgs {
    public int EventType { get; set; }
    public PowerEventArgs(int eventType) {
        this.EventType = eventType;
    }
}

public class PowerNotificationForm : Form {
    public event EventHandler<PowerEventArgs> PowerEventOccurred;

    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x0218) { // WM_POWERBROADCAST
            int wp = m.WParam.ToInt32();
            if (PowerEventOccurred != null) {
                PowerEventOccurred(this, new PowerEventArgs(wp));
            }
        }
        base.WndProc(ref m);
    }
}
"@ -ReferencedAssemblies "System.Windows.Forms" -ErrorAction Stop
    }
} catch {
    $global:PowerTypeSigError = $_.Exception.Message
}

try {
    if (-not ([System.Management.Automation.PSTypeName]'SamishIdleNative').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class SamishIdleNative {
  [StructLayout(LayoutKind.Sequential)]
  public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
  [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
  public static uint GetIdleMilliseconds() {
    LASTINPUTINFO li = new LASTINPUTINFO();
    li.cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf(li);
    GetLastInputInfo(ref li);
    return (uint)Environment.TickCount - li.dwTime;
  }
}
"@ -ErrorAction Stop
    }
} catch {
    $global:IdleNativeError = $_.Exception.Message
}

try {
    if (-not ([System.Management.Automation.PSTypeName]'SamishWin32').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class SamishWin32 {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr FindWindow(IntPtr lpClassName, string lpWindowName);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
}
"@ -ErrorAction Stop
    }
} catch {
    # Logging handled by callers
}

try {
    if (-not ([System.Management.Automation.PSTypeName]'SamishKeyState').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class SamishKeyState {
  [DllImport("user32.dll")]
  public static extern short GetAsyncKeyState(int vKey);
}
"@ -ErrorAction Stop
    }
} catch {
    # Logging handled by callers
}

try {
    if (-not ([System.Management.Automation.PSTypeName]'SamishCursorHelper').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class SamishCursorHelper {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr LoadCursor(IntPtr hInstance, int lpCursorName);
}
"@ -ErrorAction Stop
    }
} catch {}

$swNative.Stop()
# Developer Note: Check $swNative.ElapsedMilliseconds if performance drops.
