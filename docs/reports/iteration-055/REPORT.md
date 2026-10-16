# Отчёт итерации 055 — реальное Web live tuning PCIe/MTP

## Причина

Web UI итерации 053 умел отправлять `strata_tune`, но сервер затем сам возвращал запрошенные значения как будто движок их применил. Это было ложным подтверждением: старый `engine\strata.exe` мог не понимать per-request `pcie_frac/spec_min_p`, а Web всё равно показывал `PCIe 0.20`.

Дополнительно пользовательский Windows-тест parity из 052 завершился неудачей: CPU/CUDA Q8_0 не совпали побитово, поэтому защитный build script намеренно НЕ установил новый `strata.exe`. В результате Python/Web могли быть новее реально работающего engine.

## Исправлено

1. Engine startup `INFO` теперь объявляет `request_tune=1`.
2. Engine `DONE` каждого обычного GEN request дописывает реально разобранные для этого запроса `pcie_frac` и `spec_min_p`.
3. `serve/server.py` считает tuning применённым только при engine ACK из `DONE`; запрошенное значение больше не считается фактическим автоматически.
4. OpenAI stream/non-stream теперь различают:
   - `strata_tune_requested` — что запросил клиент;
   - `strata_tune` — что подтвердил engine;
   - `strata_tune_applied` — совпало ли подтверждение с запросом.
5. `GET /settings` сообщает `runtime_tune_supported` по capability реально запущенного engine.
6. Web отключает PCIe/MTP controls и показывает `engine rebuild required`, если запущенный exe старый.
7. Web под ответом показывает override только после ACK engine. При отказе/старом engine пишет `runtime tune NOT applied`, а не ложное значение.
8. `TUNE-MODEL.ps1` теперь отклоняет замер, если engine не подтвердил каждый tuning key.
9. `tools/calibrate.py` также прекращает calibration, если прямой engine request не получил runtime-tune ACK.
10. Добавлен `BUILD-RUNTIME-TUNE-ENGINE.ps1/.bat`: обычная сборка текущего engine без `-ParityTest`. Незавершённый CPU/CUDA parity больше не блокирует установку runtime-tune протокола.
11. Добавлен `VERIFY-RUNTIME-TUNE.ps1/.bat`: на одной уже загруженной модели последовательно отправляет PCIe 0.00 и 1.00 и требует точного ACK без рестарта.
12. Исправлены browser-test harnesses: перед `app.js` загружается `runtime_tune.js`.

## Не изменялось

- Пользовательские модельные JSON и их значения.
- Размер RAM-диска R: остаётся 54 GiB.
- Модельные веса, pack, PLE, MTP-файлы.
- CPU/CUDA parity не объявлен исправленным: это отдельная незавершённая задача.
- SHA не вычисляется; проектная идентичность файлов — точное имя + точный размер.

## Проверки

- `python -m py_compile serve/server.py tools/calibrate.py serve/test_server.py tools/test_calibrate.py` — OK.
- `node --check serve/web/app.js` — OK.
- `node serve/web/test_runtime_tune.js` — OK.
- Runtime/server/calibrate target suite — 38/38 OK.
- Queue/winjob/runconfig/security regression suite — 37 tests: 35 OK + 2 штатно skipped.
- Chromium stop/settings browser test — OK.
- Chromium structured-output browser test — OK.
- Chromium system-instruction browser test — OK.
- Chromium Web runtime-tune browser test — OK: override PCIe/MTP реально попадает в `strata_tune`, а UI показывает только engine ACK и timings.
- Все 169 пользовательских/проектных JSON сохранены с теми же именами и точными размерами в байтах.

## Обязательный Windows шаг

Поскольку изменён C++ protocol в `src/program/generate.cpp`, одного обновления Python/Web недостаточно. После установки итерации 055 нужно один раз собрать/установить текущий `engine\strata.exe` через `BUILD-RUNTIME-TUNE-ENGINE.ps1`, затем перезапустить модель. После READY `VERIFY-RUNTIME-TUNE.ps1` должен подтвердить PCIe 0 и PCIe 1 на одной resident model.
