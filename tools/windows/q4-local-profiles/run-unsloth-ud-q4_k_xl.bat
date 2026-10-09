@echo off
title Strata unsloth-UD-Q4_K_XL
cd /d "E:\ai\Strata-Q4"
"E:\ai\Strata-Q4\.venv\Scripts\python.exe" "E:\ai\Strata-Q4\serve\server.py" "--engine" "strata" "--config" "E:\ai\Strata-Q4\strata-unsloth-ud-q4_k_xl.json" "--port" "8080" "--open"
if errorlevel 1 pause
