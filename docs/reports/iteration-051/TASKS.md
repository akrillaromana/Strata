# TASKS — итерация 051

1. На Windows собрать отдельный `engine-q6\strata.exe` через `BUILD-Q6-ENGINE.ps1`.
2. Подготовить native pack именно из пяти `Qwen3.8-Flash-Next-Q6_K-*-of-00005.gguf`.
3. Получить READY и пройти `VERIFY-Q6-API.ps1`.
4. После READY выполнить `TEST-Q6.bat`, `BENCHMARK-Q6.bat`, затем `TUNE-Q6.bat`; MTP=1.0 должен оставаться в сетке.
5. Не переписывать вручную изменённые JSON; launcher использует их read-only.
