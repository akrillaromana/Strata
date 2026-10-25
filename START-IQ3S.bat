@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
title Strata - START-IQ3S

set "PS="
for /f "delims=" %%P in ('where pwsh.exe 2^>nul') do if not defined PS set "PS=%%P"
if not defined PS if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PS=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not defined PS if exist "%LOCALAPPDATA%\Programs\PowerShell\7\pwsh.exe" set "PS=%LOCALAPPDATA%\Programs\PowerShell\7\pwsh.exe"
if not defined PS (
  echo PowerShell 7 was not found. Windows PowerShell 5.1 is not supported.
  echo Install PowerShell 7 with:
  echo   winget install --id Microsoft.PowerShell --source winget
  pause
  exit /b 1
)

"%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0START-IQ3S-RAM.ps1" %*
set "CODE=%ERRORLEVEL%"
if not "%CODE%"=="0" (
  echo.
  echo Strata command failed with code %CODE%.
  pause
)
exit /b %CODE%
