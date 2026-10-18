# CONTINUE PROMPT — Strata Fork iteration 059

Полный проект после iteration 058 + новых пользовательских defaults и исправления Windows launcher bootstrap. Текущий полный архив: `Strata-Fork-IQ3S-iteration-059.zip`, без дополнительной верхней папки.

## Итерация 059 — новые defaults + parallel ON + launcher dependency repair

- Новый обязательный product default для всех активных MTP-профилей и embedded launcher/setup/engine fallback: `--pcie-frac 0.09`. Явный user/runtime/autotune override по-прежнему имеет приоритет и model JSON не переписывается.
- MTP остаётся включённым с product default `--spec-min-p 0.9`; `1.0` остаётся в calibration grid.
- Настоящая engine parallelism включена по умолчанию как `parallel: 2`, то есть server добавляет `--batch 2`. Явное `parallel: 1`/`--parallel 1` отключает её; larger values остаются пользовательским override.
- Все 25 активных MTP JSON (root, PERSONAL_START, q4-local-profiles, native-high-quant examples) проверены на `0.09 / 0.9 / parallel=2`.
- `setup.py` теперь создаёт новые configs с `0.09 / 0.9 / parallel=2`; direct main/SYCL engine fallback `pcie_frac` = `0.09`; calibration reset default = `0.09 / 0.9`.
- Исправлен Windows запуск после upstream 0.1.45: `serve/frontend.py` требует `jinja2`, но старая `.venv` могла не содержать его. Общий launcher теперь до тяжёлой подготовки R: проверяет imports `jinja2`, `regex`, `yaml`, `requests`, `PIL`, `psutil`, `jsonschema`, `referencing`; при необходимости восстанавливает pinned packages из `requirements.txt` через текущий `.venv` Python и повторяет probe.
- Dependency repair подключён к Q4/Huihui/Q6/Q8/IQ3 launchers. Также процесс-guard учитывает отдельный `engine-q6\strata.exe`.
- В PowerShell 7 bare `START-Q4-K-XL.bat` из текущего каталога всё равно требует `./`/`.\` по штатному Command_Precedence PowerShell. Project-side BAT не может перехватить команду до своего запуска. Использовать `.\START-Q4-K-XL.bat`; реальная ошибка после запуска (`ModuleNotFoundError: jinja2`) устранена bootstrap'ом.
- Неприкосновенные правила 058 сохраняются: immutable model JSON, live `TUNE/TUNED`, Q6 separate engine, 54 GiB R:, no SHA runtime file identity, Q8 parity opt-in, upstream 0.1.45 API/hardening/sm_86 backports.

## Проверка 059

- `tools.test_iteration059_defaults`: 4/4 OK.
- defaults/setup/autotune/profile targeted suite: все связанные тесты OK; полный `test_setup_golden` сохраняет два ранее известные отказа только для UD-Q4_K_XL на 32/47 GiB RAM из-за штатного требования >=48 GiB.
- `serve.test_parallel.ParallelArgs` и первые concurrent/recovery service cases прошли; длинный общий parallel suite был остановлен лимитом окружения, не assertion failure.

---

Полный проект после selective backport нового upstream Strata 0.1.45 поверх опубликованной iteration 057 (`0c1a09f`). Текущий полный архив: `Strata-Fork-IQ3S-iteration-058.zip`, без дополнительной верхней папки.

## Неприкосновенные defaults и правила

- Во всех активных пользовательских MTP-профилях и launcher defaults: `--pcie-frac 0.26`, `--spec-min-p 0.9`. Web/runtime override и явная autotune-калибровка могут временно выбрать другое значение, но не переписывают model JSON.
- `MTP=1.0` всегда остаётся в calibration grid.
- Пользовательские model JSON immutable/read-only. Runtime создаётся только как generated JSON в `logs/...`; POST `/config` запрещён.
- Saved model-autotune применяется только при явном `"autotune": true`.
- RAM-диск `R:`: новый стандарт 54 GiB; существующий том автоматически не форматировать и не уменьшать.
- Q6: только пятишардовый `Q6_K`, отдельный `engine-q6`.
- Runtime Web tuning использует engine `TUNE`/ACK и должен показывать success только после подтверждения движка.
- Q8 CPU/CUDA parity остаётся opt-in до аппаратного подтверждения; не объявлять parity доказанным без RTX 3060 test.
- Не вычислять SHA для runtime model/pack comparisons; identity = точное имя + точный размер. SHA допустим только для проверки доставочного ZIP перед GitHub-публикацией.
- Пользователь сам распаковывает возвращённый ZIP в `E:\ai\Strata-Q4-Fork`; команды поиска/выбора/распаковки runtime-архива не давать.


## Итерация 058 — selective upstream Strata 0.1.45 backport

- Upstream donor: `Strata-main(5).zip`, project version 0.1.45. Основа форка остаётся custom 0.1.39 + выборочные backport'ы; CMake version не выдаётся за полный upstream 0.1.45.
- Server/API переведены на новый 0.1.45 контракт с сохранением custom слоёв: immutable model JSON, live `TUNE`/`TUNED`, system prompts, Web reasoning-budget bridge, Prometheus/backlog.
- Добавлены hard reasoning budgets/answer-room, config-level reasoning effort на OpenAI/Anthropic/Responses, model-card sampling, `logit_bias`, chunked/body/request hardening, context-overflow contract, новые tool-call/parser fixes.
- Добавлены optional control modules: cache drop, CPU affinity, keep-awake, replicas, session-save retry, image/vision elastic helpers. Они не включают опасные режимы автоматически.
- Web до изменения Sampling не шлёт sampling tuple и позволяет model-card defaults; пользовательские extended sampling настройки сохранены.
- Structured output остаётся stricter than upstream: schema-mode fail-closed без `jsonschema`, лимит 64 KiB/32 уровней, никакого извлечения JSON из Markdown/prose; добавлена поддержка object-only root unions и Responses final-answer + tools.
- CUDA: backport wide dequant для Q4_K/Q5_K/Q6_K/IQ4_XS/Q8_0; upstream default включает его на sm_86 (RTX 3060/A4000), `STRATA_DEQUANT_WIDE=0` отключает. Реальная CUDA/Windows сборка должна быть проверена на пользовательской RTX 3060 перед заявлением фактического ускорения.
- Parallel: настоящий engine `--batch N` уже был в 057 (2..8 concurrent slots). 058 backport'ит более новый server slot/recovery/group admission. Полный C++ `--batch-mtp`/multi-GPU >8-slot engine path НЕ импортирован в этой итерации: слишком широкая замена engine конфликтует с custom Q6/Q8/runtime-tune. На одной RTX 3060 parallel остаётся opt-in.
- Неприкосновенные defaults подтверждены: все 25 активных MTP JSON имеют `--pcie-frac 0.26` и `--spec-min-p 0.9`; static JSON приложение не переписывает.

## История donor 053–056

# Итерация 056 — реальный Web PCIe + неизменяемые model JSON

- Полный следующий архив: `Strata-Fork-IQ3S-iteration-056.zip`; база — 055.
- Главный bugfix: Web Apply теперь вызывает engine control command `TUNE`, а engine немедленно меняет `drive.d.pcie_num`/split scheduler в RAM. `INFO` capability: `request_tune=2 live_tune=1`; успешный ответ: `TUNED <pcie> <mtp> <pcie_num>`.
- Web не имеет права сообщать success без ACK; под ответом показывается `PCIe offload N entries` из DONE, поэтому фактическое изменение scheduler проверяем по работе, а не по echo.
- `VERIFY-RUNTIME-TUNE.ps1` исправлен от PowerShell `$CfgPath:` parser bug и проверяет PCIe=0 -> 0 offload, PCIe=1 -> больше offload, затем восстанавливает исходное runtime значение.
- Любой пользовательский model JSON — immutable runtime source. Web POST `/config` запрещён (405), `runconfig.save` fail-closed, launchers создают только `logs/.../runtime-*.json`.
- Saved `model-autotune` больше не применяется по умолчанию: только если в пользовательском JSON явно стоит `"autotune": true`. Это не позволяет калибровке молча заменить `--pcie-frac`/`--spec-min-p`, записанные пользователем.
- SHA не вычислять. Identity файлов = точное имя + точный размер.
- R: = 54 GiB. Q6 = только Q6_K, 5 шардов. MTP grid всегда содержит 1.0.
- CPU/CUDA parity остаётся отдельной незавершённой задачей и не блокирует runtime tuning.

## Первый Windows-тест 056

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
Set-Location "E:\ai\Strata-Q4-Fork"
& ".\BUILD-RUNTIME-TUNE-ENGINE.ps1"
& ".\START-Q8-RAM.ps1"
```

