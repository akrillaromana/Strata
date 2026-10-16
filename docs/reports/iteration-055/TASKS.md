# TASKS — iteration 055

1. Один раз выполнить `BUILD-RUNTIME-TUNE-ENGINE.ps1` после обновления файлов.
2. Перезапустить нужную модель обычным launcher.
3. После READY выполнить `VERIFY-RUNTIME-TUNE.ps1`.
4. В Web сделать Ctrl+F5; проверить несколько запросов с разными PCIe/MTP без рестарта модели.
5. CPU/CUDA Q8 parity из 052 остаётся отдельной задачей: не включать его по умолчанию, пока реальный parity test не станет bitwise PASS.
