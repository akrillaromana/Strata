@echo off
setlocal
cd /d "%~dp0"
where pwsh.exe >nul 2>nul
if errorlevel 1 (
  echo PowerShell 7 pwsh.exe not found.
  exit /b 1
)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0BUILD_AND_START_IQ3S.ps1" -BuildOnly -ParityTest
exit /b %errorlevel%
