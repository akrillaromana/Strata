# COMMANDS — Q6_K

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
Set-Location "E:\ai\Strata-Q4-Fork"

& ".\BUILD-Q6-ENGINE.ps1"
& ".\START-Q6-RAM.ps1" -PreparePack -AllowBf16Conversion -PrepareOnly
& ".\START-Q6-RAM.ps1"
```

После READY во втором PowerShell:

```powershell
Set-Location "E:\ai\Strata-Q4-Fork"
& ".\VERIFY-Q6-API.ps1"
& ".\TEST-REQUESTS.ps1" -Requests 6
& ".\BENCHMARK-MODEL.ps1" -Runs 3
& ".\TUNE-MODEL.ps1" -Model "qwen3.8-flash-next-unsloth-q6_k" -Apply
```
