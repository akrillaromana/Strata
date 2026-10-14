# TASKS — итерация 052

1. На Windows выполнить `BUILD-Q6-ENGINE.ps1`.
2. Подготовить native pack из пяти Q6_K GGUF через `START-Q6-RAM.ps1 -PreparePack -AllowBf16Conversion -PrepareOnly`.
3. Запустить Q6_K и получить READY.
4. Выполнить `VERIFY-Q6-API.ps1`, затем `TEST-Q6.bat` и `BENCHMARK-Q6.bat`.
5. Выполнить `TUNE-Q6.bat`; MTP=1.0 должен остаться кандидатом, default без применённого tune — 0.9.
6. Не переписывать root/PERSONAL JSON из launcher; runtime JSON только в logs.
