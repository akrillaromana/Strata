# САМАЯ НОВАЯ ИТЕРАЦИЯ 020 — ПОЛНЫЙ ИСХОДНЫЙ ZIP (ожидает публикации)

- **Последний подтверждённый опубликованный GitHub HEAD:** `7ac3301` (итерация 019, получен из пользовательского вывода `git push`, локальная и origin ветки совпадают). Не повторять публикацию 001–019. Следующая публикация 020 должна проверять HEAD `7ac3301`, ветку `strata-v0.1.39-custom`.
- Полный архив `Strata-custom-v0.1.39-iteration020-FULL.zip`, дерево `Strata/`, полная история и персональные профили. Файловый manifest для переноса **только изменённых файлов**: `docs/reports/iteration-020/PUBLISH_019_TO_020.txt`; команды git/push выдавать прямо в чате, без `git add -A`, `git clean -fd`, удаления `tj` или `h origin strata-v0.1.39-custom`.
- **Кодовая функциональность 020:** новый `tools/mtp_shared_source.py`; `tools/mtp_original_rt.py` поддерживает необязательный `--shared-gguf` как явный источник ТОЛЬКО отсутствующих shared-expert gate/up/down и BF16 scalar gate. Три проекции обязательны для companion; проверяются точные имена, GGUF BF16/Q8_0 физическая геометрия и тип, отсутствие дубликатов/конфликтов, побайтовое совпадение при пересечении. Объединение после проверки источников происходит перед созданием runtime; обе mmap GGUFReader сохраняются; для Q2_0 преобразование всё ещё ТОЛЬКО через explicit lossy opt-in; native BF16/Q8_0 остаётся без переквантования. Политика записывает `origin_verified: false` — имя файла и форма не доказывают общее происхождение checkpoint.
- `data/personal_models.json` добавляет **две кандидатные** пары BF16/shared-BF16 и Q8_0/shared-Q8_0, сохраняя существующие 8 записей моделей и E:/R: пути. Реальные GGUF заголовки не предоставлены: shared-only файлы иной топологии честно отклоняются; не заявлять полной поддержки всех четырёх без физического анализа.
- Тесты в `tools/test_mtp_shared_source.py` на синтетических массивах; подробности `docs/reports/iteration-020/{REPORT,SHARED_COMPANION,TASKS,CHECKS}.md`. CUDA не собиралась, движок/модели не запускались, готовность всего кода не 100%.
- **Незакрытое P0:** всё ещё реальные схемы четырёх MTP GGUF и иные shared topology, полноценные Unsloth Q6_K/Huihui Q8_0, Vision/mmproj, token-level JSON Schema/Anthropic, API/UI настройки, портирование нужного функционала оригинала 0.1.41. Не откладывать кодовые задачи из-за отсутствия аппаратных испытаний.

---

## САМАЯ НОВАЯ ИТЕРАЦИЯ 019 — ПУБЛИКАЦИЯ ЕЩЁ НЕ ПОДТВЕРЖДЕНА

- **База:** подтверждённый `8f522b1` (018), `strata-v0.1.39-custom`. Следующая публикация 019 должна проверять HEAD `8f522b1`. Один полный ZIP `Strata-custom-v0.1.39-iteration019-FULL.zip` с полным деревом `Strata/`, списком только новых/изменённых файлов `docs/reports/iteration-019/PUBLISH_018_TO_019.txt` и отчётом.
- **Код MTP:** native исходные dense BF16 теперь побайтово сохраняются вместе с Q8_0 и допускаются в независимых C++/Python валидаторах. Проверка точных размеров `mtp_projection_geometry` до выделения GPU. `src/core/mtp.cpp` выбирает BF16 GEMV/Q8 MMVQ per projection fc/attention; `src/kernels/cuda/shared_expert.cu` поддерживает BF16/Q8 shared gate/up/down; ускоренный `src/prefill/prefill.cpp::draft_kv` при BF16 переключается на точный `MtpDrafter::prefill` с FP32 SwiGLU без дополнительного Q8_1 для BF16 down. Старый Q2_0 не изменяет свой dense Q8 формат. CPU тест `tests/cpu/mtp_dense_bf16_test.cpp`, Python `tools/test_mtp_dense_bf16.py`, новые docs.
- **Ограничения:** CUDA сборку/запуск не выполняли; проверка на реальных MTP GGUF (особенно shared-only) отсутствует. Кодовые задачи `docs/reports/iteration-019/TASKS.md` **открыты**: shared-only, end-to-end Q6_K, Huihui/Unsloth Q8_0 и родная Q8 PLE, RCO IQ3_S, vision/mmproj, JSON Schema token constraints, функции донора 0.1.41. Не писать 100% готовность.
- **Личные пути:** `E:\ai\Strata-Q4`, `E:\ai\Strata-data`, `E:\ai\models`, `R:`; BAT/PS1/JSON и `data/personal_models.json` сохранены и не копируются в персональную установку. Не трогать `E:` и файлы `?? tj`, `?? "h origin strata-v0.1.39-custom"` в локальном Git. Git-команды только в чате, без `git add -A`.

