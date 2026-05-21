@echo off
setlocal

echo Uninstalling SAMISH...

net session >nul 2>&1
if %errorlevel% NEQ 0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

schtasks /Delete /TN "\SAMISH (Hidden)" /F >nul 2>&1
schtasks /Delete /TN "\SAMISH (Interactive)" /F >nul 2>&1

echo.
echo Uninstall complete.
echo If Task Scheduler is open, refresh it to see changes.

pause
endlocal