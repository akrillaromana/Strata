# Команды Windows — итерация 056

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
Set-Location "E:\ai\Strata-Q4-Fork"

& ".\BUILD-RUNTIME-TUNE-ENGINE.ps1"
& ".\START-Q8-RAM.ps1"
```

После READY, во втором PowerShell:

```powershell
Set-Location "E:\ai\Strata-Q4-Fork"

& ".\VERIFY-RUNTIME-TUNE.ps1"
& ".\tools\TEST-CONFIG-IMMUTABILITY.ps1"
```
