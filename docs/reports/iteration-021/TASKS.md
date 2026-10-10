# Оставшиеся кодовые задачи после 021

- [x] Единый строгий multishard `GgufModel` для native dense discovery и load; исключить частичный набор/неверное число тензоров перед загрузкой.
- [x] Корректные типы `U16`/`I32` из GGUF split, проверка повторяющихся metadata keys и ограниченная обработка повреждённых заголовков в C++ и Python.
- [ ] Полное end-to-end нативное Q6_K для всех ролей gate/up/down/dense/CPU-CUDA/grouped/prefill/pack; существующие opt-in исходные ядра не доказывают полную поддержку.
- [ ] Полное end-to-end Huihui Q8_0 и Unsloth Q8_0, включая шесть шардов, resident/expert routing, PLE original Q8_0 и n-gram; аппаратная совместимость не подтверждена.
- [ ] Проверить реальные заголовки четырёх MTP GGUF и два shared-only; реализация shared companion 020 сохраняется, для другой фактической топологии нужен отдельный путь.
- [ ] Vision/mmproj, token-level JSON Schema, Anthropic structured tools, недостающие параметры API/UI.
- [ ] Прицельно интегрировать оставшиеся нужные функциональные модули донора 0.1.41 (conversation file, VMM/DMA, speculative probability, swap, CPU/HIP/SYCL) после анализа архитектуры.

Не проводить сборку CUDA или запуск моделей на компьютере пользователя без его отдельной команды. Полная кодовая готовность ещё не 100%.
