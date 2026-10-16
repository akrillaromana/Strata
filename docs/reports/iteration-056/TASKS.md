# Осталось после итерации 056

1. На Windows собрать `engine\\strata.exe` через `BUILD-RUNTIME-TUNE-ENGINE.ps1`.
2. Перезапустить Q8_0 один раз, чтобы resident engine объявил `request_tune=2 live_tune=1`.
3. Выполнить `VERIFY-RUNTIME-TUNE.ps1`; PASS требует реального изменения PCIe offload scheduler между 0.00 и 1.00.
4. В Web проверить несколько PCIe значений без перезапуска модели и сравнить `PCIe offload ... entries` / decode tok/s.
5. CPU↔CUDA parity продолжать отдельно; runtime tuning от parity не зависит.
