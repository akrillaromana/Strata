@echo off
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0BUILD-RUNTIME-TUNE-ENGINE.ps1"
exit /b %ERRORLEVEL%