# Актуальное состояние — STRATA PERSONAL CUSTOM после итерации 018 (2026-10-10)

**ВСЕ разделы ниже — история, устаревшие номера HEAD/следующих итераций из них НЕ применять.**

- **Последняя реальная публикация пользователя:** итерация **017**, коммит `2946947` (`HEAD` и `origin/strata-v0.1.39-custom` совпадают). Из журнала пользователя подтверждено: `8adafd6..2946947`; отдельные 012/013 были вместе `f6d07a8`. **018 создана в ZIP, но не опубликована.** Следующая после публикации — **019**. Если пользователь даст лог Git push 018, обновить подтверждённый HEAD по журналу, не угадывать SHA.
- **Полный архив:** `Strata-custom-v0.1.39-iteration018-FULL.zip`, корень `Strata/`, включает предыдущие 001–017 и полный текущий исходный код, личные профили. `docs/reports/iteration-018/PUBLISH_017_TO_018.txt` — только новые/изменённые файлы; `REPORT.md`, `TASKS.md`, `CHECKS.txt` — ход работы и ограничения.
- **Новая кодовая возможность 018:** `tools/mtp_original_rt.py --experts native` (НЕ `--allow-lossy-expert-conversion`) сохраняет bit-exact BF16/Q8_0 `gate_up` и `down` routed экспертов из исходного MTP GGUF в `experts.bin`, строит строгий `experts.txt`. `include/strata/core/mtp_native_layout.hpp`, `tools/mtp_native_layout.py` и `tools/mtp_rt_validator.py` проверяют размеры, количество и форматы, не допускают Q2_0 downgrade. `src/core/mtp.cpp` распознаёт native-формат и переключает вызов в `src/kernels/cuda/mtp_native_experts.cu` с gate/up, SwiGLU, down GEMV, не требует преобразования routed experts в Q2_0. Legacy Q2_0 остаётся поддержан. `CMakeLists.txt` подключает CUDA source и CPU-only test. **Dense BF16, требующий Q8_0, всё ещё может квантизоваться; native относится к routed experts.** Shared-only GGUF, не содержащие оригинальные routed experts, НЕ считаются совместимыми без исследования их фактической схемы.
- **Проверки 018 в нашей среде:** 129/129 профильных Python, 55/55 JS, отдельный автономный C++ manifest test с `g++ -std=c++17 -Wall -Wextra -Werror`, NumPy CPU oracle gate/up/SwiGLU/down на исходных BF16/Q8_0 байтах. Полный CUDA-движок НЕ собирался, CUDA код НЕ исполнялся и реальный GGUF не подавался. Поэтому заявлять окончательную GPU/end-to-end совместимость/производительность нельзя; остаётся валидировать работу физического CUDA пути после завершения кода.
- **Не выполнены ещё по кодовой части:** GPU оптимизация native MTP и BF16 dense без дополнительного Q8; четыре MTP файла (обычные BF16/Q8 + shared BF16/Q8) без фактических байтов не должны смешиваться догадками; полная Q6_K gate/up/down/dense/prefill/pack, Huihui Q8_0 + Unsloth Q8_0 с оригинальной Q8 PLE, три RCO IQ3_S, Vision/mmproj, token-level JSON Schema/Anthropic, интеграции донора Strata 0.1.41, другие задачи `docs/reports/iteration-018/TASKS.md`. **Проект ещё НЕ готов на 100%.**
- **Персональные пути неизменны:** Git рабочая папка `A:\worklab\project\App\Strata\Strata`, ZIP рядом; **не трогать** `E:\ai\Strata-Q4`, `E:\ai\models`, `E:\ai\Strata-data`, RAM `R:`. Личные BAT/PS1/JSON в `PERSONAL_START_E_ai_Strata-Q4/` и зеркале `tools/windows/q4-local-profiles/`. 8 личных моделей в `data/personal_models.json`, RCO IQ3_S в `E:\ai\Strata-data\models\IQ3_S` — обязательна.
- **Текущая фаза — только исходники и публикации на GitHub.** Не предлагать пользователю сборку движка/CUDA, запуск весов на его компьютерах, копирование файлов в рабочие E:/R: до отдельного запроса. Автономные CPU/Python/Node проверки только в среде ассистента допустимы.
- **Публикация 018:** команды Windows PowerShell точечно в чате (не только в файлах), проверить HEAD `2946947`, ветку `strata-v0.1.39-custom`, SHA ZIP, все файлы манифеста, запрет посторонних stage, `git --no-pager -c core.whitespace=cr-at-eol diff --cached --check`, `git commit` и `git push`. Никогда не `git add -A` или `git clean -fd`. Не трогать `?? tj` и `?? "h origin strata-v0.1.39-custom"`.
- Донор `Strata-main(2).zip`: upstream **0.1.41**, только адресные патчи, не заменять основной исходник и профили целиком. README содержит предупреждение о сугубо персональном форке.

---

# САМОЕ СВЕЖЕЕ СОСТОЯНИЕ — STRATA CUSTOM ПОСЛЕ ИТЕРАЦИИ 017

