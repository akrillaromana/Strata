@echo off
setlocal
cd /d "%~dp0"
title Strata - TUNE-Q6
where pwsh.exe >nul 2>nul || (echo PowerShell 7 pwsh.exe not found.& pause & exit /b 1)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0TUNE-MODEL.ps1" -Model "qwen3.8-flash-next-unsloth-q6_k" -Apply %*
set "code=%errorlevel%"
if not "%code%"=="0" (echo.& echo Q6 TUNE FAILED WITH CODE %code%.& pause)
exit /b %code%
