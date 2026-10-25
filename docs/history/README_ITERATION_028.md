# Strata Custom v0.1.39 — итерация 028

Полная поставка исходников поверх опубликованной 027 (`d5304f3`). Исправлены две проблемы, препятствовавшие надёжной подготовке Q8_0 PLE/n-gram и batch prefill для Qwen3.8 Flash Next.

- `tools/q8_ple_preflight.py`: после проверки собственной Q8_0 таблицы проверяет **все** GGUF-шарды и тензоры через общий `model_compat.inspect`, включая взаимную согласованность split metadata, отсутствие дубликатов, геометрию Q6_K/Q8_0, смещения, выравнивание, перекрытия и фактические размеры payload. Читает только GGUF headers, не загружает веса в RAM.
- `include/strata/kernels/native_ple_batch_shape.hpp`: безопасные размеры CUDA/SYCL launch, байтовые границы буферов и проверка отсутствия недопустимого alias. FP16 conv weights требуют только 2-байтового выравнивания, float буферы — 4.
- `src/kernels/cuda/native_ple_postops.cu` и `sycl/src/kernels/cuda/native_ple_postops.dp.cpp`: одинаковая проверка batch shape/buffers до отправки любых PLE GPU-ядер.
- Регрессии в `tests/cpu/native_ple_batch_shape_test.cpp`, `tools/test_q8_ple_preflight.py` и `tools/test_native_ple_batch_contract.py`.

**Проверено локально:** 543 Python tests tools, 2 skips; 43 Python tests serve; 10 personal profile tests; 55 JS; 7 standalone C++ с `-Werror`; Python compileall. CUDA/HIP/SYCL SDK и модели владельца не запускались. Следовательно, это исправление загрузки и проверки prefill, а не подтверждение работы всех моделей end-to-end.

Подробности: `docs/reports/iteration-028/`. Публикация — только по `PUBLISH_027_TO_028.txt`, без изменения личных файлов, установки и E:/R:.
