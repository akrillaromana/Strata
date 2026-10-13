@echo off
setlocal EnableExtensions
title Prepare Huihui Q4 native pack
set "ROOT=E:\ai\Strata-Q4-Fork"
set "PY=%ROOT%\.venv\Scripts\python.exe"
set "SCRIPT=%~dp0PREPARE-HUIHUI-Q4.py"
if not exist "%PY%" (
 echo ERROR: Strata Python not found: %PY%
 pause
 exit /b 1
)
if not exist "%SCRIPT%" (
 echo ERROR: preparation script not found: %SCRIPT%
 pause
 exit /b 1
)
"%PY%" "%SCRIPT%" --build
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
 echo.
 echo Preparation stopped without modifying original model or pack.
) else (
 echo.
 echo Huihui native pack ready. Next: START-HERE-HUIHUI.bat
)
pause
exit /b %RC%
