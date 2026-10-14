@echo off
setlocal
cd /d E:\ai\Strata-Q4-Fork
where pwsh.exe >nul 2>nul || (echo PowerShell 7 pwsh.exe not found.& pause & exit /b 1)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\BUILD-Q6-ENGINE.ps1"
if errorlevel 1 (echo.& echo Q6 ENGINE BUILD FAILED& pause& exit /b 1)
echo.& echo Q6 ENGINE BUILD OK& pause
