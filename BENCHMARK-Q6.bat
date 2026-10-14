@echo off
setlocal
cd /d "%~dp0"
title Strata - BENCHMARK-Q6
where pwsh.exe >nul 2>nul || (echo PowerShell 7 pwsh.exe not found.& pause & exit /b 1)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0BENCHMARK-MODEL.ps1" -Runs 3 %*
set "code=%errorlevel%"
if not "%code%"=="0" (echo.& echo Q6 BENCHMARK FAILED WITH CODE %code%.& pause)
exit /b %code%
