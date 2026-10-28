# Uncensor control vector

Файл `qwen-nvfp4-gptq-uncensored.gguf` (+ `.json`) — скачан как есть из
https://github.com/sergqwer/strata-nvfp4/tree/main/data/uncensor (коммит main на момент загрузки).

- Формат: GGUF `controlvector`, `controlvector.model_hint = qwen4exp`, 26 тензоров
  `direction.8 .. direction.33`, каждый 2560 float32 (267 552 байта).
- Механизм: движок снимает направление отказа из hyper-connection остаточного потока
  после каждого слоя 8..33 (`h -= s (h·v) v`), `--cvec-mode project --cvec-dir per-layer`.
- Флаги движка (из JSON и конфига-эталона):
  `--control-vector-scaled <этот gguf>:1.0 --control-vector-layer-range 8 33 --cvec-mode project --cvec-dir per-layer`
  плюс `env.STRATA_HC_Q8=1` (Q8_0-проекции hyper-connection — скорость; в эталонном конфиге идёт вместе с вектором).
- Лицензия вектора: Qwen Community License 1.0 (построен только из GPTQ-кванта BF16-весов Qwen, без NVIDIA-весов).

Лаунчер START-CATALOG-MODEL.ps1 подключает вектор по умолчанию для всех профилей `qwen4exp`
(Qwen3.8-Flash-Next). Upstream не измерял вектор на Swift 1.5 / Coder (другие веса) — для них он
применяется на свой риск и об этом предупреждает при запуске.
