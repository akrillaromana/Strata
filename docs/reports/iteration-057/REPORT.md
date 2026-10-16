# Итерация 057 — merge 052(3)–056 поверх опубликованной 052

Дата: 2026-10-16.

## База и метод

GitHub-база: `da25220` (iteration 052). Donor-цепочка: пользовательские полные архивы 052(3), 053, 054, 055, 056.
Для конфликтующих файлов использован трёхсторонний merge с общим предком iteration 051: опубликованная 052 — acceptor, 056 — donor.
Это сохраняет уже опубликованные исправления 052 и применяет накопленные donor-изменения 052(3)–056.

## Интегрировано

- Q8 CPU/CUDA expert parity infrastructure и opt-in `--expert-parity cuda`.
- Web runtime tuning PCIe/MTP с engine ACK.
- Live `TUNE pcie_frac=... spec_min_p=...` меняет resident scheduler в RAM без рестарта.
- `request_tune=2`, `live_tune=1`, ответ `TUNED ...`, per-request DONE ACK и PCIe offload metric.
- Model/run JSON остаются immutable: POST `/config` запрещён, `runconfig.save()` fail-closed.
- Saved model-autotune применяется только при явном `"autotune": true`.
- Новый стандарт RAM-диска R: 54 GiB; существующий том автоматически не форматируется/не уменьшается.
- Runtime-tune build/verify scripts и браузерные/серверные regressions из 053–056.

## Сохранённые обязательные defaults

Во всех 25 активных MTP JSON/example-конфигах:

- `--pcie-frac 0.26`;
- `--spec-min-p 0.9`.

Launcher defaults также сохранены на 0.26/0.9. Python calibrator fallback выровнен на 0.26/0.9. Calibration grids сохраняют крайнее MTP=1.0; Web/runtime tuning и явная калибровка могут временно выбирать иные значения без записи model JSON.

## Merge policy

- Опубликованные `docs/reports/iteration-050/*` и `iteration-052/*`, включая Git publish/delete manifests, не удалялись и не заменялись альтернативной историей donor-ветки.
- В конфликте `tools/test_model_autotune.py` объединены обе стороны: donor explicit opt-in (`autotune=True`) + product default `spec-min-p=0.9`.
- Q8 launcher получил donor parity/54-GiB/immutable-autotune изменения, сохранив product defaults 0.26/0.9.

## Проверки

- `python -m py_compile` для server/runconfig/calibrate/runtime-tune targets — OK.
- `node --check serve/web/app.js` и `runtime_tune.js` — OK.
- `node serve/web/test_runtime_tune.js` — OK.
- 60 targeted Python tests: calibrate/autotune/Q8 parity/Q6 bundle/personal models/runtime-tune source/runconfig — 60/60.
- 29 server tests: sampling/runtime tune ACK/control/shared settings/usage — 29/29.
- `serve/test_runtime_tune_browser.py` — Chromium OK.
- PERSONAL↔mirror launcher identity: 5/5 pairs byte-identical.
- Active config defaults: 25/25 = PCIe 0.26 / MTP 0.9.
- Static runtime-tune source contract: `request_tune=2`, `live_tune=1`, `TUNED`, live scheduler values — OK.

## Не заявляется

Windows/CUDA engine этой итерации в Linux-контейнере не собирался. Q8 CPU↔CUDA bitwise parity остаётся opt-in и не считается доказанным до аппаратной проверки на пользовательской RTX 3060.
