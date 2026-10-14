@echo off
setlocal
cd /d "%~dp0"
title Strata - SETUP Q6_K
where pwsh.exe >nul 2>nul || (echo PowerShell 7 pwsh.exe not found.& pause & exit /b 1)
echo ============================================================
echo  BUILDING SEPARATE Q6_K ENGINE
echo ============================================================
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0BUILD-Q6-ENGINE.ps1"
if errorlevel 1 goto :fail
echo.
echo ============================================================
echo  PREPARING Q6_K NATIVE PACK
echo ============================================================
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0START-Q6-RAM.ps1" -PreparePack -AllowBf16Conversion -PrepareOnly
if errorlevel 1 goto :fail
echo.
echo Q6_K setup completed. Use START-Q6-K.bat to launch.
exit /b 0
:fail
echo.
echo Q6_K SETUP FAILED.
pause
exit /b 1
