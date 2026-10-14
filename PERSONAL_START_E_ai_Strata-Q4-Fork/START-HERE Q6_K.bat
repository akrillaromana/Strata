@echo off
setlocal EnableExtensions
cd /d "%~dp0.."
title Strata Unsloth Q6_K
where pwsh.exe >nul 2>nul || (echo PowerShell 7 pwsh.exe not found.& pause & exit /b 1)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\PERSONAL_START_E_ai_Strata-Q4-Fork\START-Q6-RAM.ps1" %*
set "code=%errorlevel%"
if not "%code%"=="0" (echo.& echo Q6 START FAILED& pause)
exit /b %code%
