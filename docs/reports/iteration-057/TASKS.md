# TASKS — iteration 057

- На Windows/RTX 3060 собрать текущий runtime engine через `BUILD-RUNTIME-TUNE-ENGINE.ps1` и выполнить `VERIFY-RUNTIME-TUNE.ps1`.
- После READY проверить Web Apply: PCIe/MTP меняются без рестарта, UI показывает только engine ACK и PCIe offload metric.
- Q8 CPU↔CUDA parity оставить opt-in до успешного аппаратного `TEST-PCIE-PARITY.bat`; не делать его default без подтверждения идентичности и скорости.
