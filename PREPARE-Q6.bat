@echo off
setlocal
cd /d "%~dp0"
title Strata - PREPARE-Q6
where pwsh.exe >nul 2>nul || (echo PowerShell 7 pwsh.exe not found.& pause & exit /b 1)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0START-Q6-RAM.ps1" -PreparePack -AllowBf16Conversion -PrepareOnly %*
set "code=%errorlevel%"
if not "%code%"=="0" (echo.& echo Q6 PREPARE FAILED WITH CODE %code%.& pause)
exit /b %code%
