# Личные модели, полученные из списка владельца 2026-10-10

Это **матрица требований и известных кодовых маршрутов**, НЕ сертификат запуска.

| ID | Основные GGUF | Шарды | Кодовый статус |
|---|---|---:|---|
| `alesha_rco_iq3s` | `Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S` | 2 | Existing native IQ3_S kernel route; dedicated pack/profile and full numerical integration not verified. |
| `sc117_rco_iq3s` | `Qwen3.8-Flash-Next-GSQ-RCO-abliterated-IQ3_S` | 2 | Existing native IQ3_S kernel route; dedicated pack/profile and full numerical integration not verified. |
| `personal_rco_iq3s` | `Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S` | 2 | Existing personal RAM profile and paths retained; no external execution. |
| `huihui_q8` | `Qwen3.8-Flash-Next-Q8_0` | 6 | Native Q8_0 PLE source enforcement plus 6-shard checks; full Huihui CPU/CUDA/MTP not verified. |
| `huihui_q4` | `Qwen3.8-Flash-Next-UD-Q4_K_XL` | 4 | Existing Huihui Q4 personal profile preserved; full runtime not retested. |
| `unsloth_q6` | `Qwen3.8-Flash-Next-Q6_K` | 5 | Q6_K CUDA gate/up/down opt-in source route; full GPU numerical equivalence unverified. |
| `unsloth_q8` | `Qwen3.8-Flash-Next-Q8_0` | 6 | Existing personal Q8 and native 170-byte Q8 PLE requirement preserved; no model weights checked. |
| `unsloth_q4` | `Qwen3.8-Flash-Next-UD-Q4_K_XL` | 4 | Existing personal Q4 profiles preserved; no runtime retest. |

## Дополнительные файлы

Unsloth: два `mmproj`, четыре MTP GGUF (`BF16`, `Q8_0`, `shared-BF16`, `shared-Q8_0`).
Huihui: `mmproj-model-bf16.gguf`; SC117 и alesha-pro: `mmproj-Qwen3.8-Flash-Next-BF16.gguf`.
RCO IQ3_S из настроек (не из списка `E:\ai\models`) находится в `E:\ai\Strata-data\models\IQ3_S`.
Папки `HauhauCS`, `morikomorizz`, `lmstudio-community` присутствуют в списке только как каталоги; имена файлов моделей не представлены, поддержку конкретных весов невозможно установить.

## Границы текущей работы

- Все shard paths в реестре — именно из присланного списка, а не вымышленные имена моделей.
- Оригинальная Q8_0 PLE проверяется на тип и полную геометрию; отсутствие — явный отказ, без IQ4_NL fallback.
- Q6_K включается через `STRATA_Q6K_EXPERTS` и `STRATA_MMQ_KQUANTS`: этот кодовый маршрут НЕ подтверждён полной CUDA-сборкой или GPU-паритетом.
- GGUF MTP — исходные checkpoint-файлы, **не готовый каталог** `--mtp`; нельзя передавать их движку вместо подготовленного runtime.
- Наличие `mmproj` само по себе не означает поддержку изображений: требуются `strata-vision`, параметр `--vision`, серверная конфигурация `vision` и согласованность проектора.
- Уникальные личные BAT/PS1/JSON в архиве сохранены без изменения, включая `E:` и `R:`.
- Заголовки исходных GGUF-шардов из `E:` не читались — байты весов не предоставлены; проверка моделей на устройстве владельца отложена.
