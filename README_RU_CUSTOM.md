# Strata v0.1.39 — пользовательская ветка (итерации 001–003)

## Итерация 003: именованные предустановки генерации

После подтверждённой публикации итерации 002 (коммит `da1fe89`) добавлено создание,
сохранение, выбор, удаление, импорт и экспорт именованных профилей параметров
генерации. Профили сохраняются локально в браузере и не отправляются на сервер.
Сохранение профиля не применяет его к модели: выберите профиль, нажмите **Load**, затем
**Apply**. Для использования настроек сторонними API-клиентами отдельно включается
существующая опция **Use for other apps too**.

Экспорт JSON версии 1 содержит только 14 разрешённых полей генерации. История чата,
API-ключи, имена файлов модели и пароли не экспортируются. При импорте отклоняются
неизвестные поля; набор профилей заменяется только после подтверждения. На другой
компьютер профили переносятся посредством экспорта и импорта. Описание и установка:
`README_ITERATION_003.md`; подробный отчёт `docs/reports/iteration-003/REPORT.md`.

**Проверено:** 16 тестов Node.js, 22 профильных серверных теста и имитация браузерных
операций. Полный тест на Windows с загруженной моделью пока не проведён.

---

## Итерация 002: расширенные настройки генерации

После успешного коммита `ba8b9d2` пользователем в `strata-v0.1.39-custom` подготовлен следующий набор изменений: управление Min-p, штрафом повторения, штрафами присутствия/частоты, окном истории; ползунки с точным числовым вводом. Настройки применяются со следующего запроса, без перезапуска модели. Внешние клиенты могут наследовать их через уже существующую опцию «Use for other apps too» (эндпоинт `/settings`). Значение из самого API-запроса важнее общей настройки.

В движке C++ эти режимы существовали ранее. В итерации 002 не изменялись движок, MTP, память, CUDA и сценарии запуска. Подробности: `docs/reports/iteration-002/REPORT.md`; команды переноса: `README_ITERATION_002.md`.

Нейтральные значения: `min_p=0`, `repetition_penalty=1`, `presence_penalty=0`, `frequency_penalty=0`. История штрафов ограничена 4096 токенами в данной реализации. `top_k` ограничен 64 кандидатами; режим полностью неограниченного Top-k пока **не реализован**.

**Статус:** тестовые проверки сервера для затронутых компонентов пройдены (40 + 50). Полные GPU-проверки и испытания интерфейса в браузере ещё не выполнены. Всё это не означает завершение всей задачи расширения настроек.

---

**Назначение:** перенос проверенных локальных изменений из `E:\ai\Strata-Q4` в ветку `strata-v0.1.39-custom` форка `akrillaromana/Strata` без замены универсального установщика.

## Что перенесено

1. `src/core/native_dense.cpp` — исправление метаданных дополнительных сегментов GGUF: поле `general.architecture` иногда повторяется без `qwen4exp.block_count`. Дополнительные сегменты всё ещё проверяются по `split.count`, `split.no`, `split.tensors.count`; повторяющиеся номера запрещены.
2. `tests/core/native_dense_ple_key_test.cpp` — расширенные проверки для повторно разделённой Huihui, несовпадающего количества сегментов и ошибочной архитектуры.
3. `serve/server.py` — прежняя работающая на локальной машине передача `reasoning_budget_tokens` из cookie веб-клиента, с приоритетом явного параметра запроса.
4. `serve/web/index.html` — существующее поле бюджета рассуждений, с сохранением значения между запросами без перезапуска модели.
5. `tools/windows/q4-local-profiles/` — копии локальных сценариев запуска Q4, Huihui и IQ3_S, диагностических утилит и конфигураций. **Это архивированные профили для конкретной машины, а не универсальные сценарии, готовые к запуску после клонирования форка.**
6. `tools/windows/experimental-ple/` — сохранённые исследовательские средства работы с PLE. Экспериментальны; не применяются автоматически.

**Не заменялись:** официальный `README.md`, `START-HERE.bat`, `setup.py`, `CMakeLists.txt`, исходные файлы `main`, настройки сборки, сторонние зависимости и файлы моделей. Тем самым новая пользовательская ветка не получает машинно-зависимый установщик в качестве стандартного.

## Перенос на второй компьютер — Windows, PowerShell 7

Архив доставки должен быть скопирован на второй компьютер по адресу:

`A:\worklab\project\App\Strata\Strata-custom-v0.1.39-iteration001-FULL.zip`

Запусти PowerShell 7 и выполни команды **по одному блоку**:

```powershell
$ErrorActionPreference = 'Stop'
$Workspace = 'A:\worklab\project\App\Strata'
$Repo = Join-Path $Workspace 'Strata'
$Archive = Join-Path $Workspace 'Strata-custom-v0.1.39-iteration001-FULL.zip'
$Delivery = Join-Path $Workspace '_DELIVERY_001'
if (Test-Path -LiteralPath $Delivery) { throw 'Каталог доставки уже существует: проверь его перед распаковкой' }
Expand-Archive -LiteralPath $Archive -DestinationPath $Delivery
$Source = Join-Path $Delivery 'Strata'
if (-not (Test-Path -LiteralPath (Join-Path $Source 'README_RU_CUSTOM.md'))) { throw 'Неправильная структура архива' }
```

Проверить текущий репозиторий. Если рабочий каталог загрязнён другими правками — **остановись**:

```powershell
git -C $Repo switch strata-v0.1.39-custom
if ($LASTEXITCODE -ne 0) { throw 'Не удалось выбрать пользовательскую ветку' }
$Expected = 'a1641e9f77aacad4d201b53c8a7ae8fa21059ebb'
$Actual = (& git -C $Repo rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $Actual -ne $Expected) { throw "Неожиданный исходный коммит: $Actual" }
$Changes = @(git -C $Repo status --porcelain)
if ($Changes.Count -ne 0) { $Changes; throw 'Репозиторий содержит незакоммиченные изменения' }
```

