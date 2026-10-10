# Оставшаяся работа после итерации 011 (только исходный код)

## P0: полноценное покрытие нативных моделей
- [ ] Полный native Q6_K end-to-end: типы плотных тензоров и экспертов, CPU `ggml`/CUDA пути, pack/loader/arena, MMQ/prefill, grouped, МТР/спекуляции; флаг `STRATA_Q6K_EXPERTS` пока опционален.
- [ ] Полная поддержка Q8_0-модели и Q8_0 n-gram на всех слоях: PLE-Q8 row есть с 006, но недостаточно для общей совместимости.
- [ ] Полная кодовая поддержка Huihui Q8_0 multishard: отдельная карта GGUF-тензоров, архитектура, tensor-name translation, per-role shard, собственные пакеты, sampling и memory. Без реальных весов нельзя подтвердить корректность полной модели.
- [ ] Не сломать Q4_K_XL, IQ3_S, Huihui Q4_K_XL и их раздельные локальные конфигурации.

## P0: другие функции
- [ ] Реальное native token-level JSON Schema constrained decoding (не поствалидация); streaming, stop, reasoning, все API, Anthropic Structured Output.
- [ ] Финализировать GUI/API/runtime настройки: контекст и overflow, MTP depth/min-p, KV formats/resident, seed, CPU threads, reasoning budgets, профили, модельный менеджер.
- [ ] Сверить отсутствующие семейства и GGML форматы последнего донора v0.1.41 по `docs/reports/iteration-010/DONOR_AUDIT.md` с проверкой полных путей, а не названий.

## P1: перенос возможностей донора 0.1.41
- [ ] `conversation_file`/снимки состояния генерации, связка с чатом без подмены browser export.
- [ ] VMM/DMA/exchange/foresight swap и резервирование памяти для больших экспертов.
- [ ] Probabilistic speculative decoding/MTP, математически корректные seed и sampling penalties.
- [ ] CPU AVX2, CUDA WMMA/PDL, SYCL/Intel Arc, HIP/AMD, CPU-only в платформенно изолированных слоях.
- [ ] Различные эндпойнты и управление: hardened requests, slots/concurrency, cancellation, fatal recovery, batch.

## P1: целостность
- [ ] Больше негативных синтетических тестов native `expert_layout_load` с объектным C++ parser (внутренние SDK-зависимости и целевой компилятор), тестов полноты GGUF-пакетов, не только header/арифметики.
- [ ] Безопасное и масштабируемое сохранение чатов (IndexedDB, изоляция нескольких вкладок, квоты, перенос вложений).
- [ ] Аудит новых URL/Range инструмента quantscope, экспертов и пакетов; исключить несогласованные источники разных модельных версий.
- [ ] Постепенная интеграция каждого реально нового runtime-модуля `Strata-main(2).zip`, без переноса 1415 файлов исторических бенчмарков как будто это функционал.

**Контракт продолжения:** только новая изменённая кодовая база, полный ZIP + корневой подробный `CONTINUE_PROMPT.md`. Все инструкции Git публиковать прямо в чате, в новый коммит только проверенный white-list; никогда не добавлять локальные `tj` и `h origin strata-v0.1.39-custom`. Никаких пользовательских сборок/тестов до отдельной команды.
