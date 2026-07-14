# ==========================================
# SAMISH (Streaming Audio Mixer Interface Sleep Helper) - Setup UI (PS 5.1 compatible)
# Created by thomwithah
# Version: 1.3.8
# ==========================================
# Place this Setup.ps1 in the same folder as:
#   - SAMISH.ps1
#   - SAMISH-HiddenTask.xml
#   - SAMISH-InteractiveTask.xml
# ==========================================

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'StateFile',
    Justification = 'Consumed by dot-sourced module Events.Setup.ps1')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'InstallMode',
    Justification = 'Consumed by dot-sourced module Install.Engine.ps1')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'OperatingMode',
    Justification = 'Consumed by dot-sourced module Install.Engine.ps1')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'EnableTrayIcon',
    Justification = 'Consumed by dot-sourced module Events.Setup.ps1')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'EnableHotkey',
    Justification = 'Consumed by dot-sourced module Events.Setup.ps1')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'HotkeyMode',
    Justification = 'Consumed by dot-sourced module Events.Setup.ps1')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'CustomHotkey',
    Justification = 'Consumed by dot-sourced module Events.Setup.ps1')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ApplyPowerPlanFix',
    Justification = 'Consumed by dot-sourced module Events.Setup.ps1')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'AcceptPowerPlanChanges',
    Justification = 'Consumed by dot-sourced module Events.Setup.ps1')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'EnableLogging',
    Justification = 'Consumed by dot-sourced module Events.Setup.ps1')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'LogEverySeconds',
    Justification = 'Consumed by dot-sourced module Events.Setup.ps1')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'EnableAutoRecovery',
    Justification = 'Consumed by dot-sourced module Install.Engine.ps1')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'tooltip',
    Justification = 'Consumed by dot-sourced modules UI.SetupTab.ps1 and UI.DiagTab.ps1')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'ProductName',
    Justification = 'Consumed by dot-sourced module UI.SetupTab.ps1')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'ProductLong',
    Justification = 'Consumed by dot-sourced module UI.SetupTab.ps1')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'ProductVersion',
    Justification = 'Consumed by dot-sourced module UI.SetupTab.ps1')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'AuthorLine',
    Justification = 'Consumed by dot-sourced module UI.SetupTab.ps1')]
param(
    [string]$StateFile = "",

    # -------- CLI / No-UI install routing --------
    [switch]$CliInstall,

    # InstallMode chooses which scheduled task XML to install
    # Hidden = SAMISH (Hidden) task (logon + registration trigger)
    # Interactive = SAMISH (Interactive) task (logon trigger)
    [ValidateSet("Hidden", "Interactive")]
    [string]$InstallMode = "Hidden",

    # OperatingMode maps to engine behavior (Graceful vs Classic)
    [ValidateSet("Graceful", "Classic")]
    [string]$OperatingMode = "Graceful",

    # Optional feature flags for Interactive installs (mirrors UI concepts)
    [switch]$EnableTrayIcon,
    [switch]$EnableHotkey,
    [ValidateSet("ScrollLock", "PauseBreak", "F12", "Custom")]
    [string]$HotkeyMode = "ScrollLock",
    [string]$CustomHotkey = "F8",

    # Power plan behavior: CLI does NOT change power plan unless explicitly requested
    [switch]$ApplyPowerPlanFix,
    [switch]$AcceptPowerPlanChanges,

    # Logging defaults (CLI keeps conservative defaults unless explicitly set)
    [switch]$EnableLogging,
    [int]$LogEverySeconds = 30,

    # Auto-Recovery
    [bool]$EnableAutoRecovery = $true
)

# Set process execution policy to Bypass so dot-sourced modules can load cleanly during boot.
# Wrapped in a try/catch to fail-forward if blocked by strict domain environment policies.
$script:ExecutionPolicyBypassError = $null
try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
}
catch {
    $script:ExecutionPolicyBypassError = $_
}

#region Native Methods
$NativeMethodsPath = $PSScriptRoot
if (-not $NativeMethodsPath -and $PSCommandPath) { $NativeMethodsPath = Split-Path -Parent $PSCommandPath }
if (-not $NativeMethodsPath) { $NativeMethodsPath = [System.AppDomain]::CurrentDomain.BaseDirectory }
$NativeMethodsPath = Join-Path $NativeMethodsPath "App\Modules\NativeMethods.ps1"
if (Test-Path -LiteralPath $NativeMethodsPath) {
    . $NativeMethodsPath
}
#endregion

