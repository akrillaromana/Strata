# PowerShell 7.6.6 — команды после самостоятельной распаковки

Архив разархивирует пользователь. В командах нет поиска и распаковки ZIP.

## Диагностика безопасного восстановления R:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
Set-Location 'E:\ai\Strata-Q4-Fork'
& '.\tools\TEST-MODEL-LAUNCHERS.ps1'
& '.\CHECK-STRATA-RAM-DISK.ps1'
```

## Q4_K_XL (в PowerShell от имени администратора, после остановки другой модели Ctrl+C)

```powershell
Set-Location 'E:\ai\Strata-Q4-Fork'
& '.\START-Q4-RAM.ps1'
```

Если `R:` не восстанавливается, передать `logs\ram-disk\RAM_DIAGNOSTICS_LAST.txt` и `logs\ram-disk\RAM_DISK_LAST.txt`. Не применять `aim_ll -d/-D` и не форматировать том самостоятельно.

## Подготовка собственного Q8_0 после остановки Q4

```powershell
Set-Location 'E:\ai\Strata-Q4-Fork'
& '.\START-Q8-RAM.ps1' -PreparePack -AllowBf16Conversion
```

Это может продолжительно читать большой исходный GGUF, создавать нативный пакет на E: и копировать таблицу PLE на R:. Ключ разрешает **округление небольших плотных проекций в BF16**; оригинальные эксперты и Q8_0 PLE остаются в GGUF. Без разрешения пакет не строится. Никакой прежний пакет не перезаписывается.