После READY во втором PowerShell:

```powershell
Set-Location "E:\ai\Strata-Q4-Fork"
& ".\VERIFY-RUNTIME-TUNE.ps1"
& ".\tools\TEST-CONFIG-IMMUTABILITY.ps1"
```

---

# Итерация 055 — Web PCIe/MTP live tuning: engine ACK обязателен

- Web больше не имеет права считать отправленный `strata_tune` применённым без подтверждения работающего engine.
- Новый engine сообщает `INFO ... request_tune=1` и в `DONE` дописывает реально разобранные `pcie_frac/spec_min_p`.
- Server возвращает `strata_tune_requested`, engine-ACK `strata_tune` и `strata_tune_applied`.
- Старый engine => `runtime_tune_supported=false`; Web controls отключены и показывают `engine rebuild required`.
- `BUILD-RUNTIME-TUNE-ENGINE.ps1/.bat` собирает и устанавливает обычный текущий engine БЕЗ parity gating. Это намеренно: parity 052 на реальной RTX 3060 не прошёл и не должен блокировать live tuning.
- `VERIFY-RUNTIME-TUNE.ps1/.bat` проверяет PCIe 0.00 и 1.00 на одной загруженной модели без рестарта и требует ACK engine.
- `TUNE-MODEL.ps1` и `tools/calibrate.py` теперь отклоняют результаты, если runtime tune не подтверждён engine.
- Добавлен `serve/test_runtime_tune_browser.py`: браузерная регрессия проверяет, что PCIe/MTP override действительно уходит в `strata_tune` и что UI показывает только ACK движка.
- CPU/CUDA parity НЕ считать готовым: пользовательский parity test дал 3966/7680 bitwise differences, и защитный build не установил тот exe.
- RAM-диск R: остаётся 54 GiB.
- SHA НЕ вычислять. Идентичность файлов по пользовательскому правилу: точное имя + точный размер.
- MTP=1.0 всегда оставлять в calibration grid.

