@echo off
setlocal
cd /d "%~dp0"
title Strata - TEST-Q6
where pwsh.exe >nul 2>nul || (echo PowerShell 7 pwsh.exe not found.& pause & exit /b 1)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0TEST-REQUESTS.ps1" -Requests 6 %*
set "code=%errorlevel%"
if not "%code%"=="0" (echo.& echo Q6 REQUEST TEST FAILED WITH CODE %code%.& pause)
exit /b %code%
