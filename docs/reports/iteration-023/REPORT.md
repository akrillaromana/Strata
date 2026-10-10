# Итерация 023 — единый preflight GGUF для NativeHead и NativeEmbed

**База:** полный архив 022, публикация `cf781ff` подтверждена пользовательским журналом; ветка `strata-v0.1.39-custom`. Архив включает всё 001–023, не удаляет рабочие файлы предыдущих итераций.

## Подтверждённые дефекты 022

1. `src/core/native_head.cpp::NativeHead::load` открывал `GgufModel`, но проверял диапазон только `output.weight`: соседний/дальний шард с повреждёнными Q6_K/Q8_0 тензорами не проверялся перед `cudaMalloc`.
2. `NativeEmbed::load` аналогично проверял лишь `token_embd.weight` перед `cudaHostAlloc` / CUDA fallback. Повреждённые поздние шарды могли пройти, хотя `NativeDense` уже имел строгий preflight.
3. Размер native embedding вычислялся как `row_ * n_vocab` без явного контроля переполнения и без отказа от отрицательного `n_vocab`. `gather_one` не проверял token ID до адресации таблицы.

## Изменения исходников

- В `include/strata/artifact/gguf_reader.hpp` добавлен единый `validate_native_model_payloads(const GgufModel&)`: перебирает ВСЕ shard-файлы и проверяет их tensor directory, геометрию квантованных строк, выравнивание, пересечения и payload bounds независимо от того, используется ли конкретный тензор.
- `NativeDense::served_names` и `NativeDense::load` используют общий helper вместо двух раздельных циклов.
- `NativeHead::load` применяет helper до первых CUDA allocations/copies; отсутствие `output.weight` обрабатывается до доступа к shard-index.
- `NativeEmbed::load` применяет тот же helper до host-pinning/GPU allocations. `native_embedding_checked_bytes()` отклоняет нулевую/отрицательную геометрию, `n_vocab` за пределами int32 token ID, неправильный stride и overflow произведения числа строк на размер строки. Missing tensor обрабатывается до `model.shard()`.
- `NativeEmbed::gather_one` проверяет token ID на диапазон `0..n_vocab-1` перед обращением к буферу.
- Старые native Q4_K_XL, IQ3_S, Q6_K, Q8_0, MTP типы и личные настройки остаются без изменений. Не вводится новая зависимость от CUDA в CPU helper.

## Регрессии и ограничения

- 133 профильных Python unit tests PASS; 32 `serve` Python PASS; 8 тестов личных профилей PASS. JS 55/55 PASS. Шесть standalone C++ тестов PASS (`-std=c++20 -Wall -Wextra -Werror`), в том числе новый multishard head/embedding preflight.
- Новая фикстура: shard 1 только метаданные, shard 2 корректные Q8_0 `output.weight`/`token_embd.weight`, shard 3 содержит Q6_K; повреждение физического хвоста shard 3 выявляется до CUDA. BF16-эмбеддинг отдельного `strata-embd` также проходит.
- Это **реальное исправление native loader**, но НЕ proof CUDA compile or full engine Q6_K/Huihui Q8_0 end-to-end. CUDA/модели не запускались; GPU tests не проводились. Закрытый участок — только безопасность источников + входная арифметика.
- Не заявлять 100% готовности проекта; следующие функции всё ещё открыты: вычислительный end-to-end Q6_K/Q8_0, реальные MTP GGUF / shared topology, Vision/mmproj, token-constrained JSON Schema, другие доноры 0.1.41.

## Публикация

Публиковать только пути `PUBLISH_022_TO_023.txt`, от HEAD `cf781ff`. Git-команды сообщить **в чате**, отдельно staging и commit/push; не трогать рабочую Strata на E:, веса, R:, личные профили, чужие untracked `tj` и `h origin strata-v0.1.39-custom`. Архив не содержит бинарников и весов.
