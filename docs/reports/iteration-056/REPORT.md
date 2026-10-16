# Итерация 056 — реальный Web live PCIe + неизменяемые model JSON

## Причина

В 055 Web мог подтвердить только per-request значения, но кнопка Apply не меняла активный expert scheduler resident engine немедленно. Кроме того, runtime `/config` всё ещё имел исторический write-path, что противоречит правилу проекта: пользовательские model JSON никогда не переписываются программой.

Пользовательский Windows-лог также показал отдельную ошибку `VERIFY-RUNTIME-TUNE.ps1`: PowerShell разбирал `$CfgPath:` как недопустимую переменную. Сам запуск Q8 уже использовал отдельный `logs\\q8\\runtime-*.json`, а исходный `strata-unsloth-q8_0.json` был выбран как read-only.

## Исправлено

- Engine protocol получил control command `TUNE pcie_frac=... spec_min_p=...` между запросами.
- `TUNE` меняет in-memory `live_pcie_frac/live_spec_min_p` и фактический `ExpertDispatch::pcie_num` scheduler; ответ движка: `TUNED <pcie> <mtp> <pcie_num>`.
- `INFO` объявляет `request_tune=2 live_tune=1`.
- Web `Apply` сначала вызывает `/runtime-tune` и считает операцию успешной только после engine ACK. Если engine не подтвердил изменение, Web ничего не сохраняет как успешно применённое.
- Per-request `strata_tune` остаётся дополнительной защитой и каждый DONE возвращает реально применённые `pcie_frac/spec_min_p`.
- `timings.pcie_offloaded_entries` выводится в Web под ответом. При реальной работе scheduler это позволяет отличить `pcie_frac=0` от `pcie_frac>0` по числу PCIe-offload entries, а не по значению поля UI.
- Runtime Reset теперь сразу возвращает engine к model defaults и тоже требует ACK.
- `VERIFY-RUNTIME-TUNE.ps1` исправлен (`${CfgPath}:`) и теперь проверяет не только ACK: при PCIe=0 требует 0 offload entries, затем при PCIe=1 требует увеличение offload entries, после чего возвращает исходный runtime PCIe.
- POST `/config` отключён: HTTP 405. Web больше не содержит write-path для model/run JSON.
- `serve.runconfig.save()` fail-closed с `PermissionError`.
- Все launchers продолжают передавать серверу только generated runtime JSON из `logs/...`; исходный root/PERSONAL JSON читается, но не передаётся как writable runtime config.
- `New-StrataModelRuntimeConfig` после генерации runtime copy проверяет исходный config по проектному правилу identity: точное имя + точный размер; SHA не используется.
- Saved model autotune больше не может молча заменить значения model JSON: профиль применяется только при явном `"autotune": true` в пользовательском config. Launcher defaults выставлены в `autotune=false`; пользовательский `true` по-прежнему имеет приоритет.
- `VERIFY-RUNTIME-TUNE.ps1` больше не содержит PowerShell `$var:` parse bug.

## Проверки в среде сборки архива

- `python -m py_compile serve/server.py serve/runconfig.py` — OK.
- `node --check serve/web/app.js` — OK.
- `python serve/test_runtime_tune_browser.py` — OK: Apply вызывает live `/runtime-tune`, request несёт override, UI показывает ACK и PCIe offload metric.
- Целевой Python-набор `serve.test_runconfig`, runtime tune server tests, queue/winjob/security, autotune, Q6/model/Q8 preflight — 76 tests, OK, 2 skipped.
- Дополнительные runtime/config tests — 22 tests, OK.
- `tools.test_runtime_tune_source` — 3/3 OK.
- Полный `serve.test_server` был запущен, но не завершился до локального timeout; полный PASS этого большого suite не заявляется.
- Windows/CUDA binary этой итерации должен быть собран на машине пользователя; контейнер не является RTX 3060 Windows build host.

## Не изменено

- R: остаётся 54 GiB.
- Q6_K остаётся 5-шардовым Q6_K, без XL.
- CPU↔CUDA bitwise parity всё ещё не доказан и не блокирует обычный runtime-tune build.
- Пользовательские model JSON в архиве не модифицировались.
- SHA не вычисляется.
