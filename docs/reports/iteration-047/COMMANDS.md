# Команды PowerShell 7 для проверки итерации 047

После самостоятельной распаковки полного архива и **сохранения собственных отредактированных JSON**, из PowerShell 7 **от имени администратора**:

```powershell
$ErrorActionPreference = 'Stop'
Set-ExecutionPolicy -Scope Process Bypass -Force
Set-Location 'E:\ai\Strata-Q4-Fork'
Get-Content '.\STRATA_ITERATION.txt' -TotalCount 1
& '.\tools\TEST-MODEL-LAUNCHERS.ps1'
& '.\tools\TEST-CONFIG-IMMUTABILITY.ps1'
& '.\START-Q8-RAM.ps1'
```

Движок и модель не пересобирать; `-PreparePack` не нужен при готовом пакете. Сервер работает в текущем окне, завершение Ctrl+C.

Если снова не READY, во втором окне:

```powershell
Set-Location 'E:\ai\Strata-Q4-Fork'
& '.\GET-Q8-DIAGNOSTICS.ps1'
```

Диагностика: `logs\q8\Q8_START_LAST.txt`, `logs\q8\Q8_FAILURE_LAST.txt`, `logs\q8\Q8_DIAGNOSTICS_LAST.txt`, `logs\ram-disk\RAM_DIAGNOSTICS_LAST.txt`. Журнал рабочего JSON — `logs\q8\runtime-*.json` (файлы содержат параметры, в том числе потенциальные ключи API; перед отправкой удалите секреты).
