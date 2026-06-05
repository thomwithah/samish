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
"@ -WarningAction SilentlyContinue -ErrorAction Stop
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
"@ -WarningAction SilentlyContinue -ErrorAction Stop
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
"@ -ReferencedAssemblies "System.Windows.Forms" -WarningAction SilentlyContinue -ErrorAction Stop
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
"@ -WarningAction SilentlyContinue -ErrorAction Stop
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

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint GetDpiForWindow(IntPtr hWnd);
}
"@ -WarningAction SilentlyContinue -ErrorAction Stop
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
"@ -WarningAction SilentlyContinue -ErrorAction Stop
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
"@ -WarningAction SilentlyContinue -ErrorAction Stop
    }
} catch {
    if (Get-Command Write-SetupLog -ErrorAction SilentlyContinue) {
        Write-SetupLog "Compile SamishTooltipForm Error: $_"
    }
}

try {
    if (-not ([System.Management.Automation.PSTypeName]'SamishTooltipForm').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Windows.Forms;
public class SamishTooltipForm : Form {
    public SamishTooltipForm() {
        this.FormBorderStyle = FormBorderStyle.None;
        this.ShowInTaskbar = false;
        this.StartPosition = FormStartPosition.Manual;
        this.TopMost = true;
        this.DoubleBuffered = true;
    }
    protected override bool ShowWithoutActivation {
        get { return true; }
    }
    protected override CreateParams CreateParams {
        get {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= 0x08000000; // WS_EX_NOACTIVATE
            cp.ExStyle |= 0x00000080; // WS_EX_TOOLWINDOW
            cp.ExStyle |= 0x00000020; // WS_EX_TRANSPARENT
            return cp;
        }
    }
}
"@ -ReferencedAssemblies "System.Windows.Forms" -WarningAction SilentlyContinue -ErrorAction Stop
    }
} catch {
    if (Get-Command Write-SetupLog -ErrorAction SilentlyContinue) {
        Write-SetupLog "Compile SamishTooltipFormV2 Error: $_"
    }
}

try {
    if (-not ([System.Management.Automation.PSTypeName]'SamishTooltipFormV2').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Windows.Forms;
using System.Drawing;
public class SamishTooltipFormV2 : Form {
    public Color BorderColor { get; set; }
    public SamishTooltipFormV2() {
        this.BorderColor = Color.FromArgb(170, 0, 255);
        this.FormBorderStyle = FormBorderStyle.None;
        this.ShowInTaskbar = false;
        this.StartPosition = FormStartPosition.Manual;
        this.TopMost = true;
        this.DoubleBuffered = true;
    }
    protected override bool ShowWithoutActivation {
        get { return true; }
    }
    protected override CreateParams CreateParams {
        get {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= 0x08000000; // WS_EX_NOACTIVATE
            cp.ExStyle |= 0x00000080; // WS_EX_TOOLWINDOW
            cp.ExStyle |= 0x00000020; // WS_EX_TRANSPARENT
            return cp;
        }
    }
    protected override void OnPaint(PaintEventArgs e) {
        base.OnPaint(e);
        using (Pen pen = new Pen(this.BorderColor, 1)) {
            Rectangle rect = this.ClientRectangle;
            rect.Width -= 1;
            rect.Height -= 1;
            e.Graphics.DrawRectangle(pen, rect);
        }
    }
}
"@ -ReferencedAssemblies "System.Windows.Forms", "System.Drawing" -WarningAction SilentlyContinue -ErrorAction Stop
    }
} catch {}

