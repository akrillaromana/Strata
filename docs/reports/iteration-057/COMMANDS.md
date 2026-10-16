# COMMANDS — iteration 057

## Windows: runtime tune

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
Set-Location "E:\ai\Strata-Q4-Fork"
& ".\BUILD-RUNTIME-TUNE-ENGINE.ps1"
& ".\START-Q8-RAM.ps1"
```

После READY во втором PowerShell:

```powershell
Set-Location "E:\ai\Strata-Q4-Fork"
& ".\VERIFY-RUNTIME-TUNE.ps1"
& ".\tools\TEST-CONFIG-IMMUTABILITY.ps1"
```

Q8 parity остаётся отдельным opt-in тестом:

```powershell
Set-Location "E:\ai\Strata-Q4-Fork"
& ".\TEST-PCIE-PARITY.bat"
```
