# Команды проверки итерации 050

После самостоятельного обновления файлов в `E:\ai\Strata-Q4-Fork`:

```powershell
& '.\tools\TEST-MODEL-LAUNCHERS.ps1'
& '.\tools\TEST-CONFIG-IMMUTABILITY.ps1'
```

Проверка выбранной модели выполняется штатным запускателем. В runtime-конфиге без применённого autotune ожидаются:

```text
--pcie-frac 0.26
--spec-min-p 0.9
```

Автокалибровка по-прежнему может явно выбрать другие значения:

```powershell
& '.\TUNE-MODEL.ps1' -Apply
```
