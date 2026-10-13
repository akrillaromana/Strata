@echo off
setlocal EnableExtensions

title Strata Q4_K_XL
cd /d "%~dp0"

set "ROOT=%~dp0"
set "LAUNCHER=%ROOT%START-Q4-RAM.ps1"

rem Нужны права администратора для RAM-диска и symlink.
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
    echo Place the personal launcher files together in:
    echo %ROOT%
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
echo  STARTING Qwen3.8-Flash-Next UD-Q4_K_XL
echo ============================================================
echo.
echo API: http://127.0.0.1:8080/v1
echo.
echo If Windows was rebooted, R: will be recreated and shard2/PLE
echo will be copied into RAM automatically. This may take some time.
echo.

%PS% -NoProfile -ExecutionPolicy Bypass -File "%LAUNCHER%"

if errorlevel 1 (
    echo.
    echo ============================================================
    echo  Q4 START FAILED
    echo ============================================================
    pause
    exit /b 1
)

echo.
echo ============================================================
echo  Q4_K_XL STARTED
echo  http://127.0.0.1:8080/v1
echo ============================================================

timeout /t 3 /nobreak >nul
exit /b 0