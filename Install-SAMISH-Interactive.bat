@echo off
setlocal

echo Installing SAMISH (Interactive mode) via Setup.ps1 CLI...

REM Ensure admin privileges
net session >nul 2>&1
if %errorlevel% NEQ 0 (
  echo Requesting administrator privileges...
  powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
  exit /b
)

REM Move to script directory
cd /d "%~dp0"

REM Ensure Setup.ps1 exists
if not exist "%~dp0Setup.ps1" (
  echo ERROR: Setup.ps1 not found in this folder.
  echo Expected: Setup.ps1 next to this .bat file.
  pause
  exit /b 1
)

REM Run CLI install (Interactive + Tray + Hotkey; Graceful by default; no power plan changes)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup.ps1" ^
  -CliInstall ^
  -InstallMode Interactive ^
  -OperatingMode Graceful ^
  -EnableTrayIcon ^
  -EnableHotkey

echo.
echo Install complete (Interactive mode).
echo Note: Tray and Hotkey were enabled. Power plan was NOT changed by this installer.
pause

endlocal