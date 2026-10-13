# Команды проверки итерации 049

Во втором PowerShell 7 при уже работающей модели:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
Set-Location "E:\ai\Strata-Q4-Fork"

& ".\tools\TEST-MODEL-LAUNCHERS.ps1"
& ".\tools\TEST-CONFIG-IMMUTABILITY.ps1"
& ".\TEST-REQUESTS.ps1" -Requests 6
& ".\BENCHMARK-MODEL.ps1" -Runs 3
& ".\TUNE-MODEL.ps1" -Apply
```

`TUNE-MODEL.ps1` должен показать MTP=1 как одну из измеряемых точек.