# ---------- Early Boot Trace Logger ----------
# Must be defined before any code that calls it (e.g., AppUserModelID registration).
function Write-SamishSetupTrace {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )

    # Determine if truly in a console-hosted CLI run.
    #  If running under powershell.exe/pwsh.exe with -CliInstall, it's safe to write to console.
    #  If running as compiled EXE, avoid *all* output streams (PS2EXE can turn them into MessageBoxes).
    $isCliConsole = $false
    try {
        $procName = (Get-Process -Id $PID -ErrorAction SilentlyContinue).Name
        if ($CliInstall -and ($procName -in @("powershell", "pwsh"))) {
            $isCliConsole = $true
        }
    }
    catch { }

    $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message

    if ($isCliConsole) {
        # Console path (safe)
        try { Write-Host $line } catch { }
        return
    }

    # Compiled EXE (or any non-console host) path: write to %TEMP%
    try {
        $path = Join-Path $env:TEMP "SAMISH_Setup_trace.log"

        # Rolling rotation: if the log exceeds 969 KB, shift history files # measured in KB
        if (Test-Path -LiteralPath $path) {
            $fileInfo = [System.IO.FileInfo]::new($path)
            if ($fileInfo.Length -gt 992256) { # 969 * 1024 = 992256 bytes
                $dir = $fileInfo.DirectoryName
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($path)
                $ext = [System.IO.Path]::GetExtension($path)
                # Delete the oldest (slot 5) if it exists
                $oldest = Join-Path $dir "$baseName.5$ext"
                if (Test-Path -LiteralPath $oldest) {
                    Remove-Item -LiteralPath $oldest -Force -ErrorAction SilentlyContinue
                }
                # Shift .4 -> .5, .3 -> .4, .2 -> .3, .1 -> .2
                for ($i = 4; $i -ge 1; $i--) {
                    $src = Join-Path $dir "$baseName.$i$ext"
                    $dst = Join-Path $dir "$baseName.$($i + 1)$ext"
                    if (Test-Path -LiteralPath $src) {
                        [System.IO.File]::Move($src, $dst)
                    }
                }
                # Move current log to .1
                $slot1 = Join-Path $dir "$baseName.1$ext"
                [System.IO.File]::Move($path, $slot1)
            }
        }

        Add-Content -LiteralPath $path -Value $line
    }
    catch { }
}

# ---------- Strategy A: Custom Taskbar Icon AppUserModelID Registration ----------
$isCompiled = ($MyInvocation.MyCommand.Name -like "*.exe")
if (-not $isCompiled) {
    try {
        if (([System.Management.Automation.PSTypeName]'SamishShellApi').Type) {
            [void][SamishShellApi]::SetCurrentProcessExplicitAppUserModelID("Thomwithah.SAMISH.Setup.v1")
        }
    }
    catch {
        Write-SamishSetupTrace -Message "Failed to execute AppUserModelID Registration: $($_.Exception.Message)" -Level "WARN"
    }
}

# ---------- Find current PS execution mode ----------
function Get-CurrentExecutionMode {
    try {
        # Get the parent process name (the one that launched us)
        $parent = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $PID" | Select-Object ParentProcessId
        if ($parent) {
            $ppid = $parent.ParentProcessId
            $parentProcess = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $ppid" | Select-Object Name
            
            if ($parentProcess) {
                $parentName = $parentProcess.Name.ToLower()
                
                # Check if running from PowerShell console
                if ($parentName -eq "powershell.exe" -or $parentName -eq "pwsh.exe") {
                    return "Console"
                }
            }
        }
    }
    catch {
        # If we can't determine, default to Exe
    }
    
    return "Exe"
}

# Helper to safely resolve a single TextBox from potential array or PSObject-wrapped collections in persistent sessions
function Get-LatestControl {
    param($ControlVar)
    $resolved = $null
    foreach ($item in $ControlVar) {
        if ($item -is [System.Windows.Forms.Control]) {
            $resolved = $item
        }
    }
    return $resolved
}

