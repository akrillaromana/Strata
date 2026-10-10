# Задачи после итерации 019 — кодовая часть

- [x] МTP BF16 dense из исходных GGUF побайтово, независимо от Q8_0, включая fc/attention/shared gate/up/down без Q8-переквантования в native runtime.
- [x] Обратная совместимость с lossy Q2_0 MTP runtime и его Q8_0 dense; проверка точной геометрии перед загрузкой.
- [ ] Действительный формат и взаимодействие **shared** BF16/Q8_0 MTP GGUF с обычными MTP весами; без реальных GGUF не предполагать, что shared-only содержит routed experts.
- [ ] CUDA оптимизация native BF16/Q8_0 MTP и полная проверка иных маршрутов drafter / multi-token для всех layouts.
- [ ] Full native Unsloth Q6_K gate/up/down/dense/pack/prefill, multi-shard; полная Huihui/Unsloth Q8_0 с собственной Q8 PLE и n-gram; корректность всех трёх личных RCO IQ3_S.
- [ ] Vision/mmproj end-to-end, токенный JSON Schema-constrained decoding, Anthropic API и недостающие UI/runtime настройки.
- [ ] Доработки из Strata 0.1.41: conversation_file, VMM/DMA, expert swap, spec_prob, CUDA/AVX2/HIP/SYCL и стабильность concurrency.

Сборки CUDA и реальные GPU прогоны по требованию владельца **не выполнялись**. Их отсутствие не является выполненной или невыполненной задачей кодовой части. Отсутствующие функции кода не отмечать как завершённые.
