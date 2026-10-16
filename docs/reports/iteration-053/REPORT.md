# Итерация 053 — Web runtime tuning PCIe/MTP

## Выполнено

- В Web UI добавлен блок **Runtime speed tuning**.
- `PCIe frac` (`pcie_frac`) и `MTP threshold` (`spec_min_p`) меняются для следующего запроса без перезапуска модели.
- Для каждого параметра есть режим **Default from model config**.
- Рядом показывается фактическое стартовое значение уже загруженного движка.
- `Reset` возвращает оба параметра к стартовым значениям модели.
- Web-overrides хранятся только в `localStorage` (`strata.runtimeTune`). Пользовательские run-config JSON не меняются.
- Runtime tuning не включается в `POST /settings` / "Use for other apps too".
- Серверный `GET /settings` теперь возвращает `model_tune` с фактическими `pcie_frac/spec_min_p`, с которыми запущен resident engine (включая сохранённый autotune, если он был применён при старте).
- Финальный OpenAI Chat chunk/response возвращает расширение `strata_tune` — реально применённые параметры запроса.
- Web читает `timings` финального ответа и показывает под ответом строку вида:
  `PCIe 0.2 · MTP 0.9 · Prefill 186.0 tok/s · Decode 15.4 tok/s`.
- `MTP=1.0` принимается UI и backend как штатное значение.

## Безопасность конфигов

Ни один запускной JSON не записывается этой функцией. Изменения Web живут в браузере; backend получает их только в поле `strata_tune` конкретного запроса.

## Проверки

- `node --check serve/web/app.js` — OK.
- `node --check serve/web/runtime_tune.js` — OK.
- Все Web unit tests: 56/56 успешно.
- Целевые server tests runtime tuning / shared settings / queue: 17/17 успешно.
- Полный `serve.test_server` запускался дополнительно, но не успел завершиться в лимит 120 секунд; до таймаута явных падений тестов не было. Не считать это полным PASS всего набора.

## Что не проверено здесь

- Реальное изменение `pcie_frac/spec_min_p` через браузер на Windows/RTX 3060.
- Визуальный вид блока в вашем браузере.
- Фактические скорости должны быть подтверждены вашим запросом после обновления.
