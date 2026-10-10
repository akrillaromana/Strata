# ПРОМТ ПРОДОЛЖЕНИЯ ПРОЕКТА — Strata Custom v0.1.39, после итерации 010

**Самодостаточная передача в новый чат.** Обязательно сначала прочитать весь файл, `docs/reports/iteration-010/{REPORT,TASKS,DONOR_AUDIT}.md`, полный `DONOR_FILE_MATRIX.tsv`, далее код и отчёты 001–009. Продолжение вести от последнего **полного архива** `Strata-custom-v0.1.39-iteration010-FULL.zip` (корень `Strata/`), не от последней ветки донора и не от нулевой базы.

## 0. Неизменяемые указания пользователя

1. Текущая фаза проекта — **ИСКЛЮЧИТЕЛЬНО завершение исходного кода и обновление GitHub**. Не предлагать пользователю компиляцию движка, CUDA/Windows/Linux/macOS-сборку, установку, запуск моделей, RAM-диск, настройку компьютеров, тесты на их машинах, пока пользователь отдельно не запросит переход к испытаниям. Внутренняя проверка синтаксиса, unit-тесты, mock HTTP и статический анализ исходного кода в собственной среде автора разрешены. Тестирование на машинах пользователя не входит в процент готовности **кодовой части**.
2. У каждой итерации — реально изменённая полная кодовая база, полный ZIP для передачи пользователю, подробный `CONTINUE_PROMPT.md` в корне, отчёты `docs/reports/iteration-NNN/`, список выполненного/невыполненного/рисков. Не утверждать «готовность общего проекта 100%», пока все требования не реализованы. Если итерация завершена, можно сообщать 100% только её объёма.
3. **Все** PowerShell-команды для применения архива, выборочного `git add`, проверки индекса, `git commit`, `git push` печатать **прямо в чате**, не требовать открывать `README_ITERATION_NNN.md`. Не повторять уже опубликованные итерации и не придумывать действия, которые пользователь выполнил ранее.
4. Не трогать действующую Strata-Q4 на `E:`; не включать GGUF-веса, движок `strata.exe`, RAM-диск или секреты в исходный Git.
5. В локальном Git у пользователя есть посторонний **неотслеживаемый** файл `tj` (`?? tj`). Его **НЕ УДАЛЯТЬ**, не `git add -A`, не `git clean -fd`. Выбирать для Git строго новые изменённые файлы итерации.
6. Особое требование — полностью нативные Q8_0 n-gram, Q6_K, Huihui Q8_0, поддержка старых частных Q4_K_XL/IQ3_S/Huihui Q4_K_XL и всех реально отсутствующих возможностей донорских архивов. Не путать header inspection, декодирование одной таблицы и полную кодовую совместимость модели.
7. Сохранить за основу **точный upstream tag v0.1.39**, не делать массовую замену на 0.1.41. Доноры лишь источники проверенных функций. Новые функции интегрировать только по согласованию всех слоёв (C++, CUDA, Python, JS, CMake, профили).

## 1. Где и как ведётся работа