# Word-wrap helper function for tooltips
function global:Format-WrappedText {
    param(
        [string]$Text,
        [int]$MaxLineLength = 70
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    $paragraphs = $Text -split "`r?`n"
    $wrappedParagraphs = @()
    foreach ($para in $paragraphs) {
        if ([string]::IsNullOrWhiteSpace($para)) {
            $wrappedParagraphs += ""
            continue
        }
        $words = $para -split "\s+"
        $currentLine = ""
        $wrappedLines = @()
        foreach ($word in $words) {
            if ([string]::IsNullOrEmpty($currentLine)) {
                $currentLine = $word
            }
            elseif (($currentLine.Length + 1 + $word.Length) -le $MaxLineLength) {
                $currentLine += " " + $word
            }
            else {
                $wrappedLines += $currentLine
                $currentLine = $word
            }
        }
        if (-not [string]::IsNullOrEmpty($currentLine)) {
            $wrappedLines += $currentLine
        }
        $wrappedParagraphs += ($wrappedLines -join "`r`n")
    }
    return ($wrappedParagraphs -join "`r`n")
}

# Factory function for creating custom tooltip wrappers
function global:New-SamishToolTip {
    $tooltipWrapper = [PSCustomObject]@{
        ShowAlways = $true
    }
    $tooltipWrapper | Add-Member -MemberType ScriptMethod -Name "SetToolTip" -Value {
        param($control, $text)
        Register-CustomToolTip -Control $control -Text $text
    }
    return $tooltipWrapper
}

# Recursive function to find child control under screen point (supports disabled controls)
function global:Get-ControlAtPoint {
    param(
        [System.Windows.Forms.Control]$Parent,
        [System.Drawing.Point]$Point
    )
    if ($null -eq $Parent) { return $null }
    
    $clientPoint = $Parent.PointToClient($Point)
    
    if ($Parent -is [System.Windows.Forms.TabControl]) {
        $selectedTab = $Parent.SelectedTab
        if ($selectedTab) {
            $nested = Get-ControlAtPoint -Parent $selectedTab -Point $Point
            if ($nested) { return $nested }
        }
    }
    
    $child = $Parent.GetChildAtPoint($clientPoint)
    if ($child -and $child -ne $Parent) {
        $nested = Get-ControlAtPoint -Parent $child -Point $Point
        if ($nested) { return $nested }
        return $child
    }
    return $Parent
}

# Cleanup handler for controls with registered tooltips
function Handle-TooltipControlDisposed {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'sender',
        Justification = 'Standard .NET WinForms event delegate signature for Control.Disposed tooltip cleanup')]
    param($sender, $e)
    if ($script:CustomTooltipTexts -and $script:CustomTooltipTexts.ContainsKey($sender)) {
        $script:CustomTooltipTexts.Remove($sender)
    }
    if ($script:HoveredControl -eq $sender) {
        if ($script:TooltipForm -and -not $script:TooltipForm.IsDisposed) { $script:TooltipForm.Hide() }
        $script:HoveredControl = $null
    }
}