# CONTINUE PROMPT — Strata Fork после итерации 054

## Текущее состояние

Полный архив: `Strata-Fork-IQ3S-iteration-054.zip`.
Основа: полный проект итерации 053. Никакой дополнительной верхней папки в ZIP.

## Что сделано в 054

Пользователь уменьшил целевой AWE RAM-диск `R:` с 64 GiB до **54 GiB**. Причина: после полного запуска Q8_0 на прежнем 64-GiB R: оставалось примерно 11 GiB свободно; 54 GiB оставляет примерно 1 GiB фактического запаса и освобождает около 10 GiB системной RAM.

Реализовано:

- `STRATA-MODEL-LAUNCH-COMMON.ps1` создаёт новый AIM AWE R: через `-s 54G` вместо `64G`.
- Минимальная проверка размера тома — `53GB`, чтобы номинальный 54-GiB NTFS том не отклонялся из-за служебной ёмкости/округления.
- Прямые IQ3_S запускатели и их PERSONAL/mirror копии также создают 54G и принимают >=53 GiB.
- Q4/Huihui/Q6/Q8 вторичные проверки приведены к тому же порогу.
- Q8 capacity reserve снижен с 2 GiB до 0.5 GiB: иначе фактический Q8 runtime, который на машине пользователя занимает около 53 GiB, мог бы быть искусственно отклонён на 54-GiB R:.
- Уже подключённый старый 64-GiB R: **не отцепляется, не форматируется и не уменьшается автоматически**. Появляется предупреждение. Пользователь должен один раз отключить старый RAM-диск своим обычным способом; следующий запуск создаст 54 GiB.
- Добавлена регрессионная проверка в `tools/TEST-MODEL-LAUNCHERS.ps1`: активные запускатели не должны снова содержать старые `-s 64G` / `Size -lt 60GB`.
- Пользовательские JSON не изменялись.
- SHA не вычислялись; политика идентичности файлов остаётся имя + точный размер.

## Следующий тест пользователя

После распаковки 054:

1. Если R: всё ещё старый 64 GiB, отключить его один раз обычным способом владельца.
2. Запустить нужный профиль, например `START-Q8-RAM.ps1`.
3. В логе должно быть создание `54 ГиБ AIM AWE`; после загрузки Q8 проверить `Get-PSDrive R` — ожидается примерно 1 GiB свободного места (фактическое значение зависит от pack/MTP/runtime данных).

