# Семантика дополнительного shared-only MTP GGUF

В `E:\ai\models\unsloth\Qwen3.8-Flash-Next-GGUF` известны из пользовательского списка:

- `mtp-Qwen3.8-Flash-Next-BF16.gguf`
- `mtp-Qwen3.8-Flash-Next-Q8_0.gguf`
- `mtp-Qwen3.8-Flash-Next-shared-BF16.gguf`
- `mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf`

Две пары занесены в `data/personal_models.json` как **candidate**, не как проверенные. Опция `--shared-gguf` в `tools/mtp_original_rt.py` должна быть названа явно; она не использует сведения из персонального реестра автоматически.

Разрешены только три полных пути `mtp.layers.0.mlp.shared_expert.gate_proj.weight`, `.up_proj.weight`, `.down_proj.weight` и, необязательно, `mtp.layers.0.mlp.shared_expert_gate.weight`. Первые три обязательны в companion, имеют физические GGUF BF16 или Q8_0 строки с проверенными размерами (FF=640, H=2560); scalar gate принимает только BF16 с H=2560 элементами. Подмена исходного тензора запрещена: совпадающий tensor name должен означать идентичные физические байты.

Если supplemental содержит tensor не из allowlist, неполный список, невалидный тип/shape, duplicate или не приносит ни одного отсутствующего тензора — обработка прекращается до записи runtime. Это безопасно, но **может не соответствовать фактической архитектуре shared GGUF**, поскольку у нас нет его физического заголовка. Для полноценной универсальности требуется исследование реального GGUF, отдельно от пользовательской фазы тестирования.

`origin_verified=false` в `source_policy.json` означает, что автоматической проверки эквивалентности модельных чекпоинтов нет. Никогда не представлять такой runtime как подтверждённый по качеству/производительности. Старые BF16/Q8 native + Q2 compatibility пути и вычисления из 018–019 сохраняются.
