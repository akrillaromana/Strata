@echo off
setlocal
cd /d "%~dp0"
where pwsh.exe >nul 2>nul || (echo PowerShell 7 pwsh.exe not found.& pause & exit /b 1)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0GET-Q6-DIAGNOSTICS.ps1"
pause
