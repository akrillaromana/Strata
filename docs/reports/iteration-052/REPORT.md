# Итерация 052 — интеграция исправленного Q6_K без отката defaults

## Источник

Интеграция выполнена трёхсторонне: опубликованный acceptor — итерация 050 / Git `3c10354`; база донора — `Strata-Fork-IQ3S-iteration-050(2).zip`; исправленный донор — `Strata-Fork-IQ3S-iteration-051(1).zip`.

Прямая замена донором не использовалась, потому что donor 050/051 содержал старые значения PCIe/MTP для существующих профилей и мог откатить уже опубликованный product default.

## Что интегрировано

- Q6_K исправлен на реальный пользовательский комплект из пяти `Qwen3.8-Flash-Next-Q6_K-00001-of-00005.gguf` ... `00005-of-00005.gguf`.
- Убрана исполняемая зависимость от ошибочного `UD-Q6_K_XL` / шестишардового профиля.
- Добавлен полный отдельный Q6 runtime: `engine-q6`, build/setup/prepare/start/verify/test/benchmark/tune/diagnostics.
- Добавлены три согласованные копии `strata-unsloth-q6_k-RAM.json`.
- Q6 preflight требует 5 шардов, routed experts Q6_K и PLE Q8_0.
- Выборочно интегрированы Q6_K MMQ/CUDA изменения и тест покрытия, без массовой замены форкового C++/CUDA.
- В существующие IQ3/Q4/Q8 launchers добавлена очистка только известных временных Q6 namespaces `R:\q6-model` и `R:\strata-runtime-q6`.
- Исторические Git publish-manifest итерации 050 сохранены; донорское удаление этих файлов не применено.

## Обязательные defaults сохранены

Во всех активных MTP JSON, включая новый Q6_K:

- `pcie-frac = 0.26`;
- `spec-min-p = 0.9`.

Donor-значения `pcie-frac=0` и старые MTP `0.5/0.75` не перенесены в существующие профили. Main/SYCL engine defaults также остаются `0.26 / 0.90`. Autotune может явно выбрать другое значение, а MTP=1.0 остаётся в tune-grid.

## Проверки

- 25/25 активных MTP JSON: `pcie-frac=0.26`, `spec-min-p=0.9`.
- 48/48 целевых Python-тестов: Q6 launch bundle, personal model inventory, model autotune, calibration, personal profiles.
- Q6↔Q8 argument parity подтверждён после нормализации model-specific путей.
- В текущих Q6 launch/preflight/config файлах нет `00006`, `UD-Q6` или `Q6_K_XL`.
- Python compile для Q6 preflight/test и затронутых autotune/calibration тестов проходит.

## Что требует Windows/GPU

Отдельный `engine-q6\strata.exe` ещё должен быть реально собран и запущен на пользовательской Windows/CUDA машине. Аппаратный READY до `VERIFY-Q6-API.ps1` не заявляется.
