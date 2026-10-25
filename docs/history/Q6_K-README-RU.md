# Qwen3.8 Flash Next Q6_K — Windows

Итерация 051 поддерживает именно пользовательскую модель `Qwen3.8-Flash-Next-Q6_K` из пяти GGUF-шардов.

Фактический комплект модели:

- `Qwen3.8-Flash-Next-Q6_K-00001-of-00005.gguf`
- `Qwen3.8-Flash-Next-Q6_K-00002-of-00005.gguf`
- `Qwen3.8-Flash-Next-Q6_K-00003-of-00005.gguf`
- `Qwen3.8-Flash-Next-Q6_K-00004-of-00005.gguf`
- `Qwen3.8-Flash-Next-Q6_K-00005-of-00005.gguf`

Проверка split выполняется по GGUF-заголовкам, имени файла и точному размеру в байтах. SHA не вычисляется. Для этого профиля требуется routed-expert тип Q6_K и PLE типа Q8_0.

## Начальные настройки

Профиль `strata-unsloth-q6_k-RAM.json` по значениям параметров полностью повторяет текущий `strata-unsloth-q8_0.json`. Отличаются только Q6-специфичные пути, имя модели и отдельный `engine-q6\strata.exe`.

Начальные значения включают:

- `expert-cache=auto`
- `prefill=auto`
- `pcie-frac=0.26`
- `spec=4`
- `spec-min-p=0.9`
- `suffix-draft=0`
- `max-context=262144`
- `kv=int8`
- `kv-resident=32768`
- `resident-budget-gib=120`
- `adapt-every=0`
- `adapt-swaps=0`
- `prompt-cache=0`
- `ple-require-type=Q8_0`

Пользовательский JSON только читается. Во время запуска временный runtime JSON создаётся в `logs\q6`; исходный файл не переписывается.

## Команды

`SETUP-Q6.bat` — собирает отдельный Q6-движок и готовит native pack.

`BUILD-Q6-ENGINE.bat` — только сборка/проверка `engine-q6\strata.exe`.

`PREPARE-Q6.bat` — только подготовка/проверка Q6 native pack.

`START-Q6-K.bat` и `START-HERE Q6_K.bat` — запуск Q6_K.

`VERIFY-Q6.bat` — `/health`, `/v1/models` и короткая реальная генерация.

`BENCHMARK-Q6.bat` — измерение скорости уже запущенной модели.

`TUNE-Q6.bat` — подбор PCIe и MTP; сетка MTP включает `1.0`.

`TEST-Q6.bat` — шесть последовательных API-запросов.

`GET-Q6-DIAGNOSTICS.bat` — состояние отдельного Q6 engine, RAM-диска, API и последние журналы.

## RAM-диск

По умолчанию PLE-шард Q6_K не копируется физически на `R:`: в split namespace создаётся ссылка на исходный GGUF на E:. Это не меняет настройки движка и не создаёт вторую 50+ GiB копию данных внутри уже выделенного RAM-диска. Если физическая копия PLE на RAM-диск нужна, используется явный `-PleToRam`.

Q6 CUDA-сборка и реальный READY должны быть подтверждены на Windows/RTX 3060. Офлайновые тесты архива этого не доказывают.
