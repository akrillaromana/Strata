# Остаток кода после 023

- [x] Единый preflight GGUF native dense, head, embedding до GPU/host allocations: полные Q6_K/Q8_0 shard families + физическая геометрия.
- [x] Защитить NativeEmbed от отрицательных/избыточных размеров, overflow произведения stride и словаря; guard single-token gather.
- [ ] Проверить реальную математику natively Q6_K gate/up/down, grouped expert, prefill/pack и правильность специальных CUDA opt-in путей; CPU-only и static tests не заменяют численные GPU тесты.
- [ ] Завершить native Huihui/Unsloth Q8_0 шестишардный путь, нативную Q8_0 PLE и собственный n-gram с сохранением персонального provenance.
- [ ] Реальные GGUF topology 4 MTP и 2 shared — нет заголовков/весов, не заявлять end-to-end совместимость.
- [ ] Vision/mmproj, token-constrained JSON Schema + Anthropic; оставшиеся сервер/API/UI фичи и функционал донора Strata 0.1.41.

Пользователь запрещал установку, сборку движка и запуск моделей на его ПК до отдельной команды. Выполнять только код и автономные проверки здесь. Кодовая готовность не 100%.
