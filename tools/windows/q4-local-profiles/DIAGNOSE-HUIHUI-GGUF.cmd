@echo off
setlocal
cd /d "%~dp0"
set "PY=%~dp0.venv\Scripts\python.exe"
if not exist "%PY%" set "PY=E:\ai\Strata-Q4\.venv\Scripts\python.exe"
if not exist "%PY%" (
 echo Python virtualenv not found.
 pause
 exit /b 1
)
"%PY%" "%~dp0DIAGNOSE-HUIHUI-GGUF.py"
set "RC=%ERRORLEVEL%"
pause
exit /b %RC%