- GitHub пользователя: `https://github.com/akrillaromana/Strata`.
- Ветка публикации: `strata-v0.1.39-custom` — default branch на GitHub.
- Исходный upstream commit v0.1.39: `a1641e9f77aacad4d201b53c8a7ae8fa21059ebb`.
- Второй Windows ПК: репозиторий `A:\worklab\project\App\Strata\Strata`. Полные ZIP рядом: `A:\worklab\project\App\Strata\`; рабочие отдельные распаковки `_DELIVERY_010\Strata` рядом с репозиторием.
- Первый Windows ПК с уже работающей Strata: `E:\ai\Strata-Q4`. Запрещено менять/запускать её в этой фазе.
- **Последний ПОДТВЕРЖДЁННЫЙ пользовательским логом Git push: `e447d53` (итерация 009)**, ветка и origin совпадают. Последний log: `e447d53`, `7d64b23`, `6e79f25`; локальный `?? tj` вне коммитов.
- **Итерация 010 есть только в этом ZIP и НЕ ПОДТВЕРЖДЕНА в GitHub.** После следующего пользовательского журнала `git push` обновить этот факт и реальный commit SHA. Не повторять команды 009.
- Исходники донора `Strata-main(1).zip` и **НОВЫЙ последний переданный `Strata-main(2).zip`**, где `project(strata VERSION 0.1.41 LANGUAGES CXX)`; (2) отличается от (1) удалением 11 экспериментальных файлов и правками 14 файлов, не является суперсетом.

## 2. Поэтапная история выполнения 001–010

- **001 / ba8b9d2:** фикс `src/core/native_dense.cpp` multishard Huihui GGUF, исходные частные Q4_K_XL/IQ3_S/Huihui-профили, server/web reasoning budget.
- **002 / da1fe89:** temperature/top-p/top-k/min-p, repetition/presence/frequency penalties, penalty_last_n, общие параметры и явные числовые элементы GUI/API.
- **003 / f08ad2f:** до 50 именованных браузерных sampling presets, импорт/экспорт и Apply.
- **004 / 7f179d5:** stop sequences для OpenAI/Anthropic/Responses streaming/nonstream, миграция presets.
- **005 / fb8b99b:** system prompt editor/templates и серверные политики `client`, `server`, `merge`.
- **006 / bb4b6ff:** мультиязычная логика отдельных чатов, удаление сообщения/ответа/пары/чата, Q8_0 PLE (строки 170 байт), экспериментальные CUDA-ветви Q6_K, изолированные профили Unsloth/Huihui.
- **007 / 6e79f25:** полный JSON backup/import чатов и вложений без потери текста/image data при переключении.
- **008 / 7d64b23:** UI Structured Output `Text/JSON object/JSON Schema`, editor, пресеты v3, обязательный серверный `jsonschema`, fail-closed без него. **Token-constrained native decoding отсутствует**, как и полноценное Anthropic Structured Output.
- **009 / e447d53:** native PLE key `IQ3_XXS/IQ4_XS`, Q8 PLE bounds-safe, запрет стихийного pack overwrite, локальный offline `tools/model_compat.py`, отрицательные проверки повреждённых shards/headers.
- **010 / ZIP, GitHub ЕЩЁ НЕ обновлён:** из актуального донора 0.1.41 выбрано и адаптировано:
  1. `serve/prometheus.py` + `serve/test_prometheus.py`; `serve/server.py` расширен на GET `/metrics` с vLLM Prometheus text при соответствующем Accept или `?format=prometheus`, прежний JSON возвращается по умолчанию. Гистограммы собираются на финализации каждого запроса. Добавлены защита метрик от управляющих символов и finite checks.
  2. `tools/quantscope.py`, `tools/strata_inspect.py`, `tools/test_strata_inspect.py` и `data/gguf_fingerprints.json` — информация о квантованиях GGUF/safetensors, в том числе заголовки из HF/ModelScope; `setup.py --inspect SOURCE [VARIANT]` вызывает его без установки и модели. Вектор риска: не считать совпавший header доказательством полной GPU-поддержки Q6_K/Huihui Q8_0.
  3. `tools/test_quantscope_safety.py`: лимиты удалённого Range-read, string/array/tensor headers, label injection.
  4. `tools/donor_audit.py` + `tools/test_donor_audit.py` — воспроизводимый ZIP→ZIP SHA256 diff без распаковки; `docs/reports/iteration-010/DONOR_FILE_MATRIX.tsv` содержит 2505 уникальных путей, статусы `identical/changed/donor_only/custom_only`.
  5. `docs/reports/iteration-010/{REPORT,TASKS,DONOR_AUDIT,DONOR_FILE_MATRIX.tsv}` и обновлённые этот файл и README.
  6. Внутренние проверки: 68 Python unit тестов прежнего набора + 4 теста донорского ZIP-аудита + 55 JS — 127 проверок, без запуска GPU/модели. Не приписывать к ним внешние Windows тесты.

## 3. Разделение «новая версия донора» и «основа форка»

В `Strata-main(2).zip` 2422 файла, в полном 009 934. SHA-аудит: идентичных путей 22, одинаковых имён с изменённым содержимым 829, donor-only 1571, custom-only 83. **1415 donor-only из `bench/`** — результаты старых опытов, не функционал в runtime. Полная таблица `docs/reports/iteration-010/DONOR_FILE_MATRIX.tsv`; объяснения и порядок ревью в `DONOR_AUDIT.md`. Эта численность относится к источникам **до** интеграции 010.

Важные donor-only интеграции **впереди**: `conversation_file` (engine-level persistence), `vmm`, `dma_batch`, `exchange_storage`, `foresight_swap`, `spec_prob`, `draft_source`, `message_boundary`, CUDA WMMA/PDL, AVX2 kernels, AMD Strix defaults, Intel Arc SYCL, специальные endpoint hardening и надежность reasoning/batch. Их нельзя бездумно переносить только заголовками: протоколы, генератор и расположение памяти обновлены в доноре.

`Strata-main(2).zip` **откатил** относительно `(1)` SSD conversation cache и hot-RAM-promotions, в том числе `conversation_disk.cpp/.hpp` и `local_memory_plan`. Эти эксперименты НЕ следует автоматически считать пропущенными возможностями актуального донора.

## 4. Открытые задачи до полного покрытия (текущая фаза — только КОД)

Самые подробные файлы: `docs/reports/iteration-010/TASKS.md`, `docs/reports/iteration-010/DONOR_AUDIT.md`, `docs/reports/iteration-009/TASKS.md`. Приоритеты:

### P0 нативные модели
- Native Q6_K end-to-end: GGUF/pack/loader/dense experts/CPU+CUDA dispatch/prefill/grouped/MTP. Opt-in CUDA kernels 006 ≠ полная поддержка.
- Native Q8_0 ngram и full Q8_0 включая Huihui abliterated Q8_0 shards, expert cache/resident, совместимость со всеми нужными типами тензоров; реальная модель не предоставлена — продолжать исходный код и регрессии без её запуска.
- Наши уникальные профили `IQ3_S`, Unsloth `Q4_K_XL`, Huihui `Q4_K_XL` должны остаться нетронутыми; устранять жесткие E:/R:-пути при обобщении. Дополнительные модели донора Swift/Coder/OrcaRouter и IQ варианты — ревизия по реальным kernels, не только по именам.

### P0 structured generation
- Полноценный C++/CUDA token-level constrained JSON Schema generation (не просто валидация готового ответа), корректная обработка stream/stop/budget/tools и Anthropic Structured Output.

### P0 GUI/API/runtime параметры
- Seed, CPU threads, context overflow, KV type/resident, MTP speculative depth/min-p, динамическое reason budget, loader/переключение моделей, приоритеты пресетов, реальные параметры по всем API.

### P1 донор 0.1.41
- Пофайловая интеграция `conversation_file`, VMM/DMA, expert planning, speculative probability, CUDA WMMA/PDL/AVX2, SYCL/AMD, endpoint hardening, batch/concurrency, с полноценной адаптацией CMake и тестами. Не заменять `src/program/generate.cpp` целиком.

### P1 Надёжность
- API/CORS/MCP/settings, безопасное хранение секретов, IndexedDB чатов и параллельные вкладки, pack integrity, полный модельный model_compat + quantscope межслойный аудит, устранение ResourceWarning в `serve/telemetry.py`.

Не закрывать задачи формулировками вроде «уже работает» без соответствующего кодового пути и синтетической проверки. Аппаратные испытания пользователь намеренно откладывает и они не входят в этот план.

## 5. Как продолжать работу

1. В новом чате первым делом получить пользователя результат **git push 010**, проверить, опубликована ли 010 и каким SHA, не повторять её, если опубликована.
2. Взять из последнего `Strata-custom-v0.1.39-iteration010-FULL.zip` всю базу `Strata/`. Донор `Strata-main(2).zip` при наличии сравнивать через `tools/donor_audit.py` + `DONOR_FILE_MATRIX.tsv`. Если файлы в новой сессии недоступны, попросить архивы снова; не придумывать sandbox пути.
3. Следующая итерация 011 должна содержать **новые содержательные изменения** по оставшимся P0-кодовым возможностям (Q6_K/Huihui Q8_0 или end-to-end функции из донора), а не просто новые документы или тесты. Проверять код через собственную среду, без запуска моделей на ПК пользователя.
4. Обязательно вернуть **полный ZIP** с деревом исходников и `CONTINUE_PROMPT.md`, обновить `docs/reports/iteration-011/` и список задач.
5. В **самом ответе** дать точные команды PowerShell для копирования **только изменённых файлов** из `_DELIVERY_011\Strata` в `A:\worklab\project\App\Strata\Strata`, явно проверив HEAD новой базы, индекс, отсутствие постороннего `tj`, `git add` только по белому списку и `git push`. Никаких ссылок на README как замену командам.
6. Статус «готовность 100%» разрешён только для конкретно ограниченного объёма итерации после внедрения и проверок; **общая полнота проекта пока не 100%**.

## 6. Принципиальные ограничения вывода

- Header-based fingerprint от донора и локальная наша проверка GGUF — диагностика, не доказательство правильности вычислений на GPU.
- Успешный unit-test на mock engine — кодовая регрессия, не внешний прогон модели.
- Архив 010 в ZIP включает только изменённый код + исходники старых итераций и матрицу сравнения; он не содержит бинарник движка, веса Q8/Q6, секреты или RAM-диск.
- Следовать запросу пользователя на завершение кода и публикацию GitHub до обсуждения любых сборок/испытаний.
