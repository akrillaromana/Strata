# Команды для итерации 039

Архив распаковывается пользователем самостоятельно в `E:\ai\Strata-Q4-Fork`. Не включать сюда команды распаковки.

## Уже работающий сервер — второе окно PowerShell

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
Set-Location 'E:\ai\Strata-Q4-Fork'
& '.\BENCHMARK-IQ3S.ps1'
& '.\TUNE-IQ3S.ps1' -Apply
```

## Применение результата — первое окно PowerShell

Остановить старый сервер с помощью `Ctrl+C`. Затем:

```powershell
Set-Location 'E:\ai\Strata-Q4-Fork'
& '.\START-IQ3S-RAM.ps1'
```

Для запуска со штатными прежними настройками:

```powershell
& '.\START-IQ3S-RAM.ps1' -IgnoreAutotune
```

Точная настройка не гарантирует тот же прирост на иных промптах. Полный отчёт автоподбора: `logs\iq3s\AUTOTUNE_IQ3S_LAST.json`.
