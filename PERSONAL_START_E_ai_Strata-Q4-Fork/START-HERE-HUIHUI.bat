@echo off
setlocal EnableExtensions
title Strata Huihui Q4_K_XL
cd /d "%~dp0"
set "LAUNCHER=%~dp0START-HUIHUI-Q4-RAM.ps1"
net session >nul 2>&1
if errorlevel 1 (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
if not exist "%LAUNCHER%" (
  echo ERROR: launcher not found: %LAUNCHER%
  pause
  exit /b 1
)
where pwsh.exe >nul 2>nul
if not errorlevel 1 (
  set "PS=pwsh.exe"
) else (
  set "PS=powershell.exe"
)
echo.
echo ============================================================
echo  STARTING Huihui-Qwen3.8-Flash-Next UD-Q4_K_XL
echo ============================================================
echo.
echo API: http://127.0.0.1:8080/v1 ^(bind 0.0.0.0^)
echo.
%PS% -NoProfile -ExecutionPolicy Bypass -File "%LAUNCHER%"
if errorlevel 1 (
  echo.
  echo Huihui Q4 startup FAILED.
  pause
  exit /b 1
)
echo.
echo Huihui Q4 launch completed.
timeout /t 3 /nobreak >nul
exit /b 0
