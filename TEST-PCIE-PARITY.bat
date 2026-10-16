@echo off
setlocal
cd /d "%~dp0"
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0TEST-PCIE-PARITY.ps1"
if errorlevel 1 pause
endlocal
