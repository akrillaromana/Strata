@echo off
setlocal EnableExtensions
cd /d "%~dp0"
net session >nul 2>&1
if errorlevel 1 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b 0
)
where pwsh.exe >nul 2>&1
if errorlevel 1 (
    echo PowerShell 7 is required: pwsh.exe was not found.
    pause
    exit /b 1
)
if not exist "%~dp0DIAGNOSE-HUIHUI-START.ps1" (
    echo ERROR: missing DIAGNOSE-HUIHUI-START.ps1
    pause
    exit /b 1
)
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0DIAGNOSE-HUIHUI-START.ps1" %*
set "RC=%ERRORLEVEL%"
if "%RC%"=="0" (
    echo Huihui is running.
) else (
    echo Huihui diagnostic failed with code %RC%.
)
pause
exit /b %RC%
