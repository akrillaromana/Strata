@echo off
cd /d "E:\ai\Strata-Q4"
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "E:\ai\Strata-Q4\START-QUALITY-RAM.ps1"
if errorlevel 1 pause
