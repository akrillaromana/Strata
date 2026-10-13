@echo off
setlocal EnableExtensions
rem Старый прямой запуск зависел от отсутствующего .venv и не готовил DLL CUDA.
rem Пользуемся единым проверенным RAM-запускателем с текущим Python.
call "%~dp0START-HERE.bat" %*
exit /b %ERRORLEVEL%