# ----- LOAD ADAPTERS -------------------------------------------------
# Load all adapter scripts (*.ps1) from the Adapters folder.
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir -and $PSCommandPath) { $ScriptDir = Split-Path -Parent $PSCommandPath }
if (-not $ScriptDir) { $ScriptDir = [System.AppDomain]::CurrentDomain.BaseDirectory }
if ($ScriptDir -and $ScriptDir.EndsWith("\")) { $ScriptDir = $ScriptDir.TrimEnd("\") }
$PackageDir = Join-Path $ScriptDir "App"
$AdaptersPath = Join-Path $PackageDir 'Modules\Adapters'
if (Test-Path -LiteralPath $AdaptersPath) {
    Get-ChildItem -Path $AdaptersPath -Filter '*.ps1' -File | ForEach-Object {
        try {
            . $_.FullName
        }
        catch {
            Write-Host "WARN: Failed to load adapter $($_.Name) - $_"
        }
    }
}


# ---------- ALWAYS RUN SETUP AS ADMIN ----------
function Ensure-AdminAtStartup {
    if ($global:SamishScreenshotMode) { return }
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    $isAdmin = $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($isAdmin) { return }

    # CLI must remain deterministic (no surprise GUI relaunch + lost Tee output)
    if ($CliInstall) {
        Write-Host "ERROR: SAMISH CLI install must be run from an elevated PowerShell session."
        Write-Host "Tip: Right-click PowerShell and choose 'Run as administrator', then rerun the same command."
        exit 1
    }

    # GUI mode: auto-elevate by relaunching the script
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    
    $currentFile = $PSCommandPath
    if (-not $currentFile) { $currentFile = [System.AppDomain]::CurrentDomain.BaseDirectory }
    
    if ($currentFile -and $currentFile.EndsWith(".ps1", [System.StringComparison]::OrdinalIgnoreCase)) {
        $psi.FileName = "powershell.exe"
        $psi.Arguments = "-ExecutionPolicy Bypass -NoProfile -STA -File `"$currentFile`""
    }
    else {
        # It's an EXE!
        $psi.FileName = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $psi.Arguments = ""
    }
    
    $psi.Verb = "runas"

    try { 
        $elevatedProc = [System.Diagnostics.Process]::Start($psi)
        if ($elevatedProc) {
            $elevatedProc.WaitForExit()
        }
    }
    catch { }
    exit
}
Ensure-AdminAtStartup

# Resolve the setup executable path for config.json persistence.
# When compiled via PS2EXE, $PSCommandPath points to a temporary extracted .ps1
# inside %TEMP% that is deleted on reboot. Detect compiled mode by checking
# whether the host process is powershell.exe/pwsh.exe; if not, the process
# itself IS the compiled Setup.exe and we use its module path directly.
$script:SetupExecutablePath = $null
try {
    $hostProc = [System.Diagnostics.Process]::GetCurrentProcess()
    $hostName = $hostProc.ProcessName.ToLower()
    if ($hostName -eq "powershell" -or $hostName -eq "pwsh") {
        # Running as a script under PowerShell -- use the script path
        $script:SetupExecutablePath = $PSCommandPath
    } else {
        # Running as a compiled EXE -- use the binary path
        $script:SetupExecutablePath = $hostProc.MainModule.FileName
    }
} catch {
    # Fail-forward: fall back to $PSCommandPath
}
if (-not $script:SetupExecutablePath) {
    $script:SetupExecutablePath = $PSCommandPath
}
if (-not $script:SetupExecutablePath) {
    $script:SetupExecutablePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
}

# ---------- SINGLE INSTANCE GUARD ----------
function Ensure-SingleInstance {
    if ($global:SamishScreenshotMode) { return $true }

    try {
        $mutexName = "Global\SAMISH_Setup_UI"

        $createdNew = $false
        $mutex = [System.Threading.Mutex]::new($true, $mutexName, [ref]$createdNew)

        if (-not $createdNew) {

            [System.Windows.Forms.MessageBox]::Show(
                "SAMISH Setup is already running.",
                "SAMISH Setup",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null

            return $false
        }

        # Keep reference alive for app lifetime
        $script:SamishSetupMutex = $mutex
        return $true
    }
    catch {
        # Fail open: allow setup to run if mutex fails
        return $true
    }
}

# ---------- Shutdown / Cleanup Helper----------
function Complete-SamishSetupUi {
    param(
        [System.Windows.Forms.Form]$Form
    )

    # 1) Release the single-instance mutex (GUI path doesn't currently guarantee release)
    try {
        if ($script:SamishSetupMutex) {
            $null = $script:SamishSetupMutex.ReleaseMutex()
            $script:SamishSetupMutex.Dispose()
            $script:SamishSetupMutex = $null
        }
    }
    catch { }

    # 2) Best-effort dispose of common UI resources (no behavior change; just cleanup)
    try {
        if ($script:LiveLogTimer) {
            $script:LiveLogTimer.Stop()
            $script:LiveLogTimer.Dispose()
            $script:LiveLogTimer = $null
        }
    }
    catch { }

    try {
        if ($script:ActiveBlockerTimer) {
            $script:ActiveBlockerTimer.Stop()
            $script:ActiveBlockerTimer.Dispose()
            $script:ActiveBlockerTimer = $null
        }
    }
    catch { }

    try {
        if ($script:TooltipTrackerTimer) {
            $script:TooltipTrackerTimer.Stop()
            $script:TooltipTrackerTimer.Dispose()
            $script:TooltipTrackerTimer = $null
        }
    }
    catch { }

    try {
        if ($script:TooltipForm) {
            $script:TooltipForm.Dispose()
            $script:TooltipForm = $null
        }
    }
    catch { }

    try {
        if ($script:btnLivePause) { $script:btnLivePause.Dispose() }
        if ($script:btnLiveCopy) { $script:btnLiveCopy.Dispose() }
        if ($script:btnLiveClear) { $script:btnLiveClear.Dispose() }
    }
    catch { }

    # 3) Dispose the form itself
    try {
        if ($Form) { $Form.Dispose() }
    }
    catch { }

    # Dispose script-level GDI resources
    try {
        if ($script:MainFormGdiResources) {
            foreach ($res in $script:MainFormGdiResources) {
                if ($res) {
                    try { $res.Dispose() } catch {}
                }
            }
            $script:MainFormGdiResources.Clear()
        }
    }
    catch { }

    # 4) OPTIONAL debug trace (never shows a MessageBox)
    # Enable by setting environment variable: SAMISH_SETUP_DEBUG=1
    if ($env:SAMISH_SETUP_DEBUG -eq "1") {
        try {
            $debugPath = Join-Path $env:TEMP "SAMISH_Setup_debug.log"

            $disposed = $false
            try { if ($Form) { $disposed = [bool]$Form.IsDisposed } } catch { }

            Add-Content -LiteralPath $debugPath -Value (
                "{0} - Setup closed. FormDisposed={1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $disposed
            )
        }
        catch { }
    }
}

# (Write-SamishSetupTrace is defined near the top of the file, before first use.)

# Safe deferred logging of any boot-time execution policy bypass errors
if ($script:ExecutionPolicyBypassError) {
    Write-SamishSetupTrace -Message "Failed to set process execution policy: $($script:ExecutionPolicyBypassError.Exception.Message)" -Level "WARN"
}

if (-not $CliInstall) {
    try {
        if (([System.Management.Automation.PSTypeName]'SamishConsoleHelper').Type) {
            $console = [SamishConsoleHelper]::GetConsoleWindow()
            if ($console -ne [IntPtr]::Zero) {
                [void][SamishConsoleHelper]::ShowWindow($console, 0)
            }
        }
    }
    catch {
        Write-SamishSetupTrace -Message "Failed to hide console window: $($_.Exception.Message)" -Level "WARN"
    }
}

# ---------- UI assemblies ----------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$setupOk = Ensure-SingleInstance
if (-not $setupOk) { return }

try {

    # ----- TOOLTIP OBJECT -----
    $tooltip = New-SamishToolTip

    # ---------- Constants ----------
    $ProductName = "SAMISH"
    $ProductLong = "SAMISH (Streaming Audio Mixer Interface Sleep Helper)"
    $ProductVersion = "v1.3.8"
    $AuthorLine = "Created by thomwithah"

    $TaskHiddenNoSlash = "SAMISH (Hidden)"
    $TaskInteractiveNoSlash = "SAMISH (Interactive)"
    $TaskHidden = "\SAMISH (Hidden)"
    $TaskInteractive = "\SAMISH (Interactive)"

    # ---------- Standard log path ----------
    # Store logs alongside config/runtime in %APPDATA%\SAMISH and rotate daily.
    $StandardLogFile = Join-Path $env:APPDATA ("SAMISH\samish_{0}.log" -f (Get-Date -Format "yyyyMMdd"))
    $StandardLogFileTemplate = Join-Path $env:APPDATA "SAMISH\samish_{DATE}.log"

    # ---------- Paths ----------
    $ScriptDir = $PSScriptRoot
    if (-not $ScriptDir -and $PSCommandPath) { $ScriptDir = Split-Path -Parent $PSCommandPath }
    if (-not $ScriptDir) { $ScriptDir = [System.AppDomain]::CurrentDomain.BaseDirectory }
    if ($ScriptDir -and $ScriptDir.EndsWith("\")) { $ScriptDir = $ScriptDir.TrimEnd("\") }
    $PackageDir = Join-Path $ScriptDir "App"


    # ----- LOAD MODULES -----
    $LoggerModulePath = Join-Path $PackageDir "Modules\Logger.psm1"
    if (Test-Path -LiteralPath $LoggerModulePath) {
        Import-Module $LoggerModulePath -Force -DisableNameChecking
    }

    $PowerPlanCommonPath = Join-Path $PackageDir "Modules\PowerPlan.Read.Common.ps1"
    if (Test-Path -LiteralPath $PowerPlanCommonPath) {
        . $PowerPlanCommonPath
    }

    $ModulePath = Join-Path $PackageDir "Modules\PowerPlan.Module.ps1"
    if (Test-Path -LiteralPath $ModulePath) {
        . $ModulePath
    }

    $ClassicModulePath = Join-Path $PackageDir "Modules\App.Control.Classic.ps1"
    if (Test-Path -LiteralPath $ClassicModulePath) {
        . $ClassicModulePath
    }

    # App.Control.Common provides Get-AppExecutablePath (used by Operating Mode Tests)
    $CommonModulePath = Join-Path $PackageDir "Modules\App.Control.Common.ps1"
    if (Test-Path -LiteralPath $CommonModulePath) {
        . $CommonModulePath
    }

    # App.Control.Graceful provides Invoke-AppStopGraceful (used by Operating Mode Tests)
    $GracefulModulePath = Join-Path $PackageDir "Modules\App.Control.Graceful.ps1"
    if (Test-Path -LiteralPath $GracefulModulePath) {
        . $GracefulModulePath
    }

    $DiagModulePath = Join-Path $PackageDir "Modules\Diagnostics.Module.ps1"
    if (Test-Path -LiteralPath $DiagModulePath) {
        . $DiagModulePath
    }

    $InstallEnginePath = Join-Path $PackageDir "Modules\Install.Engine.ps1"
    if (Test-Path -LiteralPath $InstallEnginePath) {
        . $InstallEnginePath
    }

    $ValidationModulePath = Join-Path $PackageDir "Modules\Validation.Module.ps1"
    if (Test-Path -LiteralPath $ValidationModulePath) {
        . $ValidationModulePath
    }

    $SetupHelpersPath = Join-Path $PackageDir "Modules\Setup.Helpers.ps1"
    if (Test-Path -LiteralPath $SetupHelpersPath) {
        . $SetupHelpersPath
    }

    $TaskHelpersPath = Join-Path $PackageDir "Modules\Task.Helpers.ps1"
    if (Test-Path -LiteralPath $TaskHelpersPath) {
        . $TaskHelpersPath
    }

    $DiagDisplayPath = Join-Path $PackageDir "Modules\Diagnostics.Display.ps1"
    if (Test-Path -LiteralPath $DiagDisplayPath) {
        . $DiagDisplayPath
    }

    $ConfigHelpersPath = Join-Path $PackageDir "Modules\Config.Helpers.ps1"
    if (Test-Path -LiteralPath $ConfigHelpersPath) {
        . $ConfigHelpersPath
    }

    $LiveLogModulePath = Join-Path $PackageDir "Modules\LiveLog.Module.ps1"
    if (Test-Path -LiteralPath $LiveLogModulePath) {
        . $LiveLogModulePath
    }

    $FirstRunWizardPath = Join-Path $PackageDir "Modules\FirstRunWizard.ps1"
    if (Test-Path -LiteralPath $FirstRunWizardPath) {
        . $FirstRunWizardPath
    }

    # ---------- Log-Always shim (Setup context) ----------
    # App.Control.Graceful and adapter scripts call Log-Always, which the engine
    # defines in its own scope. Provide a lightweight shim here so those modules
    # can run inside Setup without throwing on an undefined function.
    if (-not (Get-Command Log-Always -ErrorAction SilentlyContinue)) {
        function Log-Always([string]$msg) {
            Write-SetupLog $msg
        }
    }

    # ---------- Install + Config paths ----------
    $InstallDir = Join-Path $env:APPDATA "SAMISH"
    $ConfigPath = Join-Path $InstallDir "config.json"
    $InstalledEnginePath = Join-Path $InstallDir "SAMISH.ps1"
    # Used by PowerPlan.Module.ps1 (shared via scope) for backup/restore operations; not intended as a general-purpose log.
    $script:PowerPlanBackupPath = Join-Path $InstallDir "powerplan_backup.json"

    $RuntimeFiles = @(
        "SAMISH.ps1",
        "SAMISH-HiddenTask.xml",
        "SAMISH-InteractiveTask.xml",
        "Configure-CustomProfile.ps1",
        "Configure-CustomProfile.bat"
    )

    # ---------- Core helpers (logging, dialogs, power plan, install mode) ----------
    # Extracted to Modules\Setup.Helpers.ps1 (dot-sourced above in LOAD MODULES)

    # ----- Config write, log file selection, package sync, profiles -----
    # Extracted to Modules\Config.Helpers.ps1 (dot-sourced above in LOAD MODULES)

    # ----- Live Log (in Status box) helpers -----
    # Extracted to Modules\LiveLog.Module.ps1 (dot-sourced above in LOAD MODULES)

    # ----- Startup Shortcut, schtasks wrappers, Process Control, Hotkey + Log Parsing -----
    # Extracted to Modules\Task.Helpers.ps1 (dot-sourced above in LOAD MODULES)


    # ---------- Diagnostics Header, Show-CurrentConfiguration, Place-Below ----------
    # Extracted to Modules\Diagnostics.Display.ps1 (dot-sourced above in LOAD MODULES)

    # ---------- CLI Routing ----------
    if ($CliInstall) {
        try {
            Invoke-CliInstallRoute
            exit 0
        }
        catch {
            Write-Host ("CLI install failed: " + $_.Exception.Message)
            exit 1
        }
        finally {
            try {
                if ($script:SamishSetupMutex) {
                    $null = $script:SamishSetupMutex.ReleaseMutex()
                    $script:SamishSetupMutex.Dispose()
                    $script:SamishSetupMutex = $null
                }
            }
            catch {}
        }
    }


    # ---------- UI Layout & Wiring ----------
    $UIModulePath = Join-Path $PackageDir "Modules\UI.ps1"
    if (Test-Path -LiteralPath $UIModulePath) {
        . $UIModulePath
    }

    $EventsModulePath = Join-Path $PackageDir "Modules\Events-handlers.ps1"
    if (Test-Path -LiteralPath $EventsModulePath) {
        . $EventsModulePath
    }

    # ---------- Initial state ----------
    $cbTray.Enabled = $false
    $tbLogCustom.Enabled = $false
    $tbCustomKey.Enabled = $false 

    # ---------- Strategy B: Deferred Initialization to avoid UI startup lag ----------
    $form.add_Shown({
            # Apply previous saved config to UI controls (Operating Mode, logging, etc.)
            try {
                Apply-UIFromConfigIfPresent
            }
            catch {}

            # Auto-read current setup on launch
            try {
                Show-CurrentConfiguration
            }
            catch {}

            # Initialise test group state after profiles are loaded
            if (Get-Command Update-TestGroupState -ErrorAction SilentlyContinue) {
                try { Update-TestGroupState } catch {}
            }
        })

    # Pre-initialize Theme active state from config before form render
    $global:ThemeActiveType = "Normal"
    if (-not $global:SamishScreenshotMode -and (Test-Path -LiteralPath $ConfigPath)) {
        try {
            $cfgBoot = (Get-Content -LiteralPath $ConfigPath -Raw) | ConvertFrom-Json
            if ($cfgBoot -and $cfgBoot.PSObject.Properties.Name -contains "Theme" -and $cfgBoot.Theme) {
                $global:ThemeActiveType = $cfgBoot.Theme
            }
        }
        catch {}
    }

    if ($global:ThemeActiveType -eq "Neon" -or $global:ThemeActiveType -eq "Custom") {
        # Initialize Neon colors globally as default fallbacks in case Theme-Extension fails or loading is delayed
        if ($null -eq $global:NeonBackground) { $global:NeonBackground = [System.Drawing.Color]::FromArgb(15, 15, 18) }
        if ($null -eq $global:NeonPurple) { $global:NeonPurple = [System.Drawing.Color]::FromArgb(153, 51, 255) }
        if ($null -eq $global:NeonPink) { $global:NeonPink = [System.Drawing.Color]::FromArgb(255, 0, 102) }
        if ($null -eq $global:NeonLime) { $global:NeonLime = [System.Drawing.Color]::FromArgb(179, 255, 0) }
        if ($null -eq $global:NeonCyan) { $global:NeonCyan = [System.Drawing.Color]::FromArgb(0, 245, 212) }
        if ($null -eq $global:NeonText) { $global:NeonText = [System.Drawing.Color]::FromArgb(255, 255, 255) }

        if (-not (Get-Command Set-BrandTheme -ErrorAction SilentlyContinue)) {
            $themeExt = Join-Path $PackageDir "Modules\Theme-Extension.ps1"
            if (Test-Path -LiteralPath $themeExt) {
                . $themeExt
            }
        }
        
        # Load correct color variables prior to drawing
        if ($global:ThemeActiveType -eq "Custom") {
            try { Load-CustomThemeColors } catch {}
        } else {
            try { Load-NeonThemeColors } catch {}
        }

        try { Set-BrandTheme -Form $form -IsCustom $true } catch {}
        # Sync the tab indicator after the theme is applied -- Set-BrandTheme calls Update-TabIndicator
        # internally but at that point the form geometry may not be finalised yet; calling it again
        # after ShowDialog's first paint pass ensures the indicator lands on the correct tab.
        if (Get-Command Update-TabIndicator -ErrorAction SilentlyContinue) {
            try { [void]$form.BeginInvoke([Action] { Update-TabIndicator }) } catch {}
        }
    }

    # Apply modern UX: Hand cursors on all buttons
    $modernHand = [System.Windows.Forms.Cursors]::Hand
    try {
        if (-not ("SamishCursorHelper" -as [type])) {
            # Already compiled in NativeMethods.ps1
        }
        $handle = [SamishCursorHelper]::LoadCursor([IntPtr]::Zero, 32649) # IDC_HAND
        if ($handle -ne [IntPtr]::Zero) {
            $modernHand = New-Object System.Windows.Forms.Cursor($handle)
        }
    }
    catch {}

    function Set-ButtonCursors([System.Windows.Forms.Control]$parent) {
        foreach ($ctrl in $parent.Controls) {
            if ($ctrl -is [System.Windows.Forms.Button]) {
                $ctrl.Cursor = $modernHand
            }
            if ($ctrl.HasChildren) {
                Set-ButtonCursors -parent $ctrl
            }
        }
    }
    Set-ButtonCursors -parent $form

    # Apply modern UX: Escape key to close
    $form.KeyPreview = $true
    $form.add_KeyDown({
            if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
                $form.Close()
            }
        })
    # ---- First-Run Wizard (before main form opens) ----
    if (-not $CliInstall -and -not $global:SamishScreenshotMode) {
        if (Get-Command Invoke-FirstRunWizardIfNeeded -ErrorAction SilentlyContinue) {
            try {
                $wizardResult = Invoke-FirstRunWizardIfNeeded -ConfigPath $ConfigPath -PackageDir $PackageDir
                if ($wizardResult) {
                    Write-SamishSetupTrace -Message "First-run wizard completed. UI_Mode=$($wizardResult.UI_Mode)" -Level "INFO"
                    $global:IsWizardJustCompleted = $true
                    if ($wizardResult.UI_Mode -and (Get-Command Set-UiModeVisibility -ErrorAction SilentlyContinue)) {
                        try {
                            $script:chkUiMode.Checked = ($wizardResult.UI_Mode -eq "Full")
                            Set-UiModeVisibility -Mode $wizardResult.UI_Mode
                        }
                        catch {
                            Write-SamishSetupTrace -Message "Failed to apply UI mode visually: $($_.Exception.Message)" -Level "WARN"
                        }
                    }
                }
            }
            catch {
                Write-SamishSetupTrace -Message "First-run wizard error (non-fatal): $($_.Exception.Message)" -Level "WARN"
            }
        }
    }

    if (-not $global:SamishSkipShowDialog) {
        [void]$form.ShowDialog()
    }
}
finally {
    Complete-SamishSetupUi -Form $form
}
return
