@echo off
setlocal
cd /d "E:\ai\Strata-Q4-Fork"
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\VERIFY-Q6-API.ps1"
if errorlevel 1 pause
endlocal
