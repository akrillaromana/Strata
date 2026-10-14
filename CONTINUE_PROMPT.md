# CONTINUE PROMPT — Strata Fork iteration 052

Полный проект после итераций 001–052. Пользователь сам распаковывает ZIP в `E:\ai\Strata-Q4-Fork`; команды поиска/распаковки архива не давать. Каждый ответ с изменениями возвращает полный ZIP без верхней папки и обновляет текущие REPORT/TASKS/COMMANDS/CONTINUE_PROMPT.

## Неприкосновенные defaults

- Для всех активных MTP-профилей/запускателей product default: `--pcie-frac 0.26`, `--spec-min-p 0.9`.
- Явный пользовательский override или принятый autotune может временно выбрать другое значение; без override baseline возвращается к `0.26 / 0.90`.
- `TUNE-MODEL.ps1` продолжает тестировать MTP grid `0.3, 0.5, 0.7, 0.75, 0.9, 1.0`; наличие `1.0` не меняет default `0.9`.
- Root/PERSONAL JSON read-only для запускателей; runtime JSON создаются отдельно в `logs`.
- Для проверки пользовательских моделей/пакетов не использовать SHA: только точное имя и точный размер в байтах.

## Q6_K — исправление 051/052

Поддерживается именно `Qwen3.8-Flash-Next-Q6_K` из пяти GGUF: `00001-of-00005` ... `00005-of-00005`. Не добавлять к этому профилю `UD`/`XL` и не принимать шестишардовый набор. Model id: `qwen3.8-flash-next-unsloth-q6_k`.

Q6 использует отдельный `engine-q6\strata.exe`; основной `engine\strata.exe` IQ3_S/Q4/Q8 не заменяется. Native pack по умолчанию `E:\ai\Strata-data\packs\unsloth-q6_k`. Preflight требует 5 шардов, routed experts Q6_K и PLE Q8_0. PLE по умолчанию остаётся на исходном диске и подключается ссылкой; физическая копия на R: только через `-PleToRam`.

Три постоянных Q6-конфига называются `strata-unsloth-q6_k-RAM.json` (root/PERSONAL/tools mirror) и имеют baseline `pcie-frac=0.26`, `spec-min-p=0.9`, `spec=4`, `kv=int8`, `kv-resident=32768`, `resident-budget-gib=120`, `max-context=262144`.

Q6 инструменты: `BUILD-Q6-ENGINE.*`, `SETUP-Q6.bat`, `PREPARE-Q6.bat`, `START-Q6-K.bat`, `START-HERE Q6_K.bat`, `VERIFY-Q6.*`, `TEST-Q6.bat`, `BENCHMARK-Q6.bat`, `TUNE-Q6.bat`, `GET-Q6-DIAGNOSTICS.*`.

Существующие IQ3/Q4/Q8 запускатели при переключении могут удалять только известные временные `R:\q6-model` и `R:\strata-runtime-q6`; пользовательские/неизвестные файлы не удалять.

## Статус проверки

Кодовая интеграция Q6_K и статические/целевые тесты выполняются локально в итерации 052. Аппаратный READY Q6_K не заявлять до Windows CUDA-сборки, реального запуска и `VERIFY-Q6-API.ps1` на пользовательской машине.
