# Открытые задачи после итерации 017 — исходники

- [x] Отдельный строгий разбор исходных BF16/Q8_0 MTP GGUF и отказ от неявной подмены.
- [x] Явно opt-in потоковое преобразование routed experts в совместимый Q2_0 runtime как **промежуточная опция**, с маркировкой потери качества и проверкой диапазонов и целостности выхода.
- [x] Автономные интеграционные тесты импорта BF16/Q8_0 на маленьких данных, без исходных весов.
- [ ] **Нативный** MTP BF16/Q8_0 CUDA/CPU routed expert compute, без lossily converted Q2_0: типизированный формат экспертов, GPU kernels, VRAM расчёт, prefill, draft, quality semantics.
- [ ] Полное разделение четырёх реальных Unsloth MTP GGUF (BF16/Q8_0/shared-*); их истинная структура пока не проверялась, не допускать догадок о named tensors.
- [ ] Нативные Q6_K CPU/CUDA gate/up/down, dense, pack, prefill + полная числовая семантика.
- [ ] Нативный multi-shard Huihui Q8_0 и Unsloth Q8_0 (dense/expert/PLE/n-gram, loader, CUDA/CPU), без IQ4_NL fallback.
- [ ] Полная генерация pack для трёх RCO IQ3_S, Huihui Q8_0, Unsloth Q6_K.
- [ ] Полное Vision/mmproj, включая серверную подачу мультимодальных данных.
- [ ] Token-level constrained JSON Schema и Anthropic API.
- [ ] Остальные необходимые функции upstream Strata 0.1.41: патчами, без перезаписи архитектуры.
- [ ] Общая 100% кодовая реализация требований. Внешние тесты пользовательской машины не считать незавершённой кодовой задачей.