## Важные правила проекта

- Не удалять/не форматировать существующий R: автоматически ради изменения размера.
- Пользовательские JSON read-only.
- SHA для файлов не вычислять; идентичность = имя + точный размер.
- `MTP=1.0` всегда входит в сетку калибровки.
- Q6 называется только Q6_K, пять шардов; стартовые параметры совпадают с Q8_0 кроме модельно-зависимых путей/engine.
- Web runtime tuning PCIe/MTP из 053 сохраняется.
- CPU↔CUDA parity из 052 остаётся opt-in до аппаратного подтверждения.

---

# CONTINUE PROMPT — Strata Fork после итерации 053

## Текущее состояние

Полный архив: `Strata-Fork-IQ3S-iteration-053.zip`.
Основа: полный проект итерации 052. Никакой дополнительной верхней папки в ZIP.

## Что сделано в 053

Пользователь попросил реализовать всё ранее предложенное для Web UI: менять `pcie_frac` и MTP (`spec_min_p`) без перезапуска модели перед каждым запросом.

Реализовано:

- Web Settings -> `Runtime speed tuning`.
- PCIe frac 0..1, step 0.01, точное numeric поле.
- MTP threshold/spec_min_p 0..1, step 0.01, включая 1.0.
- У каждого параметра checkbox `Default from model config`.
- Отображение `Model: <value>` для фактических стартовых аргументов resident engine.
- `Reset` возвращает оба runtime tuning параметра к model defaults.
- `Apply` сохраняет overrides только в браузере (`strata.runtimeTune`).
- Run-config JSON не меняется.
- Runtime tuning намеренно НЕ передаётся в shared defaults (`POST /settings`) для других клиентов.
- Перед каждым Web chat request активные overrides уходят как `strata_tune`.
- `GET /settings` отдаёт `model_tune`.
- Финальный Chat response/SSE chunk отдаёт `strata_tune` — effective values.
- Web сохраняет финальный `timings` и под ответом выводит PCIe/MTP/Prefill/Decode.

Изменённые файлы:

- `serve/server.py`
- `serve/test_server.py`
- `serve/web/index.html`
- `serve/web/app.js`
- `serve/web/app.css`

Добавлены:

- `serve/web/runtime_tune.js`
- `serve/web/test_runtime_tune.js`
- `docs/reports/iteration-053/*`

## Backend contract

У Strata уже был per-request контракт:

```json
"strata_tune": {
  "pcie_frac": 0.2,
  "spec_min_p": 0.9
}
```

`StrataEngine.sampling_keys()` передаёт их в текущий GEN request, то есть resident model не перезапускается.

В 053 добавлено:

- `tune_defaults_from_args()` — читает фактические стартовые `--pcie-frac/--spec-min-p` из `engine.spawn[1]`.
- `Service.model_tune_defaults`.
- `GET /settings -> model_tune`.
- effective tune в final done payload -> OpenAI stream/non-stream `strata_tune`.

## Проверки

- Web JS syntax OK.
- Web tests: 56/56.
- Target server tests: 17/17.
- Полный `serve.test_server` был запущен, но превысил локальный timeout 120 s; до timeout явных FAIL не было. Не заявлять полный suite PASS.

## Важные правила проекта

- Пользовательские JSON не перезаписывать.
- SHA для больших файлов не вычислять; идентичность пользователь просит определять по имени + точному размеру.
- `MTP=1.0` всегда должен входить в сетку калибровки.
- Q6 модель называется только Q6_K, 5 шардов, не Q6_K_XL.
- Q6 стартовые настройки должны совпадать с Q8_0, кроме модельно-зависимых путей/имени/engine-q6.
- Следующая работа по parity: продолжить проверку Q8 CPU↔CUDA из 052, не обещать идентичность до реального RTX 3060 теста.

## Следующий пользовательский тест

После распаковки 053 пользователь один раз перезапускает сервер модели, затем открывает Web, Ctrl+F5, Settings -> Runtime speed tuning.
Проверить два последовательных запроса БЕЗ рестарта модели, например:

1. PCIe 0.00, MTP 0.90
2. PCIe 0.20, MTP 1.00

Под каждым ответом должны быть фактические значения и speeds.