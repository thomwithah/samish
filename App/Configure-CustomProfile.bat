@echo off
title SAMISH - Configure Custom Profile
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Configure-CustomProfile.ps1"
pause
