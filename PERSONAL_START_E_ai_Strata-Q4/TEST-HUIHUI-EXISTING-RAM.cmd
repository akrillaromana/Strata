@echo off
setlocal EnableExtensions
cd /d "%~dp0"
net session >nul 2>&1
if errorlevel 1 (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
  exit /b 0
)
where pwsh.exe >nul 2>&1
if errorlevel 1 (
  echo PowerShell 7 is required: pwsh.exe was not found.
  pause
  exit /b 1
)
if not exist "%~dp0START-HUIHUI-Q4-RAM.ps1" (
  echo ERROR: missing START-HUIHUI-Q4-RAM.ps1
  pause
  exit /b 1
)
echo.
echo Verifying Huihui GGUF, pack and RAM staging.
echo If R:\q4-model is missing, 46 GiB of PLE will be COPIED from E: to R:.
echo If staging is present, SHA256 checks prevent original/Huihui cross-contamination.
echo.
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0START-HUIHUI-Q4-RAM.ps1" -ResumeRam -Foreground
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" echo Huihui test failed: exit code %RC%
pause
exit /b %RC%
