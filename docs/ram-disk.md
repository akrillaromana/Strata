# RAM-диск R: — размер определяется при запуске

RAM-диск `R:` (Arsenal Image Mounter, AWE) больше не имеет фиксированного размера 54 GiB.

## Как это работает

- Каждый запускатель модели считает требуемый объём из фактических файлов этого запуска:
  PLE-шард + native pack + MTP + expert-profile + резерв модели.
- `Ensure-StrataModelRamDisk` (`STRATA-MODEL-LAUNCH-COMMON.ps1`) получает `-RequiredBytes`
  и создаёт AWE-диск ровно такого размера (округление вверх до целых ГиБ).
- Если `R:` уже существует и это распознанный Strata RAM-диск, но размер вне диапазона
  `[RequiredBytes, RequiredBytes + 6 GiB]`, том автоматически отцепляется
  (`aim_ll -d -m R:`) и создаётся заново нужного размера.
- Если том не распознан как Strata RAM-диск (чужая метка/файлы/устройство) — отказ,
  чужие диски не трогаются и не форматируются.
- Модели, которым RAM-диск не нужен (например Qwen3.6-35B-A3B через sidecar
  `vendor/strata-q36-0.1.45`), функцию не вызывают и диск не создают.

## Что кладётся на R:

Всё, что не помещается в видеопамять и читается движком во время генерации: PLE-шард GGUF,
native pack, MTP, expert-profile. Всё копируется на R: до старта движка; во время работы
чтётся только из RAM.

## Текущие формулы размера

| Профиль | RequiredBytes |
|---|---|
| IQ3_S | pack + MTP + profile + 3 GiB + PLE-шард (shard2) |
| Q4_K_XL / Huihui Q4 | shard2 (PLE) + pack + MTP + profile + 3 GiB |
| Q6_K | pack + MTP + profile + (PLE при -PleToRam) + 2 GiB |
| Q8_0 | PLE + pack + MTP + profile + 0.5 GiB |

## Диагностика

Отчёт создания/отцепления: `logs/ram-disk/RAM_DISK_LAST.txt`.
Проверка состояния: `CHECK-STRATA-RAM-DISK.ps1`.