# Registers or updates tooltip text and starts the hover tracker timer
function global:Register-CustomToolTip {
    param($Control, $Text)
    if ($null -eq $Control) { return }
    
    # Initialize globals if not already present
    if ($null -eq $script:CustomTooltipTexts) {
        $script:CustomTooltipTexts = @{}
    }
    
    # Initialize the global active-control hover tracker timer if not already created
    if ($null -eq $script:TooltipTrackerTimer) {
        $script:HoveredControl = $null
        $script:HoverStartTick = 0
        $script:TooltipShown = $false
        
        $script:TooltipTrackerTimer = New-Object System.Windows.Forms.Timer
        $script:TooltipTrackerTimer.Interval = 100
        $script:TooltipTrackerTimer.add_Tick({
            try {
                $activeForm = [System.Windows.Forms.Form]::ActiveForm
                $isTooltipValid = ($script:TooltipForm -and -not $script:TooltipForm.IsDisposed)
                if ($null -eq $activeForm -or ($isTooltipValid -and $activeForm -eq $script:TooltipForm)) {
                    # Fallback to the most recently opened (last) visible form that is not the tooltip form
                    $activeForm = $null
                    $openForms = [System.Windows.Forms.Application]::OpenForms
                    for ($i = $openForms.Count - 1; $i -ge 0; $i--) {
                        $f = $openForms[$i]
                        $isTooltip = $isTooltipValid -and ($f -eq $script:TooltipForm)
                        if (-not $isTooltip -and $f.Visible) {
                            $activeForm = $f
                            break
                        }
                    }
                }
                
                if ($null -eq $activeForm) {
                    if ($isTooltipValid -and $script:TooltipForm.Visible) {
                        $script:TooltipForm.Hide()
                    }
                    $script:HoveredControl = $null
                    $script:HoverStartTick = 0
                    $script:TooltipShown = $false
                    return
                }
                
                # Clicks hide tooltips immediately
                if ([System.Windows.Forms.Control]::MouseButtons -ne [System.Windows.Forms.MouseButtons]::None) {
                    if ($isTooltipValid -and $script:TooltipForm.Visible) {
                        $script:TooltipForm.Hide()
                    }
                    $script:TooltipShown = $true # Suppress re-showing until mouse leaves/enters
                    return
                }
                
                $mousePos = [System.Windows.Forms.Cursor]::Position
                
                # Check if mouse is within the active form's window boundaries.
                # If the mouse leaves the active form, hide the tooltip immediately.
                $formBounds = New-Object System.Drawing.Rectangle($activeForm.Location, $activeForm.Size)
                if (-not $formBounds.Contains($mousePos)) {
                    if ($isTooltipValid -and $script:TooltipForm.Visible) {
                        $script:TooltipForm.Hide()
                    }
                    $script:HoveredControl = $null
                    $script:HoverStartTick = 0
                    $script:TooltipShown = $false
                    return
                }
                
                $ctrl = Get-ControlAtPoint -Parent $activeForm -Point $mousePos
                
                if ($ctrl -ne $script:HoveredControl) {
                    if ($isTooltipValid -and $script:TooltipForm.Visible) {
                        $script:TooltipForm.Hide()
                    }
                    $script:HoveredControl = $ctrl
                    $script:HoverStartTick = [Environment]::TickCount
                    $script:TooltipShown = $false
                }
                else {
                    if ($null -ne $ctrl -and $script:CustomTooltipTexts.ContainsKey($ctrl) -and -not $script:TooltipShown) {
                        $elapsed = [Environment]::TickCount - $script:HoverStartTick
                        if ($elapsed -lt 0) { $elapsed = 500 }
                        if ($elapsed -ge 500) {
                            $txt = $script:CustomTooltipTexts[$ctrl]
                            if (-not [string]::IsNullOrEmpty($txt)) {
                                Show-CustomTooltipWindow -Control $ctrl -Text $txt
                                $script:TooltipShown = $true
                            }
                        }
                    }
                    elseif ($null -ne $ctrl -and -not $script:CustomTooltipTexts.ContainsKey($ctrl)) {
                        if ($isTooltipValid -and $script:TooltipForm.Visible) {
                            $script:TooltipForm.Hide()
                        }
                    }
                }
            } catch {
                if (Get-Command Write-SetupLog -ErrorAction SilentlyContinue) {
                    Write-SetupLog "Tooltip Tracker Error: $_"
                }
            }
        })
        $script:TooltipTrackerTimer.Start()
    }
    
    # Store or update the text
    if ([string]::IsNullOrWhiteSpace($Text)) {
        if ($script:CustomTooltipTexts.ContainsKey($Control)) {
            $script:CustomTooltipTexts.Remove($Control)
        }
        return
    }
    
    $isNew = -not $script:CustomTooltipTexts.ContainsKey($Control)
    $script:CustomTooltipTexts[$Control] = $Text
    
    if ($isNew) {
        $Control.add_Disposed({ Handle-TooltipControlDisposed @args })
    }
}

