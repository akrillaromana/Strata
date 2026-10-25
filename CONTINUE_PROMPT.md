# CONTINUE PROMPT — Strata Fork (personal)

Рабочий документ форка. Актуальные правила и задачи; выполненное отсюда убрано и
задокументировано в `docs/`. Номера итераций не используются — история в git-коммитах.

## Где что лежит

- Git-форк (вся работа здесь): ветка `strata-v0.1.39-custom`,
  origin `https://github.com/akrillaromana/Strata`, upstream `https://github.com/Niko1221/Strata`.
- Живая рабочая деплой-папка на машине пользователя: `E:\ai\Strata-Q4-Fork` — только чтение,
  менять запрещено.
- Тестовая копия для экспериментов и сборок: `E:\ai\Strata-Q4-Fork_test`.
  Запуск моделей из неё делает пользователь вручную (живая модель в это время остановлена).
- Данные: `E:\ai\Strata-data`, модели: `E:\ai\models`.

## Неприкосновенные правила

- Никаких ZIP пользователю: агент работает напрямую с файлами на машине.
- Никаких итераций: упоминания итераций из документации и информационных файлов убираются.
- Каждое изменение — коммит и push в `strata-v0.1.39-custom`.
- В README репозитория только английский; локализованные README удалены, историчные заметки
  в `docs/history/`.
- Пользовательские model JSON immutable/read-only; `POST /config` запрещён (405);
  runtime-конфиги — только generated JSON в `logs/...`.
- Product defaults qwen4exp: `--pcie-frac 0.09`, `--spec-min-p 0.9`, `parallel=2`
  (`parallel: 1` отключает). MTP=1.0 всегда в calibration grid. Saved autotune — только
  при явном `"autotune": true`.
- RAM-диск `R:`: размер определяется при запуске под модель, том неверного размера
  автоматически пересоздаётся; чужие диски не трогаются; моделям без надобности (q36)
  диск не создаётся. Всё вне видеопамяти кладётся на R: до старта. Подробности: `docs/ram-disk.md`.
- Vision-энкодер стартует в оперативной памяти и переходит в VRAM только по востребованию,
  обратно по простою. Подробности: `docs/vision-gpu-on-demand.md`.
- Q6: только пятишардовый `Q6_K`, отдельный `engine-q6`.
- Web runtime tuning: engine ACK (`TUNE`/`TUNED`), success без ACK запрещён.
- Идентичность runtime-файлов = имя + точный размер, без SHA.
- PowerShell только 7 (pwsh); BAT ищут PS7 и не откатываются на 5.1; .ps1 с кириллицей — UTF-8 BOM.
- Python без pip: bootstrap через ensurepip (`tools/ensure_server_dependencies.py`) до тяжёлой
  подготовки; проверка импортов до старта.
- `.part`/`downloading_*` — не готовые модели.
- qwen35moe только через изолированный `vendor/strata-q36-0.1.45` → `engine-q36\strata-q36.exe`
  (`BUILD-Q36-ENGINE.bat`); q36 MTP embedded `--mtp 2 --batch-mtp`; флаги PCIe/spec-min-p к q36
  не применять; кастомные qwen4exp/Q6-движки не заменять.
- Structured output fail-closed без jsonschema; лимиты 64 KiB/32 уровня.
- Q8 CPU/CUDA parity — opt-in до подтверждения на RTX 3060.

## Железо пользователя

- Десктоп: i9-10980XE (AVX-512 F/BW/VL/VNNI, без VBMI), ASUS ROG STRIX X299-E GAMING II,
  226 ГБ DDR4, RTX 3060 12 ГБ, Windows.
- Ноутбук 1: 5900HX, 64 ГБ, RX 6800M 12 ГБ (HIP gfx1031, ручная сборка).
- Ноутбук 2: 5900HX, 64 ГБ, RTX 3080 Laptop 16 ГБ.
- Mac home-lab `192.168.50.197`: `~/Strata`, `./run-iq3_s.sh`.

## Калибровка (замерено на машине)

- IQ3_S ~40 ток/с. Q4_K_XL: без `--kv-resident`, `--pcie-frac 0.20`, `--spec-min-p 0.70`,
  `--spec 4`, `--resident-budget-gib 71` → ~20 ток/с; `--kv-resident 32768` вреден на PCIe3+DDR4.
- Draft-vocab VRAM: CJK ~348 MiB, кириллица ~193 MiB, English ~133 MiB.
- PLE-таблица держится в RAM (перенос на GPU ронял decode).

## Задачи

- [ ] Проверка в `E:\ai\Strata-Q4-Fork_test` (запуск делает пользователь):
      старт IQ3_S (`START-HERE IQ3_S.bat`) — READY, `/v1/models`, `logs\iq3s`;
      vision-запрос с картинкой — переход энкодера RAM→GPU и возврат по простою;
      RAM-диск разного размера под IQ3_S / Q4 / q36 (для q36 — без диска).
- [ ] Решить: `parallel=1` (фактический runtime пользователя) vs `parallel=2` (product default).
- [ ] MODEL-CATALOG: безопасный PLE-staging новых моделей на R:, Web MTP OFF/ON на лету,
      фактический путь uncensored 35B Q8_K_XL когда докачается, замеры на RTX 3060.
- [ ] Аппаратные проверки на RTX 3060: wide dequant sm_86, parallel, Q8 parity (opt-in),
      q36 sidecar без SSD-стриминга.
- [ ] Будущее: одновременная работа нескольких моделей/процессов — пока не трогать.
- [ ] Будущее: автоматизация тестового цикла (остановка живой, запуск тестовой, возврат).
- [ ] Будущее: таблица реальных замеров Qwen3.8 Flash-Next по GPU (ток/с, контекст, версия,
      MTP, ссылка); оценки маркировать как оценки.
