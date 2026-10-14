# COMMANDS — Q6_K после итерации 052

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
Set-Location "E:\ai\Strata-Q4-Fork"

& ".\BUILD-Q6-ENGINE.ps1"
& ".\START-Q6-RAM.ps1" -PreparePack -AllowBf16Conversion -PrepareOnly
& ".\START-Q6-RAM.ps1"
```

После READY в отдельном PowerShell:

```powershell
Set-Location "E:\ai\Strata-Q4-Fork"
& ".\VERIFY-Q6-API.ps1"
& ".\TEST-Q6.bat"
& ".\BENCHMARK-Q6.bat"
& ".\TUNE-Q6.bat"
```