# Renders the custom styled tooltip form near the mouse cursor
function global:Show-CustomTooltipWindow {
    param($Control, $Text)
    try {
        if ($null -eq $script:TooltipForm -or $script:TooltipForm.IsDisposed) {
            if (([System.Management.Automation.PSTypeName]'SamishTooltipFormV2').Type) {
                $script:TooltipForm = New-Object SamishTooltipFormV2
            } elseif (([System.Management.Automation.PSTypeName]'SamishTooltipForm').Type) {
                $script:TooltipForm = New-Object SamishTooltipForm
            } else {
                $script:TooltipForm = New-Object System.Windows.Forms.Form
                $script:TooltipForm.FormBorderStyle = "None"
                $script:TooltipForm.ShowInTaskbar = $false
                $script:TooltipForm.StartPosition = "Manual"
                $script:TooltipForm.TopMost = $true
                try {
                    $script:TooltipForm.GetType().GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic).SetValue($script:TooltipForm, $true, $null)
                } catch {}
            }
            
            $script:TooltipForm.AutoSize = $true
            $script:TooltipForm.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
            
            $script:TooltipLabel = New-Object System.Windows.Forms.Label
            $script:TooltipLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
            $script:TooltipLabel.AutoSize = $true
            $script:TooltipLabel.BackColor = [System.Drawing.Color]::Transparent
            
            $script:TooltipForm.Controls.Add($script:TooltipLabel)
        }
        
        $scale = 1.0
        if ($null -ne $script:DpiScale) { $scale = $script:DpiScale }
        
        if ($global:ThemeCustomActive) {
            $back = if ($global:ThemeCustomPanel) { $global:ThemeCustomPanel } else { [System.Drawing.Color]::FromArgb(18, 18, 22) }
            $fore = if ($global:ThemeCustomText) { $global:ThemeCustomText } else { [System.Drawing.Color]::FromArgb(255, 255, 255) }
        } else {
            $back = [System.Drawing.Color]::FromArgb(255, 255, 255)
            $fore = [System.Drawing.Color]::FromArgb(35, 35, 40)
        }
        
        $script:TooltipForm.BackColor = $back
        $script:TooltipForm.Padding = New-Object System.Windows.Forms.Padding([int](8 * $scale))
        $script:TooltipLabel.ForeColor = $fore
        $script:TooltipLabel.BackColor = [System.Drawing.Color]::Transparent
        
        $borderColor = if ($global:ThemeCustomActive) {
            if ($global:ThemeCustomSecondary) { $global:ThemeCustomSecondary } else { [System.Drawing.Color]::FromArgb(153, 51, 255) }
        } else {
            [System.Drawing.Color]::FromArgb(170, 0, 255) # Brand Purple
        }

        # If it is SamishTooltipFormV2, update BorderColor property natively.
        if ($script:TooltipForm.PSObject.Properties.Match('BorderColor').Count -gt 0) {
            $script:TooltipForm.BorderColor = $borderColor
            $script:TooltipForm.Invalidate()
        }
        
        $font = New-Object System.Drawing.Font("Segoe UI", [float](8.5 * $scale))
        $script:TooltipLabel.Font = $font
        if ($script:MainFormGdiResources) {
            [void]$script:MainFormGdiResources.Add($font)
        }
        
        $script:TooltipLabel.MaximumSize = New-Object System.Drawing.Size([int](400 * $scale), 0)
        
        $wrapped = Format-WrappedText -Text $Text -MaxLineLength 70
        $script:TooltipLabel.Text = $wrapped
        
        $cursorPos = [System.Windows.Forms.Cursor]::Position
        $x = $cursorPos.X + 15
        $y = $cursorPos.Y + 15
        
        $preferredSize = $script:TooltipForm.GetPreferredSize([System.Drawing.Size]::Empty)
        $w = $preferredSize.Width
        $h = $preferredSize.Height
        
        $screen = [System.Windows.Forms.Screen]::FromPoint($cursorPos)
        $bounds = $screen.WorkingArea
        
        if ($x + $w -gt $bounds.Right) {
            $x = $cursorPos.X - $w - 10
        }
        if ($y + $h -gt $bounds.Bottom) {
            $y = $cursorPos.Y - $h - 10
        }
        if ($x -lt $bounds.Left) { $x = $bounds.Left }
        if ($y -lt $bounds.Top) { $y = $bounds.Top }
        
        # Set Owner to prevent deactivating the containing dialog/form (keeps dropdown highlights active)
        if ($null -ne $Control) {
            $parentForm = $Control.FindForm()
            if ($parentForm -and $script:TooltipForm.Owner -ne $parentForm) {
                if ($script:TooltipForm.Visible) {
                    $script:TooltipForm.Hide()
                }
                $script:TooltipForm.Owner = $parentForm
            }
        }
        
        $script:TooltipForm.Location = New-Object System.Drawing.Point($x, $y)
        $script:TooltipForm.Show()
    } catch {
        if (Get-Command Write-SetupLog -ErrorAction SilentlyContinue) {
            Write-SetupLog "Show-CustomTooltipWindow Error: $_"
        }
    }
}

$swNative.Stop()
# Developer Note: Check $swNative.ElapsedMilliseconds if performance drops.