- **Полный основной архив:** `Strata-custom-v0.1.39-iteration017-FULL.zip`, корень `Strata/`, все исходники и личные профили 001–017. Использовать его как основу следующей итерации.
- **Последний подтверждённый GitHub push:** коммит **`8adafd6`**, итерация **016**, ветка `strata-v0.1.39-custom` репозитория `https://github.com/akrillaromana/Strata`. **017 пока НЕ опубликована**. Вариант 012 не имел отдельного коммита и опубликован с 013 в `f6d07a8`; не пытаться публиковать старые итерации.
- **017 добавлена реальная работа с оригинальными MTP BF16/Q8_0 GGUF:** `tools/mtp_source_contract.py`, `tools/mtp_original_rt.py`, `tools/mtp_rt_validator.py`, `tools/test_mtp_original_source.py`. Исходные экспертные BF16/Q8_0 веса разбираются, затем **только с явным opt-in** преобразуются в Q2_0 expert runtime существующего CUDA drafter (ПОТЕРЯ КАЧЕСТВА, НЕ нативная поддержка), исходные Q8_0 dense блоки копируются без переквантования. Полный отчёт `docs/reports/iteration-017/REPORT.md` и `SOURCE_CONVERSION.md`.
- **017 проверено:** 119/119 Python, 55/55 JavaScript, 12/12 новых unit/integration mock tests. Не проводились GPU/CUDA build, GGUF-веса и пользовательские испытания. Статическая проверка Git staged перед выдачей архива.
- **Открыто:** настоящие нативные MTP BF16/Q8 CUDA эксперты, согласование обычных/shared файлов (не известно, содержат ли они routed experts), Q6_K, Huihui/Unsloth Q8_0, PLE end-to-end, mmproj vision, ограниченный JSON Schema токенный decoding, нужные интеграции из донора v0.1.41. Не объявлять 100% готовности. `docs/reports/iteration-017/TASKS.md`.
- **Машины/пути:** рабочий Git `A:\worklab\project\App\Strata\Strata`, ZIP рядом; рабочая модельная установка `E:\ai\Strata-Q4`, модели в `E:\ai\models` и `E:\ai\Strata-data`, RAM `R:` **не трогать**. Файлы запуска `PERSONAL_START_E_ai_Strata-Q4/` и `tools/windows/q4-local-profiles/` сохраняются. Восемь вариантов моделей и 31 предполагаемый shard в `data/personal_models.json`; отдельная RCO IQ3_S в `E:\ai\Strata-data\models\IQ3_S`.
- **Публикация:** каждый ZIP — полный; точечные PowerShell-команды `git add --` и `git commit/push` только в чате, не скрипт-файл. Строго не добавлять/удалять `?? tj` или `?? "h origin strata-v0.1.39-custom"`, никаких `git add -A` / `git clean`. Перед передачей проверить чистую базу 016, `git diff --cached --check`, SHA ZIP, набор путей из `docs/reports/iteration-017/PUBLISH_016_TO_017.txt`. Не менять рабочую установку и не запрашивать сборку или запуск моделей на пользовательских ПК до отдельного разрешения.
- **Лицензии/публичный README:** персональный форк предназначен исключительно владельцу и **не рекомендован** другим для запуска «как есть».

---

# ИСТОРИЧЕСКИЕ ЗАПИСИ НИЖЕ (содержат ранее актуальные Git-статусы, НЕ использовать их вместо раздела 017)

# САМОЕ СВЕЖЕЕ СОСТОЯНИЕ — STRATA CUSTOM, ПОСЛЕ ИТЕРАЦИИ 016

- **Исходная база:** `Strata-custom-v0.1.39-iteration016-FULL.zip` — ПОЛНЫЕ исходники 001–016, корень `Strata/`.
- **Подтверждённый последний GitHub push:** `baae31c` — итерация 015. Пользовательский лог показывает
  `baae31c (HEAD, origin/strata-v0.1.39-custom)` после `git push`. Итерация 016 пока НЕ опубликована.
- **Репозиторий:** https://github.com/akrillaromana/Strata , ветка `strata-v0.1.39-custom`,
  рабочий Git `A:\worklab\project\App\Strata\Strata`, ZIP рядом. Происхождение upstream v0.1.39,
  донор 0.1.41 — только избирательные патчи.
- **Новая 016:** `include/strata/core/mtp_manifest.hpp` (CPU-only строгие границы и типы MTP
  dense.txt), `src/core/mtp.cpp` вызывает его до выделения VRAM и проверяет experts.bin и cudaMemcpy;
  `tools/mtp_runtime_contract.py`, `tools/mtp_rt.py` не принимают BF16/Q8_0 MTP GGUF за Q2_0 packed runtime.
  Проверки: 15 C++ сценариев, 107 Python, 55 JavaScript. **Это НЕ означает готовности всех BF16/Q8 MTP**.
- **Список файлов публикации:** `docs/reports/iteration-016/PUBLISH_015_TO_016.txt` — 13 путей.
  При отправке в Git строго `git add -- <изменённый файл>`, проверять `git diff --cached --check`.
  **Не трогать** `?? tj`, `?? "h origin strata-v0.1.39-custom"`.
