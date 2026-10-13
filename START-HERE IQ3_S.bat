@echo off
setlocal EnableExtensions

title Strata IQ3_S GSQ-RCO
cd /d "%~dp0"

set "ROOT=%~dp0"
set "LAUNCHER=%ROOT%START-IQ3S-RAM.ps1"

rem Administrator rights are needed for the AWE RAM disk and symlink.
net session >nul 2>&1
if errorlevel 1 (
    echo.
    echo Requesting Administrator rights...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

if not exist "%LAUNCHER%" (
    echo.
    echo ERROR: file not found:
    echo %LAUNCHER%
    echo.
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
echo  STARTING Qwen3.8-Flash-Next GSQ-RCO IQ3_S
echo ============================================================
echo.
echo Models: E:\ai\Strata-data\models\IQ3_S
echo Bind:   0.0.0.0:8080
echo Local:  http://127.0.0.1:8080/v1
echo.
echo The IQ3_S PLE shard is copied to the 64 GiB R: RAM disk.
echo Shard 1 is loaded into normal system RAM by Strata at startup.
echo.

rem Interactive by default: the server stays in this window and prints each
rem request's prefill, generation progress and final tok/s until Ctrl+C.
%PS% -NoProfile -ExecutionPolicy Bypass -File "%LAUNCHER%"

if errorlevel 1 (
    echo.
    echo ============================================================
    echo  IQ3_S START FAILED
    echo ============================================================
    pause
    exit /b 1
)

echo.
echo ============================================================
echo  IQ3_S SERVER STOPPED
echo ============================================================

timeout /t 3 /nobreak >nul
exit /b 0
