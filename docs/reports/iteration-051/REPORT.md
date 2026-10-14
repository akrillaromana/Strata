# Итерация 051 — исправление профиля Q6_K

## Причина

В итерации 050 был ошибочно создан профиль для несуществующего в пользовательском наборе варианта Q6_K с шестью шардами. Пользовательский набор подтверждён скриншотом каталога: `Qwen3.8-Flash-Next-Q6_K` состоит ровно из пяти GGUF.

## Исправлено

- Q6-профиль принимает только `Qwen3.8-Flash-Next-Q6_K-00001-of-00005.gguf` ... `00005-of-00005.gguf`.
- Модель API называется `qwen3.8-flash-next-unsloth-q6_k`.
- Постоянный конфиг переименован в `strata-unsloth-q6_k-RAM.json`; аналогично исправлены PERSONAL и зеркальная копии.
- Native pack по умолчанию хранится в `E:\ai\Strata-data\packs\unsloth-q6_k`.
- Preflight требует ровно 5 шардов, routed experts Q6_K и PLE типа Q8_0.
- Убраны ошибочные XL/UD-наименования Q6 из исполняемых профилей и текущей документации.
- Q6 launcher/verify/tune/RAM-artifacts используют только пятишардовое имя.

## Начальные настройки Q6_K

Параметры намеренно синхронизированы с текущим `strata-unsloth-q8_0.json` один в один. Отличаются только пути к Q6 runtime/model, `model_name`, `log` и отдельный `engine-q6\strata.exe`.

Значения: `expert-cache=auto`, `prefill=auto`, `pcie-frac=0.26`, `spec=4`, `spec-min-p=0.9`, `suffix-draft=0`, `max-context=262144`, `kv=int8`, `kv-resident=32768`, `resident-budget-gib=120`, `adapt-every=0`, `adapt-swaps=0`, `prompt-cache=0`, `ple-require-type=Q8_0`.

Пользовательский JSON остаётся read-only. Runtime-конфиг создаётся только в `logs\q6`.

## Проверка идентичности файлов

SHA не используется. Проверки копий модели/PLE/пакета выполняются по точному имени и точному размеру в байтах.

## Ограничение

Q6_K ещё должен быть собран и реально запущен на пользовательской Windows/RTX 3060. Итерация не объявляет аппаратный READY без этого результата.

## Проверки

- 73/73 целевых Python-теста Q6/model/native-pack/model-compat успешно.
- Q6/Q8 argument parity подтверждён: после замены только model-specific путей массивы `args` совпадают.
- Старые три конфигурации с ошибочным именем удалены и заменены тремя корректными `strata-unsloth-q6_k-RAM.json`.
- Активных SHA-вычислений в Q6 PowerShell/Python/BAT нет.
