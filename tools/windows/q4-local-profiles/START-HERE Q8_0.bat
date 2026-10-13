@echo off
setlocal EnableExtensions
title Strata Unsloth Q8_0
cd /d "%~dp0"
set "LAUNCHER=%~dp0START-Q8-RAM.ps1"

net session >nul 2>&1
if errorlevel 1 (
  echo Requesting Administrator rights for the RAM disk and symlinks...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
if not exist "%LAUNCHER%" (
  echo Q8_0 launcher not found: "%LAUNCHER%"
  pause
  exit /b 1
)
where pwsh.exe >nul 2>nul
if errorlevel 1 (
  echo PowerShell 7 is required for the Q8_0 GGUF preflight.
  pause
  exit /b 1
)

echo.
echo ============================================================
echo  STARTING Qwen3.8-Flash-Next UNSLOTH Q8_0
echo  http://127.0.0.1:8080/v1
echo ============================================================
echo.
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%LAUNCHER%" %*
if errorlevel 1 (
  echo.
  echo Q8_0 START FAILED. Read the error above.
  pause
  exit /b 1
)
echo.
echo Q8_0 SERVER STOPPED
timeout /t 3 /nobreak >nul
exit /b 0