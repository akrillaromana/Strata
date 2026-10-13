@echo off
cd /d "E:\ai\Strata-Q4-Fork"
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "E:\ai\Strata-Q4-Fork\START-QUALITY-RAM.ps1"
if errorlevel 1 pause
