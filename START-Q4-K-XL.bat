@echo off
setlocal
cd /d "%~dp0"
title Strata - START-Q4-K-XL
where pwsh.exe >nul 2>nul
if errorlevel 1 (
  echo PowerShell 7 is required: pwsh.exe was not found.
  pause
  exit /b 1
)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0START-Q4-RAM.ps1" %*
set "code=%errorlevel%"
if not "%code%"=="0" (
  echo.
  echo Strata command failed with code %code%.
  pause
)
exit /b %code%
