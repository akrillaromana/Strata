# Команды Windows PowerShell 7

После самостоятельного обновления исходников. Модель запускается в первом окне, оно остаётся открытым:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
Set-Location 'E:\ai\Strata-Q4-Fork'
& '.\tools\TEST-MODEL-LAUNCHERS.ps1'
& '.\tools\TEST-CONFIG-IMMUTABILITY.ps1'
& '.\START-Q8-RAM.ps1'
```

Для IQ3_S, Q4_K_XL и Huihui соответственно `START-IQ3S-RAM.ps1`, `START-Q4-RAM.ps1`, `START-HUIHUI-Q4-RAM.ps1`. Аналогичные BAT-файлы в корне позволяют запуск двойным кликом.

Во втором окне, когда сервер сообщает READY:

```powershell
Set-Location 'E:\ai\Strata-Q4-Fork'
& '.\TEST-REQUESTS.ps1' -Requests 6
& '.\BENCHMARK-MODEL.ps1' -Runs 3
& '.\TUNE-MODEL.ps1' -Apply
```

Результаты: `logs\request-tests\REQUEST_TEST_LAST.json`, `logs\benchmark\BENCHMARK_MODEL_LAST.json`, `logs\autotune\...-LAST.json`. Пример с API-ключом: `& '.\TEST-REQUESTS.ps1' -ApiKey '<ваш ключ>'` (не записывайте ключ в отчёт/общий чат).
