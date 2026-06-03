# ==========================================
# SAMISH (Streaming Audio Mixer Interface Sleep Helper) - Setup UI (PS 5.1 compatible)
# Created by thomwithah
# Version: 1.3.0
# ==========================================
# Place this Setup.ps1 in the same folder as:
#   - SAMISH.ps1
#   - SAMISH-HiddenTask.xml
#   - SAMISH-InteractiveTask.xml
# ==========================================

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

#region Native Methods
$NativeMethodsPath = $PSScriptRoot
if (-not $NativeMethodsPath -and $PSCommandPath) { $NativeMethodsPath = Split-Path -Parent $PSCommandPath }
if (-not $NativeMethodsPath) { $NativeMethodsPath = [System.AppDomain]::CurrentDomain.BaseDirectory }
$NativeMethodsPath = Join-Path $NativeMethodsPath "App\Modules\NativeMethods.ps1"
if (Test-Path -LiteralPath $NativeMethodsPath) {
    . $NativeMethodsPath
}
#endregion

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

# Temporarily bypass execution policy for the current process to ensure dot-sourced modules can load (crucial for PS2EXE compiled EXEs)
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue

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
        $psi.Arguments = "-ExecutionPolicy Bypass -NoProfile -File `"$currentFile`""
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
    } catch { }
    exit
}
Ensure-AdminAtStartup

$script:SetupExecutablePath = $PSCommandPath
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
        Add-Content -LiteralPath $path -Value $line
    }
    catch { }
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
$ProductVersion = "v1.3.0"
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

# ---------- Core helpers ----------

# ----- File system / install folder -----
function Ensure-InstallFolder {
    if (-not (Test-Path -LiteralPath $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }
}

function Get-UnknownPowerPlanPromptStatus {
    param([string]$PromptId)
    return @{ StatusMessage = "Unknown power plan prompt request: $PromptId" }
}

# ----- Config read helpers -----
function Get-ConfigEnableLogging {
    try {
        if (Test-Path -LiteralPath $ConfigPath) {
            $raw = Get-Content -LiteralPath $ConfigPath -Raw
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $cfg = $raw | ConvertFrom-Json
                if ($null -ne $cfg.EnableLogging) { return [bool]$cfg.EnableLogging }
            }
        }
    }
    catch {}
    return $false
}

# Windows Event Log Helper
function Register-SamishEventSource {
    try {
        if (-not (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\SAMISH")) {
            [System.Diagnostics.EventLog]::CreateEventSource("SAMISH", "Application")
            Write-SetupLog "Registered SAMISH as a Windows Event Log source."
        }
    }
    catch {
        Write-SetupLog "WARNING: Failed to register SAMISH as an Event Log source: $($_.Exception.Message)"
    }
}

# Logging helpers
function Rotate-LogFileIfNeeded {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        if (-not (Test-Path -LiteralPath $Path)) { return }

        $fileItem = Get-Item -LiteralPath $Path
        # 5MB = 5 * 1024 * 1024 = 5242880 bytes
        if ($fileItem.Length -le 5242880) { return }

        $dir = Split-Path -Parent $Path
        $name = Split-Path -Leaf $Path
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($name)
        $ext = [System.IO.Path]::GetExtension($name)

        $rotatedPath = $null
        for ($i = 1; $i -le 100; $i++) {
            $testName = "$baseName.$i$ext"
            $testPath = Join-Path $dir $testName
            if (-not (Test-Path -LiteralPath $testPath)) {
                $rotatedPath = $testPath
                break
            }
        }

        if (-not $rotatedPath) {
            $rotatedPath = Join-Path $dir "$baseName.100$ext"
            if (Test-Path -LiteralPath $rotatedPath) {
                Remove-Item -LiteralPath $rotatedPath -Force -ErrorAction SilentlyContinue
            }
        }

        if ($rotatedPath) {
            [System.IO.File]::Move($Path, $rotatedPath)
        }
    }
    catch {
        # Fail silently
    }
}

function Write-SetupLog {
    param([string]$text)

    $enabled = $false
    try {
        if ($script:cbLogging -and $script:cbLogging.Checked) { $enabled = $true }
        else { $enabled = (Get-ConfigEnableLogging) }
    }
    catch {}

    if (-not $enabled) { return }

    try {
        Rotate-LogFileIfNeeded -Path $StandardLogFile
        Add-Content -Path $StandardLogFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $text"
    }
    catch {}
}

function Write-SetupLogBlock {
    param([string]$textBlock)

    $enabled = $false
    try {
        if ($script:cbLogging -and $script:cbLogging.Checked) {
            $enabled = $true
        }
        else {
            $enabled = (Get-ConfigEnableLogging)
        }
    }
    catch {}

    if (-not $enabled) { return }

    try {
        Rotate-LogFileIfNeeded -Path $StandardLogFile
        Add-Content -Path $StandardLogFile -Value (
            "`r`n==== " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " ====`r`n" +
            $textBlock + "`r`n"
        )
    }
    catch {}
}

# ----- Dialog helpers (DRY) -----
function Show-InfoDialog {
    param(
        [string]$Message,
        [string]$Title = "Information"
    )

    try {
        [System.Windows.Forms.MessageBox]::Show(
            $Message,
            $Title,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    catch {}
}

function Show-WarningDialog {
    param(
        [string]$Message,
        [string]$Title = "Warning"
    )

    try {
        [System.Windows.Forms.MessageBox]::Show(
            $Message,
            $Title,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
    }
    catch {}
}

function Show-ErrorDialog {
    param(
        [string]$Message,
        [string]$Title = "Error"
    )

    try {
        [System.Windows.Forms.MessageBox]::Show(
            $Message,
            $Title,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    catch {}
}

function Show-YesNoDialog {
    param(
        [string]$Message,
        [string]$Title,
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Question
    )

    try {
        return [System.Windows.Forms.MessageBox]::Show(
            $Message,
            $Title,
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            $Icon
        )
    }
    catch {
        return [System.Windows.Forms.DialogResult]::No
    }
}

# ----- Tools helpers (DRY) -----
function Get-VerifiedPreferredLogPathOrShowMessageBox {
    try {
        $path = Get-PreferredSamishLogPath

        if ($path -and (Test-Path -LiteralPath $path)) {
            return $path
        }

        Show-InfoDialog `
            -Title "Log Not Found" `
            -Message "No SAMISH log files were found.`r`n`r`nEnable logging and run SAMISH, then try again."

        return $null
    }
    catch {
        Show-ErrorDialog `
            -Title "Error" `
            -Message ("Failed to locate log:`r`n" + $_.Exception.Message)

        return $null
    }
}

function Format-CleanResetStatusMessage {
    param(
        [int]$StoppedCount,
        [bool]$TrayRestarted
    )

    if ($TrayRestarted) {
        if ($StoppedCount -eq 0) {
            return "SAMISH was not running.`r`nTray instance started."
        }
        elseif ($StoppedCount -eq 1) {
            return "Clean reset complete.`r`n1 instance restarted."
        }
        else {
            return "Clean reset complete.`r`n$StoppedCount instances restarted."
        }
    }
    else {
        if ($StoppedCount -eq 0) {
            return "No running SAMISH instances were found.`r`nSystem is already clean."
        }
        elseif ($StoppedCount -eq 1) {
            return "Clean reset complete.`r`n1 running instance was stopped."
        }
        else {
            return "Clean reset complete.`r`n$StoppedCount running instances were stopped."
        }
    }
}

function Get-NoPowerPlanChangesText {
    return "No power plan changes were made."
}

function Get-NoPowerPlanChangesStatus {
    return @{ StatusMessage = (Get-NoPowerPlanChangesText) }
}

# ----- Power plan opt-in helpers (DRY) -----
function Get-PowerPlanClassicCompatOptInPromptText {
    return @"
You are currently using Graceful mode. Graceful mode does not require Classic power plan compatibility.

Classic mode works best when Screen Off occurs at least 60 seconds before Sleep/Hibernate.

Would you like to make your current power plan Classic-compatible now anyway?

A backup will be created before any changes are applied.
"@
}

function Ask-PowerPlanClassicCompatOptIn {
    $res = [System.Windows.Forms.MessageBox]::Show(
        (Get-PowerPlanClassicCompatOptInPromptText),
        "Power Plan Compatibility",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )

    return ($res -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Invoke-GracefulClassicCompatOptInFlow {
    param(
        $InitialResult,
        [bool]$AutoMode
    )

    if (-not $InitialResult -or -not $InitialResult.NeedsPrompt) {
        return $InitialResult
    }

    if (-not (Ask-PowerPlanClassicCompatOptIn)) {
        return (Get-NoPowerPlanChangesStatus)
    }

    $result = Handle-PowerPlanPromptIfNeeded -result $InitialResult -AutoMode:$AutoMode
    if ($result -and $result.NeedsPrompt) {
        $result = Handle-PowerPlanPromptIfNeeded -result $result -AutoMode:$AutoMode
    }

    return $result
}

function Get-ActiveInstallModeForReset {
    # Prefer installed task reality; fall back to config intent; final fallback: UI selection.
    try {
        if (Task-Exists -TaskNameWithSlash $TaskInteractive) { return "Interactive" }
        if (Task-Exists -TaskNameWithSlash $TaskHidden) { return "Hidden" }
    }
    catch {}

    try {
        if (Test-Path -LiteralPath $ConfigPath) {
            $cfg = (Get-Content -LiteralPath $ConfigPath -Raw) | ConvertFrom-Json
            if ($cfg) {
                $tray = $false
                $hot = $false
                if ($cfg.PSObject.Properties.Name -contains "EnableTrayIcon") { $tray = [bool]$cfg.EnableTrayIcon }
                if ($cfg.PSObject.Properties.Name -contains "EnableHotkey") { $hot = [bool]$cfg.EnableHotkey }
                if ($tray -or $hot) { return "Interactive" }
                return "Hidden"
            }
        }
    }
    catch {}

    # Final fallback: current UI selection (best effort)
    if ($rbInteractive.Checked) { return "Interactive" }
    return "Hidden"
}

function Start-SamishInMode {
    param(
        [ValidateSet("Hidden", "Interactive")]
        [string]$Mode
    )

    # Task-only start. Do not start engine directly.
    try {
        if ($Mode -eq "Interactive") {
            if (Task-Exists -TaskNameWithSlash $TaskInteractive) {
                return Run-Schtasks ("/Run /TN `"$TaskInteractive`"")
            }
            return @{ ExitCode = 2; StdOut = ""; StdErr = "Interactive task is not installed." }
        }

        if ($Mode -eq "Hidden") {
            if (Task-Exists -TaskNameWithSlash $TaskHidden) {
                return Run-Schtasks ("/Run /TN `"$TaskHidden`"")
            }
            return @{ ExitCode = 2; StdOut = ""; StdErr = "Hidden task is not installed." }
        }
    }
    catch {
        return @{ ExitCode = 1; StdOut = ""; StdErr = ("Failed to start via scheduled task: " + $_.Exception.Message) }
    }

}

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
    if ($null -ne $global:ThemeNeonActive) {
        $themeVal = if ($global:ThemeNeonActive) { "Neon" } else { "Normal" }
    } elseif ($existing -and $existing.PSObject.Properties.Name -contains "Theme" -and $existing.Theme) {
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
        if ($existing.PSObject.Properties.Name -contains "GameModeList")    { $gameModeList = @($existing.GameModeList) }
        if ($existing.PSObject.Properties.Name -contains "WizardCompleted") { $wizardCompleted = [bool]$existing.WizardCompleted }
        if ($existing.PSObject.Properties.Name -contains "UI_Mode")         { $uiMode = [string]$existing.UI_Mode }
        if ($existing.PSObject.Properties.Name -contains "PreferredPlaybackDeviceGuid") { $prefPlaybackGuid = [string]$existing.PreferredPlaybackDeviceGuid }
        if ($existing.PSObject.Properties.Name -contains "PreferredPlaybackDeviceName") { $prefPlaybackName = [string]$existing.PreferredPlaybackDeviceName }
        if ($existing.PSObject.Properties.Name -contains "PreferredCommDeviceGuid")     { $prefCommGuid = [string]$existing.PreferredCommDeviceGuid }
        if ($existing.PSObject.Properties.Name -contains "PreferredCommDeviceName")     { $prefCommName = [string]$existing.PreferredCommDeviceName }
    }

    $cfg = [ordered]@{
        EnableLogging          = $EnableLogging
        LogEverySeconds        = $LogEverySeconds
        EnableTrayIcon         = $EnableTrayIcon
        EnableHotkey           = $EnableHotkey
        HotkeyMode             = $HotkeyMode
        CustomHotkeyVirtualKey = $CustomHotkeyVirtualKey
        OperatingMode          = $OperatingMode
        SetupPath              = $SetupPath
        LogFile                = $StandardLogFileTemplate
        ActiveProfileId        = $ActiveProfileId
        ProfilesEnabled        = @($ProfilesEnabled)
        MonitoredApps          = $monitoredApps
        Theme                  = $themeVal
        EnableAutoRecovery     = $EnableAutoRecovery
        GameModeEnabled        = $gameModeEnabled
        GameModeList           = $gameModeList
        WizardCompleted        = $wizardCompleted
        UI_Mode                = $uiMode
        PreferredPlaybackDeviceGuid = $prefPlaybackGuid
        PreferredPlaybackDeviceName = $prefPlaybackName
        PreferredCommDeviceGuid     = $prefCommGuid
        PreferredCommDeviceName     = $prefCommName
    }

    $json = $cfg | ConvertTo-Json -Depth 6
    if (Get-Command Save-ContentAtomic -ErrorAction SilentlyContinue) {
        Save-ContentAtomic -Path $ConfigPath -Content $json
    } else {
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
# ----- Live Log (in Status box) helpers -----
$script:IsLiveLogMode = $false
$script:SavedStatusText = ""
$script:SavedStatusBack = $null
$script:SavedStatusFore = $null
$script:SavedStatusFont = $null
$script:LiveLogTimer = $null
$script:LiveLogPosition = 0

function Enter-LiveLogMode {
    $path = Get-VerifiedPreferredLogPathOrShowMessageBox
    if (-not $path) { return }

    $script:IsLiveLogMode = $true
    # Reset deferred status buffer for this live session
    $script:DeferredStatusUpdates = @()
    $script:DeferredStatusLatest = $null
    $script:SavedStatusText = $statusBox.Text
    $script:SavedStatusBack = $statusBox.BackColor
    $script:SavedStatusFore = $statusBox.ForeColor
    $script:SavedStatusFont = $statusBox.Font

    # Dark "live" theme
    $statusBox.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 35)
    $statusBox.ForeColor = [System.Drawing.Color]::Gainsboro
    if (-not $script:LiveLogFont) {
        $script:LiveLogFont = New-Object System.Drawing.Font("Consolas", 9)
        if ($script:MainFormGdiResources) {
            $script:MainFormGdiResources.Add($script:LiveLogFont)
        }
    }
    $statusBox.Font = $script:LiveLogFont

    $statusBox.Clear()
    $statusBox.AppendText("LIVE LOG (press Live Log again to exit)`r`n`r`n")

    # Start at end - show last chunk first (small tail)
    try {
        $fi = Get-Item -LiteralPath $path
        $len = [int64]$fi.Length
        $script:LiveLogPosition = [Math]::Max(0, $len - 8192)  # last ~8KB
    }
    catch {
        $script:LiveLogPosition = 0
    }

    # Timer to poll for new data
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 350
    $timer.Add_Tick({
            try {
                Append-LiveLogChunk -Path $path
            }
            catch { }
        })
    $script:LiveLogTimer = $timer
    $timer.Start()

    # Button text flip
    $btnLiveLog.Text = "Exit Live Log"
}

function Exit-LiveLogMode {
    $script:IsLiveLogMode = $false

    try {
        if ($script:LiveLogTimer) {
            $script:LiveLogTimer.Stop()
            $script:LiveLogTimer.Dispose()
            $script:LiveLogTimer = $null
        }
    }
    catch { }

    # Restore theme + text
    if ($script:SavedStatusBack) { $statusBox.BackColor = $script:SavedStatusBack }
    if ($script:SavedStatusFore) { $statusBox.ForeColor = $script:SavedStatusFore }
    if ($script:SavedStatusFont) { $statusBox.Font = $script:SavedStatusFont }

    # Restore content:
    # - Start with what was there before Live Log
    # - Then append any status updates that happened while Live Log was active
    if ($script:DeferredStatusUpdates -and $script:DeferredStatusUpdates.Count -gt 0) {

        $merged = $script:SavedStatusText

        if (-not [string]::IsNullOrWhiteSpace($merged)) {
            $merged += "`r`n`r`n"
        }

        $merged += "--- Updates while Live Log was active ---`r`n`r`n"

        # De-dupe adjacent identical updates (common when the same status is set twice)
        $out = New-Object System.Collections.Generic.List[string]
        $prev = $null
        foreach ($u in $script:DeferredStatusUpdates) {
            if ($null -ne $u -and $u -ne $prev) {
                $out.Add($u)
                $prev = $u
            }
        }

        $merged += ($out -join "`r`n`r`n")

        $statusBox.Text = $merged
    }
    else {
        $statusBox.Text = $script:SavedStatusText
    }

    $btnLiveLog.Text = "Live Log"
}

function Append-LiveLogChunk {
    param([string]$Path)

    if (-not $script:IsLiveLogMode) { return }
    if (-not (Test-Path -LiteralPath $Path)) { return }

    $fs = $null
    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        if ($script:LiveLogPosition -gt $fs.Length) { $script:LiveLogPosition = 0 } # log rotated/truncated

        $fs.Seek($script:LiveLogPosition, [System.IO.SeekOrigin]::Begin) | Out-Null
        $sr = New-Object System.IO.StreamReader($fs)

        # Read to end
        $newText = $sr.ReadToEnd()
        $script:LiveLogPosition = $fs.Position

        if (-not [string]::IsNullOrEmpty($newText)) {
            $statusBox.AppendText($newText)

            # Hard cap to keep UI snappy (keep last ~200k chars)
            $maxChars = 200000
            if ($statusBox.TextLength -gt $maxChars) {
                $statusBox.Text = $statusBox.Text.Substring($statusBox.TextLength - $maxChars)
                $statusBox.SelectionStart = $statusBox.TextLength
                $statusBox.ScrollToCaret()
            }
        }
    }
    finally {
        if ($fs) { $fs.Dispose() }
    }
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

# ----- Startup Shortcut Automation -----
function Get-StartupFolder { [Environment]::GetFolderPath("Startup") }
function Get-StartupShortcutPath { Join-Path (Get-StartupFolder) "SAMISH.lnk" }

function Create-StartupShortcut {
    param([string]$ScriptPath)

    $shortcutPath = Get-StartupShortcutPath
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)

    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""
    $shortcut.WorkingDirectory = Split-Path $ScriptPath
    $shortcut.IconLocation = "powershell.exe,0"
    $shortcut.Save()
}

function Remove-StartupShortcut {
    $shortcutPath = Get-StartupShortcutPath
    if (Test-Path -LiteralPath $shortcutPath) {
        Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
    }
}

# ----- schtasks wrappers -----
function Run-Schtasks {
    param([string]$Arguments)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "schtasks.exe"
    $psi.Arguments = $Arguments
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    return @{ ExitCode = $p.ExitCode; StdOut = $stdout; StdErr = $stderr }
}

function Install-TaskFromXml {
    param([string]$TaskNameNoSlash, [string]$XmlPath)
    if (-not (Test-Path -LiteralPath $XmlPath)) { throw "XML missing: $XmlPath" }
    return Run-Schtasks ("/Create /TN `"$TaskNameNoSlash`" /XML `"$XmlPath`" /F")
}

function Delete-Task {
    param([string]$TaskNameWithSlash)
    return Run-Schtasks ("/Delete /TN `"$TaskNameWithSlash`" /F")
}

function Task-Exists {
    param([string]$TaskNameWithSlash)
    return ((Run-Schtasks ("/Query /TN `"$TaskNameWithSlash`"")).ExitCode -eq 0)
}
function Test-SamishInstalled {
    try {
        if (Task-Exists -TaskNameWithSlash $TaskInteractive) { return $true }
        if (Task-Exists -TaskNameWithSlash $TaskHidden) { return $true }
    }
    catch {}
    return $false
}

function Stop-SamishTaskIfRunning {
    param(
        [ValidateSet("Hidden", "Interactive")]
        [string]$Mode
    )
    try {
        if ($Mode -eq "Interactive" -and (Task-Exists -TaskNameWithSlash $TaskInteractive)) {
            $null = Run-Schtasks ("/End /TN `"$TaskInteractive`"")
        }
        elseif ($Mode -eq "Hidden" -and (Task-Exists -TaskNameWithSlash $TaskHidden)) {
            $null = Run-Schtasks ("/End /TN `"$TaskHidden`"")
        }
    }
    catch {}
}

# ----- Helper process control -----
function Stop-RunningHelperInstances {
    param(
        [int]$WaitTimeoutMs = 2500
    )

    $selfPid = $PID
    $enginePath = $InstalledEnginePath
    $enginePathEsc = if ($enginePath) { [Regex]::Escape($enginePath) } else { "" }

    # Find candidate processes
    $procs = Get-CimInstance Win32_Process | Where-Object {
        ($_.Name -eq "powershell.exe" -or $_.Name -eq "pwsh.exe") -and
        $_.ProcessId -ne $selfPid -and
        $_.CommandLine -and (
            # Full path run
            ($enginePathEsc -and $_.CommandLine -match $enginePathEsc) -or

            # Task run (relative file name)
            ($_.CommandLine -match '(?i)(-File\s+)"?SAMISH\.ps1"?(?:\s|$)') -or

            # Generic roaming path hint
            ($_.CommandLine -match '(?i)\\AppData\\Roaming\\SAMISH\\SAMISH\.ps1')
        )
    }

    $pids = @()
    foreach ($p in $procs) {
        try {
            $pids += [int]$p.ProcessId
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        }
        catch { }
    }

    # Wait (briefly) for termination so Task Scheduler (/Run) can actually restart under IgnoreNew.
    if ($pids.Count -gt 0) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while ($sw.ElapsedMilliseconds -lt $WaitTimeoutMs) {
            $still = @()
            foreach ($id in $pids) {
                if (Get-Process -Id $id -ErrorAction SilentlyContinue) { $still += $id }
            }
            if ($still.Count -eq 0) { break }
            Start-Sleep -Milliseconds 100
        }
    }

    return $pids.Count
}

# ----- Hotkey parsing -----
$VkMap = @{
    "ScrollLock" = 0x91
    "PauseBreak" = 0x13
    "F12"        = 0x7B
}

function Parse-CustomHotkeyToVk {
    param([string]$InputText)

    if ([string]::IsNullOrWhiteSpace($InputText)) { throw "Custom hotkey is blank." }
    $u = $InputText.Trim().ToUpperInvariant()

    if ($VkMap.ContainsKey($u)) { return [int]$VkMap[$u] }
    if ($u -match '^F([1-9]|1[0-9]|2[0-4])$') { return 0x70 + ([int]$matches[1] - 1) }
    if ($u -match '^[A-Z]$') { return [int][byte][char]$u }
    if ($u -match '^[0-9]$') { return 0x30 + [int]$u }
    if ($u -match '^0X[0-9A-F]+$') { return [Convert]::ToInt32($u, 16) }

    throw "Unsupported custom hotkey. Examples: F8, K, 7, or 0x91."
}

# ----- Log interval parsing -----
function Parse-LogEverySecondsOrThrow {
    param(
        [string]$RawText,
        [string]$ContextLabel = "Log interval"
    )

    $t = ($RawText | Out-String).Trim()

    if ([string]::IsNullOrWhiteSpace($t)) {
        throw "$ContextLabel must not be blank."
    }

    if ($t -notmatch '^\d+$') {
        throw "$ContextLabel must be a whole number of seconds."
    }

    $n = 0
    if (-not [int]::TryParse($t, [ref]$n)) {
        throw "$ContextLabel is out of range. Please enter a value between 0 and 2147483647 seconds."
    }

    return $n
}

function Format-SecondsToFriendlyCompact {
    param([int]$Seconds)

    if ($Seconds -lt 0) { return "Unknown" }
    if ($Seconds -eq 0) { return "Verbose (every loop)" }

    $start = Get-Date
    $end = $start.AddSeconds($Seconds)

    $years = 0
    $cursor = $start
    while ($cursor.AddYears(1) -le $end) {
        $cursor = $cursor.AddYears(1)
        $years++
    }

    $remaining = $end - $cursor

    $days = [Math]::Floor($remaining.TotalDays)
    $cursor = $cursor.AddDays($days)
    $remaining = $end - $cursor

    $hours = [Math]::Floor($remaining.TotalHours)
    $cursor = $cursor.AddHours($hours)
    $remaining = $end - $cursor

    $minutes = [Math]::Floor($remaining.TotalMinutes)
    $cursor = $cursor.AddMinutes($minutes)
    $remaining = $end - $cursor

    $secs = [Math]::Floor($remaining.TotalSeconds)

    $parts = @()
    if ($years -gt 0) { $parts += ($(if ($years -eq 1) { "1 year" } else { "$years years" })) }
    if ($days -gt 0) { $parts += ($(if ($days -eq 1) { "1 day" } else { "$days days" })) }
    if ($hours -gt 0) { $parts += ($(if ($hours -eq 1) { "1 hour" } else { "$hours hours" })) }
    if ($minutes -gt 0) { $parts += ($(if ($minutes -eq 1) { "1 minute" } else { "$minutes minutes" })) }
    if ($secs -gt 0) { $parts += ($(if ($secs -eq 1) { "1 second" } else { "$secs seconds" })) }

    if ($parts.Count -eq 0) { return "0 seconds" }
    return ($parts -join " ")
}



# ---------- Diagnostics Header ----------
function Get-TaskQueryInfo {
    param([string]$TaskNameNoSlash)

    $r = Run-Schtasks ("/Query /TN `"$TaskNameNoSlash`"")
    if ($r.ExitCode -ne 0) { return @{ Exists = $false; Status = "Missing" } }

    $status = "Unknown"
    $m = [Regex]::Match($r.StdOut, "(?im)^\s*Status:\s*(.+?)\s*$")
    if ($m.Success) { $status = $m.Groups[1].Value.Trim() }

    return @{ Exists = $true; Status = $status }
}

function Get-SamishProcessInfo {
    $procs = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -and (
            $_.CommandLine -match "SAMISH\\.ps1" -or
            ($InstalledEnginePath -and ($_.CommandLine -like "*$InstalledEnginePath*"))
        )
    }
    if (-not $procs) { return @{ Running = $false; Count = 0; Pids = @() } }
    $pids = @($procs | ForEach-Object { $_.ProcessId })
    return @{ Running = $true; Count = $pids.Count; Pids = $pids }
}
function Build-DiagnosticsHeader {
    param(
        [string]$Context = "",
        [string]$Mode = "",
        [bool]$IncludePowerPlan = $true
    )

    $shortcutPath = Get-StartupShortcutPath
    $shortcutPresent = Test-Path -LiteralPath $shortcutPath

    $hiddenTask = Get-TaskQueryInfo -TaskNameNoSlash $TaskHiddenNoSlash
    $interactiveTask = Get-TaskQueryInfo -TaskNameNoSlash $TaskInteractiveNoSlash
    $proc = Get-SamishProcessInfo

    $powerLine = ""
    if ($IncludePowerPlan) {
        $scheme = $null
        try { $scheme = Get-ActiveSchemeGuid } catch { $scheme = $null }
        $powerLine = if ($scheme) { Get-PowerPlanDiagnosticsText -SchemeGuid $scheme } else { "" }
    }

    # Load config
    $cfg = $null
    if (Test-Path -LiteralPath $ConfigPath) {
        try { $cfg = (Get-Content -LiteralPath $ConfigPath -Raw) | ConvertFrom-Json } catch {}
    }

    $installed = ($hiddenTask.Exists -or $interactiveTask.Exists)

    # Infer install mode (prefer actual task reality, then config intent)
    if ([string]::IsNullOrWhiteSpace($Mode)) {
        try {
            if ($interactiveTask.Exists) { $Mode = "Interactive" }
            elseif ($hiddenTask.Exists) { $Mode = "Hidden" }
        }
        catch {}
    }

    if ([string]::IsNullOrWhiteSpace($Mode) -and $cfg) {
        try {
            $tray = $false
            $hot = $false
            if ($cfg.PSObject.Properties.Name -contains "EnableTrayIcon") { $tray = [bool]$cfg.EnableTrayIcon }
            if ($cfg.PSObject.Properties.Name -contains "EnableHotkey") { $hot = [bool]$cfg.EnableHotkey }

            if ($tray -or $hot) { $Mode = "Interactive" }
            else { $Mode = "Hidden" }
        }
        catch {}
    }

    # Operating mode only if installed
    $operatingMode = $null
    if ($installed -and $cfg -and ($cfg.PSObject.Properties.Name -contains "OperatingMode")) {
        $operatingMode = $cfg.OperatingMode
    }

    # Status line
    $statusLine = "Status: Not installed"

    if ($installed -and $proc.Running) {
        $statusLine = "Status: SAMISH is running correctly"
    }
    elseif ($installed -and -not $proc.Running) {
        $statusLine = "Status: Installed but not currently running"
    }
    elseif (-not $installed -and $proc.Running) {
        $statusLine = "Status: Not installed (leftover SAMISH instance is running)"
    }

    $lines = @()
    $lines += $statusLine
    $lines += "=== SAMISH Diagnostics ==="

    if ($Context) { $lines += "Context: $Context" }
    $lines += "Engine: $InstalledEnginePath"

    if (-not [string]::IsNullOrWhiteSpace($Mode)) {
        $lines += "Install Mode: $Mode"
    }

    if ($installed -and $operatingMode) {
        $lines += "Operating Mode: $operatingMode"
    }

    # Logging (friendly)
    if ($cfg) {
        if ($cfg.PSObject.Properties.Name -contains "EnableLogging" -and [bool]$cfg.EnableLogging) {
            $sec = -1
            try { $sec = [int]$cfg.LogEverySeconds } catch { $sec = -1 }
            $lines += "Logging: Enabled (" + (Format-SecondsToFriendlyCompact $sec) + ")"
        }
        else {
            $lines += "Logging: Disabled"
        }
    }

    # Hotkey
    if ($cfg -and ($cfg.PSObject.Properties.Name -contains "EnableHotkey") -and [bool]$cfg.EnableHotkey) {
        if ($cfg.HotkeyMode -eq "Custom") {
            $vk = $cfg.CustomHotkeyVirtualKey
            $friendly = [System.Windows.Forms.Keys]$vk
            $lines += "Hotkey: Custom ($friendly)"
        }
        else {
            $lines += "Hotkey: " + $cfg.HotkeyMode
        }
    }
    else {
        $lines += "Hotkey: Disabled"
    }

    # Tray
    if ($cfg -and ($cfg.PSObject.Properties.Name -contains "EnableTrayIcon")) {
        $lines += "Tray Icon: " + ($(if ([bool]$cfg.EnableTrayIcon) { "Enabled" } else { "Disabled" }))
    }

    # Startup shortcut (Scheduled-task-only for Interactive)
    if (-not $installed) {
        $lines += "Startup shortcut: Not Installed"
    }
    elseif ($Mode -eq "Hidden") {
        $lines += "Startup shortcut: Not required (Hidden mode)"
    }
    elseif ($Mode -eq "Interactive") {
        if ($shortcutPresent) {
            $lines += "Startup shortcut: Present (unexpected) - should be removed ($shortcutPath)"
        }
        else {
            $lines += "Startup shortcut: Not required (Interactive uses Scheduled Task)"
        }
    }
    else {
        if ($shortcutPresent) {
            $lines += "Startup shortcut: Present (unexpected) - should be removed ($shortcutPath)"
        }
        else {
            $lines += "Startup shortcut: Not required"
        }
    }


    # Tasks -- NO "Missing"
    if (-not $installed) {
        $lines += "Task (Hidden): Not Installed"
        $lines += "Task (Interactive): Not Installed"
    }
    elseif ($Mode -eq "Interactive") {
        $lines += "Task (Interactive): " + ($(if ($interactiveTask.Exists) { "Present" } else { "Not Created" }))
        $lines += "Task (Hidden): Not Used"
    }
    elseif ($Mode -eq "Hidden") {
        $lines += "Task (Hidden): " + ($(if ($hiddenTask.Exists) { "Present" } else { "Not Created" }))
        $lines += "Task (Interactive): Not Used"
    }
    else {
        # Mode unknown: show both task states
        $lines += "Task (Interactive): " + ($(if ($interactiveTask.Exists) { "Present" } else { "Not Created" }))
        $lines += "Task (Hidden): " + ($(if ($hiddenTask.Exists) { "Present" } else { "Not Created" }))
    }

    # Process
    if (-not $installed) {
        $lines += "Process running: " + ($(if ($proc.Running) { "Yes (manual or leftover instance)" } else { "No" }))
    }
    else {
        $lines += "Process running: " + ($(if ($proc.Running) { "Yes" } else { "No" })) +
        ($(if ($proc.Running) { " | Instances: $($proc.Count) | PID(s): $($proc.Pids -join ',')" } else { "" }))
    }

    # Power plan block (only if it has content)
    if (-not [string]::IsNullOrWhiteSpace($powerLine)) {
        $lines += $powerLine
    }

    $lines += "========================="

    return ($lines -join "`r`n")
}

function Show-DiagnosticsHeader {
    param(
        [string]$Context = "",
        [string]$Mode = "",
        [bool]$TrayRequested = $false,
        [bool]$HotkeyRequested = $false,
        [bool]$LoggingRequested = $false,

        # Default behavior: include power plan, but auto-disable if it already appears in the existing status text
        [bool]$IncludePowerPlan = $true
    )

    
    # Capture existing text FIRST (important for Install/Update and other flows that set status before calling this)
    $existing = $statusBox.Text

    # Auto-dedup: if the existing text already contains a "Power Plan:" block, don't repeat it in diagnostics header
    $effectiveIncludePowerPlan = $IncludePowerPlan
    try {
        if ($effectiveIncludePowerPlan -and -not [string]::IsNullOrWhiteSpace($existing)) {

            # Case 1: Existing text already includes the Power Plan block (exact or implied)
            if ($existing -match '(?m)^\s*Power Plan:\s*$' -or
                ($existing -match '(?m)^\s*Screen Off\s*=' -and $existing -match '(?m)^\s*Hibernate\s*=')) {
                $effectiveIncludePowerPlan = $false
            }

            # Case 2: Existing text already contains a power-plan warning/action (even without the block)
            if ($effectiveIncludePowerPlan -and
                $existing -match '(?i)\bpower plan\b' -and
                $existing -match '(?i)check\s*/\s*restore') {
                $effectiveIncludePowerPlan = $false
            }
        }
    }
    catch { }

    $header = Build-DiagnosticsHeader `
        -Context $Context `
        -Mode $Mode `
        -IncludePowerPlan:$effectiveIncludePowerPlan


    if ([string]::IsNullOrWhiteSpace($existing)) {
        Set-StatusText($header)
    }
    else {
        Set-StatusText($header + "`r`n`r`n--- Recent Activity ---`r`n" + $existing)
    }

    Write-SetupLogBlock $statusBox.Text
}

# ----- UI read-only status helpers -----
function Show-CurrentConfiguration {
    try {
        $lines = @()

        $warn = Get-PowerPlanReadOnlyWarnings
        if ($warn -and $warn.Count -gt 0) { $lines += $warn }

        $lines += "Loaded current configuration..."
        $lines += ""

        $configExists = Test-Path -LiteralPath $ConfigPath

        if ($configExists) {
            $hiddenTaskExists = Task-Exists -TaskNameWithSlash $TaskHidden
            $interactiveTaskExists = Task-Exists -TaskNameWithSlash $TaskInteractive

            if (-not ($hiddenTaskExists -or $interactiveTaskExists)) {
                $lines += "=== SAVED CONFIGURATION (from previous installation) ==="
            }
            else {
                $lines += "=== CURRENT CONFIGURATION ==="
            }
        }
        else {
            $lines += "=== CURRENT CONFIGURATION ==="
        }

        if ($configExists) {
            $cfg = (Get-Content -LiteralPath $ConfigPath -Raw) | ConvertFrom-Json

            $loggingEnabled = [bool]$cfg.EnableLogging
            $lines += "Logging: " + ($(if ($loggingEnabled) { "Enabled" } else { "Disabled" }))

            if ($loggingEnabled) {
                $sec = -1
                try { $sec = [int]$cfg.LogEverySeconds } catch { $sec = -1 }
                $lines += "Log Interval: " + (Format-SecondsToFriendlyCompact $sec)
            }

            $lines += "Tray Icon: " + ($(if ($cfg.EnableTrayIcon) { "Enabled" } else { "Disabled" }))

            if ($cfg.EnableHotkey) {
                if ($cfg.HotkeyMode -eq "Custom") {
                    $vk = $cfg.CustomHotkeyVirtualKey
                    $friendly = [System.Windows.Forms.Keys]$vk
                    $lines += "Hotkey: Custom ($friendly)"
                }
                else {
                    $lines += "Hotkey: " + $cfg.HotkeyMode
                }
            }
            else {
                $lines += "Hotkey: Disabled"
            }
        }
        else {
            $lines += "Config not found (not installed yet)."
        }

        $includePowerPlan = $true

        try {
            if ($warn -and ($warn -contains "Power Plan:" -or (($warn -join "`n") -match '(?m)^\s*Power Plan:\s*$'))) {
                $includePowerPlan = $false
            }
        }
        catch { }

        $lines += ""
        $lines += (Build-DiagnosticsHeader -IncludePowerPlan:$includePowerPlan)

        Set-StatusText($lines -join "`r`n")
        Write-SetupLogBlock ($lines -join "`r`n")
    }
    catch {
        Set-StatusText("Failed to read configuration.`r`n$($_.Exception.Message)")
    }
}

# ----- Layout helpers -----
function Place-Below {
    param([System.Windows.Forms.Control]$Above, [System.Windows.Forms.Control]$Below, [int]$Gap = 10)
    $Below.Location = New-Object System.Drawing.Point($Below.Location.X, ($Above.Location.Y + $Above.Height + $Gap))
}



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

# Pre-initialize Neon theme state from config before form render
if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $cfgBoot = (Get-Content -LiteralPath $ConfigPath -Raw) | ConvertFrom-Json
        if ($cfgBoot -and $cfgBoot.PSObject.Properties.Name -contains "Theme") {
            $global:ThemeNeonActive = ($cfgBoot.Theme -eq "Neon")
        }
    } catch {}
}

if ($global:ThemeNeonActive) {
    # Initialize Neon colors globally as default fallbacks in case Theme-Extension fails or loading is delayed
    if ($null -eq $global:NeonBackground) { $global:NeonBackground = [System.Drawing.Color]::FromArgb(15, 15, 18) }
    if ($null -eq $global:NeonPurple)     { $global:NeonPurple     = [System.Drawing.Color]::FromArgb(153, 51, 255) }
    if ($null -eq $global:NeonPink)       { $global:NeonPink       = [System.Drawing.Color]::FromArgb(255, 0, 102) }
    if ($null -eq $global:NeonLime)       { $global:NeonLime       = [System.Drawing.Color]::FromArgb(179, 255, 0) }
    if ($null -eq $global:NeonCyan)       { $global:NeonCyan       = [System.Drawing.Color]::FromArgb(0, 245, 212) }
    if ($null -eq $global:NeonText)       { $global:NeonText       = [System.Drawing.Color]::FromArgb(255, 255, 255) }

    if (-not (Get-Command Set-BrandTheme -ErrorAction SilentlyContinue)) {
        $themeExt = Join-Path $PackageDir "Modules\Theme-Extension.ps1"
        if (Test-Path -LiteralPath $themeExt) {
            . $themeExt
        }
    }
    try { Set-BrandTheme -Form $form -IsCustom $true } catch {}
    # Sync the tab indicator after the theme is applied -- Set-BrandTheme calls Update-TabIndicator
    # internally but at that point the form geometry may not be finalised yet; calling it again
    # after ShowDialog's first paint pass ensures the indicator lands on the correct tab.
    if (Get-Command Update-TabIndicator -ErrorAction SilentlyContinue) {
        try { [void]$form.BeginInvoke([Action]{ Update-TabIndicator }) } catch {}
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
} catch {}

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
            }
        }
        catch {
            Write-SamishSetupTrace -Message "First-run wizard error (non-fatal): $($_.Exception.Message)" -Level "WARN"
        }
    }
}

[void]$form.ShowDialog()
}
finally {
    Complete-SamishSetupUi -Form $form
}
return
