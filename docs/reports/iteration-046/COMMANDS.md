# PowerShell 7, итерация 046

После самостоятельной установки полного архива в `E:\ai\Strata-Q4-Fork` и остановки прежнего сервера Ctrl+C, в первом окне (PowerShell 7 от администратора):

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
Set-Location "E:\ai\Strata-Q4-Fork"
Get-Content .\STRATA_ITERATION.txt -TotalCount 1
& .\tools\TEST-MODEL-LAUNCHERS.ps1
& .\START-Q8-RAM.ps1
```

Если в первом окне длительно проверяется SHA-256, не прерывать её. В отдельном окне диагностика:

```powershell
Set-Location "E:\ai\Strata-Q4-Fork"
& .\GET-Q8-DIAGNOSTICS.ps1
```

При необходимости обратимой проверки без калибровки **после штатной остановки первого запуска**:

```powershell
& .\START-Q8-RAM.ps1 -IgnoreAutotune
```

**Не** использовать `-PreparePack`: собственный Q8-пакет уже подготовлен.