**Скопировать только перечисленные исходные файлы**, не перезаписывая остальное содержимое `Strata`:

```powershell
Copy-Item -LiteralPath (Join-Path $Source 'src\core\native_dense.cpp') -Destination (Join-Path $Repo 'src\core\native_dense.cpp')
Copy-Item -LiteralPath (Join-Path $Source 'tests\core\native_dense_ple_key_test.cpp') -Destination (Join-Path $Repo 'tests\core\native_dense_ple_key_test.cpp')
Copy-Item -LiteralPath (Join-Path $Source 'serve\server.py') -Destination (Join-Path $Repo 'serve\server.py')
Copy-Item -LiteralPath (Join-Path $Source 'serve\web\index.html') -Destination (Join-Path $Repo 'serve\web\index.html')
if (Test-Path -LiteralPath (Join-Path $Repo 'tools\windows')) { throw 'Каталог tools\windows уже существует — сначала сравни его с импортом' }
Copy-Item -LiteralPath (Join-Path $Source 'tools\windows') -Destination (Join-Path $Repo 'tools') -Recurse
New-Item -ItemType Directory -Force -Path (Join-Path $Repo 'docs\reports') | Out-Null
if (Test-Path -LiteralPath (Join-Path $Repo 'docs\reports\iteration-001')) { throw 'Отчёт итерации 001 уже существует — не перезаписывай' }
Copy-Item -LiteralPath (Join-Path $Source 'docs\reports\iteration-001') -Destination (Join-Path $Repo 'docs\reports') -Recurse
Copy-Item -LiteralPath (Join-Path $Source 'README_RU_CUSTOM.md') -Destination $Repo
Copy-Item -LiteralPath (Join-Path $Source 'CONTINUE_PROMPT.md') -Destination $Repo
```

Важно: `Copy-Item ... -Destination "$Repo\tools" -Recurse` предполагает, что в репозитории существует папка `tools`; проверка выше отдельно запрещает перезапись существующей папки `windows`. Не запускай с `-Force`.

Теперь изучить изменения **до отправки**:

```powershell
git -C $Repo status --short
git -C $Repo -c core.whitespace=cr-at-eol diff --check
git -C $Repo diff -- src/core/native_dense.cpp tests/core/native_dense_ple_key_test.cpp serve/server.py serve/web/index.html
& python -m py_compile (Join-Path $Repo 'serve\server.py')
if ($LASTEXITCODE -ne 0) { throw 'Ошибка синтаксиса Python' }
```

Коммит в пользовательскую ветку, только после проверки:

```powershell
git -C $Repo add src/core/native_dense.cpp tests/core/native_dense_ple_key_test.cpp serve/server.py serve/web/index.html tools/windows/ docs/reports/iteration-001 README_RU_CUSTOM.md CONTINUE_PROMPT.md
git -C $Repo -c core.whitespace=cr-at-eol diff --cached --check
git -C $Repo diff --cached --stat
git -C $Repo commit -m "Backport Huihui GGUF loader fix and preserve local Q4 profiles"
git -C $Repo push origin strata-v0.1.39-custom
```

Если появится ошибка на любом этапе — **пришли вывод перед следующей командой**, без принудительного продолжения.

Параметр `core.whitespace=cr-at-eol` действует только на конкретную проверку: исходники upstream и пользовательские изменения в Windows используют завершение строк CRLF; Git не должен ошибочно принимать завершающий CR за пробел. Это не отключает обнаружение настоящих пробелов в конце строк.

## Проверки сборки на компьютере с NVIDIA

Сборка пользовательского движка проводится только в отдельном `build` каталоге, не в рабочей `E:\ai\Strata-Q4`. Для Windows под RTX 3060 использовались CMake, Ninja, MSVC, CUDA и архитектура 86.

После конфигурирования и сборки запусти:

```powershell
& 'C:\Program Files\CMake\bin\ctest.exe' --test-dir '<каталог-сборки>' -R '^(gguf_split_test|native_dense_ple_key_test)$' --output-on-failure
```

В ранее выполненной локальной сборке эти 2 проверки прошли. **В новой ветке на втором компьютере CUDA-тесты ещё не выполнялись.** Это не следует выдавать за новую успешную проверку.

## Безопасность и переносимость

- Профили в `tools/windows/q4-local-profiles` содержат пути `E:\ai\...`, диск `R:` и предполагают определённый состав RAM-диска. На другом компьютере нельзя запускать их без адаптации, прав администратора и проверки всех операций удаления.
- `host = 0.0.0.0`, `port = 8080` сохранены **в локальных профилях** по просьбе пользователя. Перед открытием порта в сеть установи ключ API и ограничь правила брандмауэра.
- В эту доставку не включены установленные `strata.exe`, закрытые ключи, GGUF/PLE/веса, кэши, виртуальное окружение, `.git` вложенного llama.cpp, резервные копии, файлы с локальными журналами.
- Поле бюджета рассуждений в интерфейсе и поддержка cookie — унаследованная локальная реализация. Переработка в нативный контрол и единые настройки генерации предусмотрена в следующих итерациях.
- Ни одну папку из `tools/windows/q4-local-profiles/` автоматически не копировать в корень другого развертывания Strata. Для локальной рабочей установки есть самостоятельная проверенная конфигурация.

## Дальнейшие итерации

Следующий приоритет — единая схема параметров генерации между веб-интерфейсом, API и C++-ядром с разделением настроек, применяемых между запросами, и настроек, требующих перезапуска. См. `CONTINUE_PROMPT.md` и `docs/reports/iteration-001/REPORT.md`.
