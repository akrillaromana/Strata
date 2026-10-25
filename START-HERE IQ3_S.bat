@echo off
setlocal EnableExtensions DisableDelayedExpansion

title Strata IQ3_S GSQ-RCO
cd /d "%~dp0"

set "ROOT=%~dp0"
set "LAUNCHER=%ROOT%START-IQ3S-RAM.ps1"

rem The AWE RAM disk and the model symlink require an elevated process.
net session >nul 2>&1
if errorlevel 1 (
    echo.
    echo Requesting Administrator rights...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

if not exist "%LAUNCHER%" (
    echo.
    echo ERROR: IQ3_S launcher was not found:
    echo "%LAUNCHER%"
    echo.
    pause
    exit /b 1
)

rem Locate PowerShell 7. Never fall back to Windows PowerShell 5.1:
rem it cannot safely read this UTF-8 project and is not supported by the launcher.
set "PS="
for /f "delims=" %%P in ('where pwsh.exe 2^>nul') do if not defined PS set "PS=%%P"
if not defined PS if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PS=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not defined PS if exist "%LOCALAPPDATA%\Programs\PowerShell\7\pwsh.exe" set "PS=%LOCALAPPDATA%\Programs\PowerShell\7\pwsh.exe"

if not defined PS (
    echo.
    echo ERROR: PowerShell 7 was not found.
    echo Windows PowerShell 5.1 is not supported by this launcher.
    echo Install PowerShell 7 with:
    echo   winget install --id Microsoft.PowerShell --source winget
    echo Then run this file again.
    echo.
    pause
    exit /b 1
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
echo The IQ3_S PLE shard is copied to the 54 GiB R: RAM disk.
echo Shard 1 is loaded into normal system RAM by Strata at startup.
echo.
echo PowerShell: "%PS%"
echo.

rem Interactive by default; Ctrl+C stops the foreground server.
"%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%LAUNCHER%" %*
set "EXITCODE=%ERRORLEVEL%"

if not "%EXITCODE%"=="0" (
    echo.
    echo ============================================================
    echo  IQ3_S START FAILED (exit code %EXITCODE%)
    echo ============================================================
    pause
    exit /b %EXITCODE%
)

echo.
echo ============================================================
echo  IQ3_S SERVER STOPPED
echo ============================================================
timeout /t 3 /nobreak >nul
exit /b 0