- **Пользовательская система:** профили хранятся в `PERSONAL_START_E_ai_Strata-Q4/` и
  `tools/windows/q4-local-profiles/` с абсолютными путями `E:\ai\...`, `R:\...`.
  Действующая установка `E:\ai\Strata-Q4` не должна затрагиваться.
- **Восемь вариантов:** alesha GSQ-RCO IQ3_S, SC117 GSQ-RCO IQ3_S, отдельный личный
  RCO IQ3_S в `E:\ai\Strata-data\models\IQ3_S`, Huihui Q4_K_XL/Q8_0,
  Unsloth Q4_K_XL/Q6_K/Q8_0; всего 31 ожидаемый шард; исходные четыре MTP GGUF,
  mmproj отдельно в `data/personal_models.json`.
- **Задачи:** `docs/reports/iteration-016/TASKS.md`. Ещё не готовы полная native Q6_K,
  Huihui Q8, MTP BF16/Q8/shared, vision, token-constrained JSON Schema и интеграция донора.
- **Строгий режим:** только правки исходников, проверки в нашей среде, полный архив каждой итерации
  и PowerShell-команды публикации прямо в ответе; НИКАКОГО запуска моделей, сборок CUDA/движка
  или работы на компьютерах владельца, пока он отдельно не запросит.

---

# ПРОДОЛЖЕНИЕ ПРОЕКТА Strata Custom — после итерации 015

**Верхний раздел актуализирован 2026-10-10. Читай его прежде старых заметок ниже.**

