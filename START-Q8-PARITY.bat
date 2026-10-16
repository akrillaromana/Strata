@echo off
setlocal
cd /d "%~dp0"
echo ============================================================
echo  STARTING Q8_0 - EXPERIMENTAL CPU/CUDA EXPERT PARITY
ECHO ============================================================
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0START-Q8-RAM.ps1" -ExpertParityCuda
if errorlevel 1 (
  echo.
  echo Q8_0 PARITY START FAILED. Read the error above.
  pause
)
endlocal
