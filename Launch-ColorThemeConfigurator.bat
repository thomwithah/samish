@echo off
title SAMISH Color Theme Configurator
echo Launching SAMISH Interactive Color Theme Configurator...
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0App\Modules\Configure-ColorTheme.ps1"
pause
