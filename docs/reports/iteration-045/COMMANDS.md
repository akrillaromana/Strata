# Выполнение на Windows PowerShell 7 — итерация 045

Пользователь распаковывает архив самостоятельно в `E:\ai\Strata-Q4-Fork`.

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
Set-Location 'E:\ai\Strata-Q4-Fork'
Get-Content '.\STRATA_ITERATION.txt' -TotalCount 1
& '.\tools\TEST-MODEL-LAUNCHERS.ps1'
& 'C:\Users\Keter\AppData\Local\Programs\Python\Python312\python.exe' '.\tools\ensure_gguf_py.py'
& '.\START-Q8-RAM.ps1' -PreparePack -AllowBf16Conversion
```

Последнюю команду выполнять в окне PowerShell 7 с правами администратора после остановки другой модели штатным `Ctrl+C`. Если проверка `ensure_gguf_py.py` перед запуском выдаст код 2, сценарий запуска попытается самостоятельно получить закреплённую библиотеку. При сетевом отказе выведет точную причину; исходные GGUF и R: останутся без изменений.

Для повторной диагностики библиотеки без загрузки модели:

```powershell
Set-Location 'E:\ai\Strata-Q4-Fork'
& 'C:\Users\Keter\AppData\Local\Programs\Python\Python312\python.exe' '.\tools\ensure_gguf_py.py'
```
