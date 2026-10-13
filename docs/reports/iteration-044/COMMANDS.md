# Команды PowerShell 7 после самостоятельной распаковки итерации 044

Не включать команды загрузки, поиска либо распаковки архива: пользователь всегда распаковывает ZIP вручную непосредственно в `E:\ai\Strata-Q4-Fork`.

## Проверка того, какая версия действительно находится на диске

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
Set-Location 'E:\ai\Strata-Q4-Fork'
Get-Content '.\STRATA_ITERATION.txt' -TotalCount 1
$Launcher = Get-Command '.\START-Q8-RAM.ps1' -CommandType ExternalScript
$Inner = Get-Command '.\PERSONAL_START_E_ai_Strata-Q4-Fork\START-Q8-RAM.ps1' -CommandType ExternalScript
foreach ($ParameterName in @('PreparePack','AllowBf16Conversion')) {
    if (-not $Launcher.Parameters.ContainsKey($ParameterName) -or
        -not $Inner.Parameters.ContainsKey($ParameterName)) {
        throw "Не обновлён Q8_0 запускатель, отсутствует -$ParameterName."
    }
}
& '.\tools\TEST-MODEL-LAUNCHERS.ps1'
```

## Подготовка и запуск Q8_0

Только после остановки другой модели (`Ctrl+C`), из PowerShell 7 от имени администратора:

```powershell
Set-Location 'E:\ai\Strata-Q4-Fork'
& '.\START-Q8-RAM.ps1' -PreparePack -AllowBf16Conversion
```

По умолчанию запускается живой терминал. Не закрывать его во время работы модели. Само разрешение `-AllowBf16Conversion` допускает изменение точности **отдельных плотных проекций**; оригинальная PLE `Q8_0` и эксперты в исходных GGUF должны сохраниться.

## Если появится следующая ошибка

Предоставить полный вывод PowerShell. При ошибке RAM дополнительно `logs\ram-disk\RAM_DIAGNOSTICS_LAST.txt` и `logs\ram-disk\RAM_DISK_LAST.txt`. При ошибке Q8 после начала загрузки — файлы из `logs\q8`.