- GitHub `https://github.com/akrillaromana/Strata`, ветка `strata-v0.1.39-custom`. Последний подтверждённый push: **`fdfe831` (014)**. Новая 015 ещё НЕ опубликована. 012/013 были вместе одним коммитом `f6d07a8` — не повторять.
- Последний ПОЛНЫЙ базовый ZIP: `Strata-custom-v0.1.39-iteration015-FULL.zip`. Он включает 001–015. При продолжении начать именно с него, не терять персональные `PERSONAL_START_E_ai_Strata-Q4` и `tools/windows/q4-local-profiles`.
- Владелец приложил листинг `E:\ai\models` и требует поддержку КАЖДОЙ имеющейся модели; отдельная RCO IQ3_S расположена в `E:\ai\Strata-data\models\IQ3_S` и остаётся обязательной. Полная матрица восьми вариантов/31 предполагаемый shard в `data/personal_models.json` и `docs/reports/iteration-015/MODEL_MATRIX.md`. Имена 29 из этих GGUF явно присутствуют в листинге; 2 для отдельного RCO берём из существующего личного JSON.
- Модели: `alesha-pro` GSQ-RCO IQ3_S 2, `SC117` GSQ-RCO-abliterated IQ3_S 2, личный RCO IQ3_S 2, Huihui Q8_0 6, Huihui Q4_K_XL 4, Unsloth Q6_K 5, Unsloth Q8_0 6, Unsloth Q4_K_XL 4. Unsloth есть четыре MTP GGUF (BF16/Q8/shared), два mmproj; Huihui и RCO тоже имеют mmproj. **MTP GGUF не является каталогом runtime `--mtp`; mmproj не является готовой активированной vision моделью.**
- В 015 реализован `tools/personal_models.py`: read-only каталог и валидация всех нужных shard-имён, Q8 собственной PLE, количеств, split metadata; `tools/model_compat.py` ужесточён до C++-условий, полный Q8 PLE geometry `[160,320001536]`. Сам C++ `GgufModel::validate_split()` теперь отказывается от противоречивой повторной архитектуры и split.tensors.count между шардами. Автотесты `tools/test_personal_models.py`, `tools/test_model_compat.py`, `tests/cpu/model_split_metadata_test.cpp`.
- Эти исправления НЕ означают 100% готовности Q6_K, Huihui Q8_0, MTP и vision. Ни полноформатных весов, ни внешних GPU-запусков не выполнялось. Открытые задачи: `docs/reports/iteration-015/TASKS.md`.
- Фаза ТОЛЬКО исходники, полный ZIP, локальные офлайн-проверки, GitHub через **команды PowerShell прямо в ответе**. Никаких CUDA/Windows сборок, запусков моделей на машинах владельца, изменения `E:\ai\Strata-Q4` до его прямого запроса.
- Windows Git: `A:\worklab\project\App\Strata\Strata`; полные ZIP в `A:\worklab\project\App\Strata\`. Переносить только пути `docs/reports/iteration-015/PUBLISH_014_TO_015.txt`, запрет `git add -A`, `git clean`, добавления локальных `?? tj` и `?? "h origin strata-v0.1.39-custom"`. Включить `--no-pager` для выводов; перед выдачей ZIP проверить staged `git diff --check` на чистом снимке 014.
- Донор `Strata-main(2).zip` upstream 0.1.41 использовать только избирательно: все уникальные Q4/IQ3/Huihui и веб-функции нашего 0.1.39 сохранять.

---

# ПРОМТ ПРОДОЛЖЕНИЯ ПРОЕКТА — Strata Custom v0.1.39, после итерации 014

**Самодостаточная передача в новый чат.** Обязательно сначала прочитать весь файл, `docs/reports/iteration-011/{REPORT,TASKS,NATIVE_MANIFEST}.md`, `docs/reports/iteration-011/CHECKS.txt`, `docs/reports/iteration-010/{REPORT,TASKS,DONOR_AUDIT}.md`, полный `DONOR_FILE_MATRIX.tsv`, далее код и отчёты 001–009. Продолжение вести от последнего **полного архива** `Strata-custom-v0.1.39-iteration014-FULL.zip` (корень `Strata/`), не от последней ветки донора и не от нулевой базы.

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
- Второй Windows ПК: репозиторий `A:\worklab\project\App\Strata\Strata`. Полные ZIP рядом: `A:\worklab\project\App\Strata\`; рабочие отдельные распаковки `_DELIVERY_011\Strata` рядом с репозиторием.
- Первый Windows ПК с уже работающей Strata: `E:\ai\Strata-Q4`. Запрещено менять/запускать её в этой фазе.
- **Последний ПОДТВЕРЖДЁННЫЙ пользовательским логом Git push: `fdfe831` (итерации 012+013 объединены)**, ветка и origin совпадают. Последний log: `fdfe831`, `f6d07a8`, `ccccbd1`; локальные файлы `?? tj` и `?? "h origin strata-v0.1.39-custom"` вне Git-коммитов. Нельзя их удалять/добавлять без просьбы пользователя.
- **Итерации 012 и 013 уже опубликованы ВМЕСТЕ одним коммитом `f6d07a8`. Отдельного коммита 012 не было: ошибка `new blank line at EOF` остановила её публикацию, исправлена в 013. Итерация 014 уже опубликована коммитом `fdfe831`. Итерация 015 пока только в ZIP.** Не повторять предыдущие итерации.
- Исходники донора `Strata-main(1).zip` и **НОВЫЙ последний переданный `Strata-main(2).zip`**, где `project(strata VERSION 0.1.41 LANGUAGES CXX)`; (2) отличается от (1) удалением 11 экспериментальных файлов и правками 14 файлов, не является суперсетом.

## 2. Поэтапная история выполнения 001–014

- **001 / ba8b9d2:** фикс `src/core/native_dense.cpp` multishard Huihui GGUF, исходные частные Q4_K_XL/IQ3_S/Huihui-профили, server/web reasoning budget.
- **002 / da1fe89:** temperature/top-p/top-k/min-p, repetition/presence/frequency penalties, penalty_last_n, общие параметры и явные числовые элементы GUI/API.
- **003 / f08ad2f:** до 50 именованных браузерных sampling presets, импорт/экспорт и Apply.
- **004 / 7f179d5:** stop sequences для OpenAI/Anthropic/Responses streaming/nonstream, миграция presets.
- **005 / fb8b99b:** system prompt editor/templates и серверные политики `client`, `server`, `merge`.
- **006 / bb4b6ff:** мультиязычная логика отдельных чатов, удаление сообщения/ответа/пары/чата, Q8_0 PLE (строки 170 байт), экспериментальные CUDA-ветви Q6_K, изолированные профили Unsloth/Huihui.
- **007 / 6e79f25:** полный JSON backup/import чатов и вложений без потери текста/image data при переключении.
- **008 / 7d64b23:** UI Structured Output `Text/JSON object/JSON Schema`, editor, пресеты v3, обязательный серверный `jsonschema`, fail-closed без него. **Token-constrained native decoding отсутствует**, как и полноценное Anthropic Structured Output.
- **009 / e447d53:** native PLE key `IQ3_XXS/IQ4_XS`, Q8 PLE bounds-safe, запрет стихийного pack overwrite, локальный offline `tools/model_compat.py`, отрицательные проверки повреждённых shards/headers.
- **010 / 67290b9 (подтверждено):** из актуального донора 0.1.41 выбрано и адаптировано:
  1. `serve/prometheus.py` + `serve/test_prometheus.py`; `serve/server.py` расширен на GET `/metrics` с vLLM Prometheus text при соответствующем Accept или `?format=prometheus`, прежний JSON возвращается по умолчанию. Гистограммы собираются на финализации каждого запроса. Добавлены защита метрик от управляющих символов и finite checks.
  2. `tools/quantscope.py`, `tools/strata_inspect.py`, `tools/test_strata_inspect.py` и `data/gguf_fingerprints.json` — информация о квантованиях GGUF/safetensors, в том числе заголовки из HF/ModelScope; `setup.py --inspect SOURCE [VARIANT]` вызывает его без установки и модели. Вектор риска: не считать совпавший header доказательством полной GPU-поддержки Q6_K/Huihui Q8_0.
  3. `tools/test_quantscope_safety.py`: лимиты удалённого Range-read, string/array/tensor headers, label injection.
  4. `tools/donor_audit.py` + `tools/test_donor_audit.py` — воспроизводимый ZIP→ZIP SHA256 diff без распаковки; `docs/reports/iteration-010/DONOR_FILE_MATRIX.tsv` содержит 2505 уникальных путей, статусы `identical/changed/donor_only/custom_only`.
  5. `docs/reports/iteration-010/{REPORT,TASKS,DONOR_AUDIT,DONOR_FILE_MATRIX.tsv}` и обновлённые этот файл и README.
  6. Внутренние проверки: 68 Python unit тестов прежнего набора + 4 теста донорского ZIP-аудита + 55 JS — 127 проверок, без запуска GPU/модели. Не приписывать к ним внешние Windows тесты.

- **011 / ccccbd1 (GitHub подтверждён):** реальная защита native expert source при работе с нативными Q6_K/Q8_0 и multishard Huihui; исправление донорского TSV и Linux файлов телеметрии.
  1. `include/strata/kernels/cpu/native_layout_safety.hpp` + `tests/cpu/native_layout_safety_test.cpp`, цель CMake: проверяемое умножение размера native expert, диапазоны GGUF и безопасное имя shard (ни `..`, ни абсолютные/UNC пути); синтетический тест без модели.
  2. `src/kernels/cpu/expert_layout.cpp`: `native_experts.txt` v3/v4 строго проверяет версии/число экспертов, дубли слоёв, пропущенные или неполные оффсеты, оторванные поля и переполнения общей раскладки. Прежнее семантическое разбиение по трём ролям сохранено.
  3. `src/kernels/cpu/native_expert.cpp`: до обращения к ggml CPU traits проверка type ID и geometry; проверяемые размеры `gu_row * n_ff`, `down_offset`, суммарный expert blob. `src/core/expert_source.cpp`: валидирует `data_start <= file_size`, per-role span, границу физического файла до сложения смещений.
  4. `tools/donor_audit.py`, `tools/test_donor_audit.py`, `docs/reports/iteration-010/DONOR_FILE_MATRIX.tsv`: отсутствующий SHA теперь `-`, TSV всегда 5 колонок без trailing tab. **Не удалять TSV из предыдущей 010**: он перезаписан с эквивалентными статусами/известными хешами, меняется только пустое значение.
  5. `serve/telemetry.py` и `serve/test_telemetry_files.py`: закрытие handles `/proc/cpuinfo`, `/proc/stat`, `/proc/meminfo`, три новых unit-теста.
  6. `docs/reports/iteration-011/{REPORT,TASKS,NATIVE_MANIFEST}.md`, `docs/reports/iteration-011/CHECKS.txt`, `README_ITERATION_011.md`, обновлённый этот CONTINUE_PROMPT.
  7. **Локальные проверки 011**: 76/76 Python, 55/55 JS, standalone C++ safety = OK, 10/10 synthetic native manifest C++ parser; syntax C++ with `-DSTRATA_NATIVE_EXPERTS` = OK. Полная CUDA сборка не проводилась.
  8. Не делать вывод о том, что **полные** Q6_K/Huihui Q8_0 уже работают; эта итерация именно закрывает defects native expert path. Внутренняя компиляция полного CUDA движка невозможна без SDK (не часть пользовательской фазы).

## 2a. Итерация 012 — персональная синхронизация профилей (опубликована вместе с 013)

- Пользователь передал последний снимок персональной установки `Strata-Q4(2).zip` и потребовал сохранить **точные личные пути** E:/R:, не ориентироваться на сообщество. Это персональный форк, в README прямо сказано, что его не рекомендуется использовать как есть другим пользователям.
- **Итерация 012 опубликована только в совокупном коммите `f6d07a8` с 013. Полный актуальный источник — ZIP 014; исходники 012 входят в него.**
- Личные профили из `Strata-Q4(2).zip` синхронизированы в **`tools/windows/q4-local-profiles/` и побайтово одинаковом `PERSONAL_START_E_ai_Strata-Q4/`** (плоские BAT/PS1/JSON/зависимости, готовые для _позднего_ размещения в E:\ai\Strata-Q4). В этой фазе не переносить их на E:, не запускать модели.
- Q4_K_XL Unsloth и IQ3_S `.ps1` больше не стирают пользовательские sampling/repeat_stop_tokens/прочие серверные поля при пересоздании конфигурации, атомарная запись `.bak`; `--spec-min-p=0.75` совпадает с последними JSON. Huihui Q4_K_XL использует сохранение персональных sampling из нового архива вместе с прежней SHA-256 проверкой 46 GiB PLE и индекса пакета.
- Добавлены пропущенные исходные конфиги `strata-unsloth-q8_0.json`, `strata-unsloth-ud-q4_k_xl.json` и BAT `START-HERE.bat` (в персональной папке, не заменяет корневой upstream START-HERE). Для Q4 отдельного JSON исправлен ошибочно переданный как CLI `--reasoning_budget_tokens` (правильно серверное поле).
- Личный Q8 JSON использует `IQ4_NL` PLE, **не отвечает требованию полностью нативного Q8_0 n-gram**. Нативные Q6_K/Huihui Q8_0 также остаются открытыми задачами.
- Подробности: `docs/reports/iteration-012/{REPORT,PERSONAL_PATHS,TASKS}.md`. Автономная проверка `tools/windows/q4-local-profiles/test_personal_profiles.py` — 8/8. Полный Windows PowerShell/модель на машине пользователя ещё не испытывались; не называть гарантированно проверенными.
- От пользователя: все команды `git` и переноса только **в чат**, не в README. Публиковать только белый список файлов, не `git add -A`, не изменять локальные посторонние `?? tj` и `?? "h origin strata-v0.1.39-custom"`. Учитывать последнее реальное состояние коммита `ccccbd1`.

## 3. Разделение «новая версия донора» и «основа форка»

В `Strata-main(2).zip` 2422 файла, в полном 009 934. SHA-аудит: идентичных путей 22, одинаковых имён с изменённым содержимым 829, donor-only 1571, custom-only 83. **1415 donor-only из `bench/`** — результаты старых опытов, не функционал в runtime. Полная таблица `docs/reports/iteration-010/DONOR_FILE_MATRIX.tsv`; объяснения и порядок ревью в `DONOR_AUDIT.md`. Эта численность относится к источникам **до** интеграции 010.

Важные donor-only интеграции **впереди**: `conversation_file` (engine-level persistence), `vmm`, `dma_batch`, `exchange_storage`, `foresight_swap`, `spec_prob`, `draft_source`, `message_boundary`, CUDA WMMA/PDL, AVX2 kernels, AMD Strix defaults, Intel Arc SYCL, специальные endpoint hardening и надежность reasoning/batch. Их нельзя бездумно переносить только заголовками: протоколы, генератор и расположение памяти обновлены в доноре.

`Strata-main(2).zip` **откатил** относительно `(1)` SSD conversation cache и hot-RAM-promotions, в том числе `conversation_disk.cpp/.hpp` и `local_memory_plan`. Эти эксперименты НЕ следует автоматически считать пропущенными возможностями актуального донора.

## 4. Открытые задачи до полного покрытия (текущая фаза — только КОД)

Самые подробные файлы: `docs/reports/iteration-011/TASKS.md`, `docs/reports/iteration-010/TASKS.md`, `docs/reports/iteration-010/DONOR_AUDIT.md`, `docs/reports/iteration-009/TASKS.md`. Приоритеты:

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

1. В новом чате первым делом получить у пользователя результат **git push 011**, проверить, опубликована ли 011 и каким SHA, не повторять 010 (уже опубликована `67290b9`).
2. Взять из последнего `Strata-custom-v0.1.39-iteration011-FULL.zip` всю базу `Strata/`. Донор `Strata-main(2).zip` при наличии сравнивать через `tools/donor_audit.py` + `DONOR_FILE_MATRIX.tsv`. Если файлы в новой сессии недоступны, попросить архивы снова; не придумывать sandbox пути.
3. Следующая итерация **012** должна содержать **новые содержательные изменения** по оставшимся P0-кодовым возможностям (нативный Q6_K/Huihui Q8_0 end-to-end или зрелые связанные пути из 0.1.41), а не просто документы/тесты. Проверить, что `expert_layout.cpp` со строгим парсером сохраняет совместимость с существующими v3/v4 pack файлами. Проверять код через собственную среду, без запуска моделей на ПК пользователя.
4. Обязательно вернуть **полный ZIP** с деревом исходников и `CONTINUE_PROMPT.md`, обновить `docs/reports/iteration-012/` и список задач.
5. В **самом ответе** дать точные команды PowerShell для копирования **только изменённых файлов** из `_DELIVERY_012\Strata` в `A:\worklab\project\App\Strata\Strata`, явно проверив HEAD новой базы, индекс, отсутствие постороннего `tj`, `git add` только по белому списку и `git push`. Никаких ссылок на README как замену командам.
6. Статус «готовность 100%» разрешён только для конкретно ограниченного объёма итерации после внедрения и проверок; **общая полнота проекта пока не 100%**.

## 6. Принципиальные ограничения вывода

- Header-based fingerprint от донора и локальная наша проверка GGUF — диагностика, не доказательство правильности вычислений на GPU.
- Успешный unit-test на mock engine — кодовая регрессия, не внешний прогон модели.
- Архив 011 в ZIP включает полный исходный код + исходники старых итераций и матрицу сравнения; он не содержит бинарник движка, веса Q8/Q6, секреты или RAM-диск.
- Следовать запросу пользователя на завершение кода и публикацию GitHub до обсуждения любых сборок/испытаний.

## 2b. Итерация 013 — строго нативная Q8_0 PLE / n-gram (опубликована вместе с 012)

- База итераций 012+013 УЖЕ опубликована в GitHub, коммит `f6d07a8` из последнего пользовательского журнала. Исходный архив 013 содержит их обе, 014 продолжает эту базу. Никогда не повторять публикацию 012/013.
- **`Q8` обязан использовать СВОЮ таблицу n-gram:** в двух экземплярах `strata-unsloth-q8_0.json` удалена принудительная `--ple-gguf R:\q8-ple\Qwen3.8-Flash-Next-PLE-IQ4_NL.gguf`. Добавлена `--ple-require-type Q8_0`. Остальные личные пути `E:\ai\Strata-Q4`, `R:\q8-model`, `R:\strata-runtime-q8`, `R:\strata-runtime-q8\mtp` и параметры сохранены.
- `src/program/generate.cpp` автоматически ищет `per_layer_token_embd.weight` среди собственных GGUF-шардов `--native`; для Q8_0 проверяет type ID, shape `[160, 320001536]`, границы данных до и после открытия. Отсутствующая/чужая таблица вызывает ошибку: **никакой IQ4_NL fallback**.
- Существующий в `src/kernels/ngram.cpp` декодер Q8_0 считывает **170 байт на строку** (пять нативных GGUF Q8_0 блоков по 34 байта). `src/ngram/ple_reader.cpp` дополнительно защищён от переполнения диапазонов unbuffered чтения.
- Новый `tools/q8_ple_preflight.py` проверяет заголовки шардов и собственную Q8_0 таблицу без загрузки тензоров/запуска модели. Тесты в `tools/test_q8_ple_preflight.py`; `tools/windows/q4-local-profiles/test_personal_profiles.py` проверяет новые профили. 4 PS1 копии лишились trailing blank lines, что должно исправить ошибку Git в 012.
- **Внимание:** ни настоящих 6 Q8 GGUF-шардов, ни рабочей сборки E:\ai бинарника в этой фазе не проверяли. Пока нет оригинального Q8_0 PLE тензора в модели, запуск fail-closed. Это именно исправление кода/конфига, НЕ подтверждение производительности или полной поддержки Q8/Huihui.
- Полная документированная разница 011→013 и белый список файлов публикации в `docs/reports/iteration-013/PUBLISH_011_TO_013.txt`. 012+013 уже опубликованы коммитом `f6d07a8`; публиковать только 014, без `git add -A` и без захвата `tj` / `h origin strata-v0.1.39-custom`. Powershell-команды публикации всегда выдавать **в чате**, не ссылаться на README.
- Следующие P0: полная нативная поддержка Q8_0/Huihui Q8_0/Q6_K и оставшиеся возможности оригинала 0.1.41, строго без потери персональных Q4_K_XL/IQ3_S/Huihui профилей. Разделение фазы: сейчас меняем только код форка; никаких E:-операций, установки, сборки/запуска моделей до отдельного указания пользователя.

- **Проверки 013:** 8/8 GGUF preflight, 8/8 профили, 55/55 JS, 29/29 сервер Python, C++ CPU native 170-byte Q8 row, C++ PLE reader syntax; Git whitespace staging 53 путей, все OK. Полный CUDA executable не собирался.

## 2c. Итерация 014 — Q6_K CUDA down/MMVQ и Q8_0 provenance (опубликована `fdfe831`)

- Входное опубликованное состояние GitHub: **`f6d07a8`** (`strata-v0.1.39-custom`). 014 изготовлена из полного ZIP 013 и опубликована `fdfe831`; не повторять перенос 012/013/014.
- `src/kernels/cuda/iq_kernels.cu`: opt-in `STRATA_Q6K_EXPERTS` расширен с gate/up до down и MMVQ; `iq_row_bytes(14)` = блоки по 210 байт/256 значений, `sizeof(block_q6_K)==210` компиляционный assert. Сохранена исходная настройка OFF и требование `STRATA_MMQ_KQUANTS` из CMake.
- `src/kernels/native_grouped_parity.cpp`: включён Q6_K down в параллельные CUDA-сценарии; фактический GPU запуск этих сценариев не проводился.
- `src/program/generate.cpp` + `include/strata/artifact/native_ple_source.hpp`: собственная Q8_0 PLE обязана принадлежать именно одному из GGUF `--native`-шардов, отдельный файл с тем же Q8_0 type/shape не принимается; GgufModel проверяет дубли и split метаданные, testable filesystem-equivalent пути принимаются. Это дополнительная защита к Q8_0 PLE из 013.
- `tests/cpu/native_ple_source_test.cpp`, `tools/test_native_q6_cuda_contract.py`, расширение `tools/test_q8_ple_preflight.py`: проверки происхождения таблицы и регрессионные исходные контракты.
- `docs/reports/iteration-014/` содержит полный REPORT, TASKS, CHECKS и белый список `PUBLISH_013_TO_014.txt`. `README_ITERATION_014.md` — краткое описание. Все личные пути в Q4/IQ3/Huihui/Q8 профилях из 013 сохранены (профили не изменялись).
- Кодовая часть проекта **не 100% завершена**: полная Q6_K CUDA точность/сборка/metadata, Huihui Q8_0, native JSON Schema constrained decoding и оставшиеся функции донора 0.1.41. Полных GGUF-весов в ZIP нет.
- Полный актуальный архив: `Strata-custom-v0.1.39-iteration014-FULL.zip`; будущему чату начинать именно с него и этой секции. Публиковать **ТОЛЬКО изменения 014** в текущую ветку, никогда `git add -A`; команды выдавать в чате. Не изменять E: и не запускать модель на машинах пользователя.
