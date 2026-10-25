# Итерация 005 — системные инструкции. Установка в форк Strata v0.1.39

## 1. Что это

Готовый полный архив исходников со всеми предыдущими изменениями и новой системой системных инструкций. Этот архив **не содержит новую собранную программу `strata.exe`**. Из него нужно **перенести только изменённые исходные файлы** в существующий Git-репозиторий на втором компьютере. Не распаковывать поверх рабочего `E:\ai\Strata-Q4-Fork`.

Подтверждённая исходная ветка `strata-v0.1.39-custom`, коммит `7f179d5` после успешно опубликованной итерации 004.

## 2. Перед применением

Скачать `Strata-custom-v0.1.39-iteration005-FULL.zip` в каталог:

`A:\worklab\project\App\Strata\`

Проверить реальное существование файла в Проводнике. Рядом находится каталог репозитория:

`A:\worklab\project\App\Strata\Strata`

## 3. Копирование файлов — PowerShell 7

Выполнить блок **целиком**. Любая ошибка останавливает операцию. До начала копирования проверяются ветка, коммит, отсутствие локальных изменений и наличие файлов в ZIP.

```powershell
& {
    $ErrorActionPreference = 'Stop'
    $Root = 'A:\worklab\project\App\Strata'
    $Repo = Join-Path $Root 'Strata'
    $Zip = Join-Path $Root 'Strata-custom-v0.1.39-iteration005-FULL.zip'
    $Dst = Join-Path $Root '_DELIVERY_005'
    $Source = Join-Path $Dst 'Strata'

    if (-not (Test-Path -LiteralPath $Zip -PathType Leaf)) { throw "Архив не найден: $Zip" }
    if (Test-Path -LiteralPath $Dst) { throw "Каталог распаковки существует: $Dst" }
    if (-not (Test-Path -LiteralPath (Join-Path $Repo '.git'))) { throw 'Git-репозиторий не найден' }

    $Branch = (& git -C $Repo branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0 -or $Branch -ne 'strata-v0.1.39-custom') { throw "Неверная ветка: $Branch" }
    $Commit = (& git -C $Repo rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $Commit.StartsWith('7f179d5')) { throw "Неожиданный коммит: $Commit" }
    $Pending = @(& git -C $Repo status --porcelain)
    if ($LASTEXITCODE -ne 0 -or $Pending.Count -ne 0) { $Pending; throw 'Имеются незакоммиченные изменения' }

    Expand-Archive -LiteralPath $Zip -DestinationPath $Dst

    $Files = @(
        'serve\server.py',
        'serve\system_prompts.py',
        'serve\test_system_prompts.py',
        'serve\test_system_browser.py',
        'serve\web\app.js',
        'serve\web\index.html',
        'serve\web\components.css',
        'serve\web\system_prompts.js',
        'serve\web\test_system_prompts.js',
        'README_RU_CUSTOM.md',
        'README_ITERATION_005.md',
        'CONTINUE_PROMPT.md'
    )
    foreach ($File in $Files) {
        if (-not (Test-Path -LiteralPath (Join-Path $Source $File) -PathType Leaf)) {
            throw "Нет файла в архиве: $File"
        }
    }
    $New = @(
        'serve\system_prompts.py',
        'serve\test_system_prompts.py',
        'serve\test_system_browser.py',
        'serve\web\system_prompts.js',
        'serve\web\test_system_prompts.js',
        'README_ITERATION_005.md'
    )
    foreach ($File in $New) {
        if (Test-Path -LiteralPath (Join-Path $Repo $File)) {
            throw "Новый файл уже существует, автоматическую перезапись запрещаем: $File"
        }
    }
    if (Test-Path -LiteralPath "$Repo\docs\reports\iteration-005") {
        throw 'Отчёт итерации 005 уже существует'
    }
    if (-not (Test-Path -LiteralPath "$Source\docs\reports\iteration-005\REPORT.md")) {
        throw 'Нет отчёта итерации 005 в архиве'
    }
    foreach ($File in $Files) {
        Copy-Item -LiteralPath (Join-Path $Source $File) -Destination (Join-Path $Repo $File)
        Write-Host "[OK] $File"
    }
    Copy-Item -LiteralPath "$Source\docs\reports\iteration-005" -Destination "$Repo\docs\reports" -Recurse
    Write-Host 'Итерация 005 скопирована. Git ещё НЕ опубликован.'
    & git -C $Repo status --short
}
```

## 4. Проверки перед коммитом

```powershell
$ErrorActionPreference = 'Stop'
$Repo = 'A:\worklab\project\App\Strata\Strata'
Push-Location $Repo
try {
    python -m py_compile serve/server.py serve/system_prompts.py serve/test_system_prompts.py serve/test_system_browser.py
    if ($LASTEXITCODE -ne 0) { throw 'Ошибка синтаксиса Python' }
    node --check serve/web/app.js
    if ($LASTEXITCODE -ne 0) { throw 'Ошибка app.js' }
    node --check serve/web/system_prompts.js
    if ($LASTEXITCODE -ne 0) { throw 'Ошибка system_prompts.js' }
    node --test serve/web/test_presets.js serve/web/test_system_prompts.js
    if ($LASTEXITCODE -ne 0) { throw 'Не прошли тесты Node.js' }
    python -m unittest -q serve.test_system_prompts serve.test_stops serve.test_server.SharedSettings serve.test_server.ClientShapes serve.test_server.ThinkingBudget serve.test_server.WebApp
    if ($LASTEXITCODE -ne 0) { throw 'Не прошли тесты Python' }
    git -c core.whitespace=cr-at-eol diff --check
    if ($LASTEXITCODE -ne 0) { throw 'Ошибка проверки Git diff' }
}
finally { Pop-Location }
```

`python serve/test_system_browser.py` — дополнительная необязательная проверка взаимодействия в Chromium. Для её запуска нужны Python Playwright и установленный Chromium. Если отсутствуют — отметьте браузерный тест как невыполненный, не устанавливайте браузер автоматически.

## 5. Публикация GitHub

**Только после успешного выполнения обязательных проверок и просмотра `git diff`:**

```powershell
$ErrorActionPreference = 'Stop'
$Repo = 'A:\worklab\project\App\Strata\Strata'
& git -C $Repo add serve/server.py serve/system_prompts.py serve/test_system_prompts.py serve/test_system_browser.py serve/web/app.js serve/web/index.html serve/web/components.css serve/web/system_prompts.js serve/web/test_system_prompts.js README_RU_CUSTOM.md README_ITERATION_005.md CONTINUE_PROMPT.md docs/reports/iteration-005/
if ($LASTEXITCODE -ne 0) { throw 'Не удалось подготовить изменения' }
& git -C $Repo -c core.whitespace=cr-at-eol diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Нарушены требования к отступам' }
& git -C $Repo diff --cached --stat
# После просмотра изменений:
& git -C $Repo commit -m 'Add system instruction editor and API precedence'
if ($LASTEXITCODE -ne 0) { throw 'Не удалось создать коммит' }
& git -C $Repo push origin strata-v0.1.39-custom
if ($LASTEXITCODE -ne 0) { throw 'Не удалось отправить ветку' }
```

## 6. Использование после установки

В собственном веб-интерфейсе открой **Sampling → System instructions and templates**, разверни раздел, введи текст. Отметь `Enable these instructions`, выбери роль `System` или `User`, нажми `Apply instruction`. Следующий запрос будет содержать выбранный текст; модель не перезапускается. Команды `Save template`, `Load draft`, `Delete`, `Import JSON`, `Export JSON` работают только в браузере. Загрузка шаблона **не применяет** его без `Apply instruction`.

Опциональная общая инструкция для всех API задаётся **в JSON конфигурации запуска**, не в веб-шаблонах:

```json
{
  "system_prompt": "Отвечай точно, учитывай предоставленный контекст.",
  "system_prompt_priority": "client"
}
```

Это только фрагмент полей: не заменяйте им весь существующий JSON. Допустимые правила:

- `client` — клиентская начальная системная инструкция имеет приоритет.
- `server` — начальная клиентская системная инструкция заменяется серверной.
- `merge` — серверная и клиентская инструкции объединяются, серверная идёт первой.

Внешние API-клиенты продолжают отправлять инструкции привычным способом: OpenAI Chat Completions `messages[].role=system/developer`, Anthropic Messages `system`, OpenAI Responses `instructions`. Добавлять новый нестандартный параметр к каждому запросу **не нужно**. Изменение JSON конфигурации запуска требует перезапуска сервера, изменение инструкции из веб-панели — нет.

## 7. Откат

Если изменения 005 ещё не закоммичены, из чистой исходной точки `7f179d5` и только убедившись, что нет чужих изменений: `git -C $Repo restore` по изменённым ранее существовавшим файлам, удаление только новых файлов 005; безопаснее восстановить старую ветку во второй копии и сравнить. После коммита **не используйте `git reset --hard` и `push --force`**, поскольку это может стереть чужие изменения. Используйте `git revert <новый SHA>` после проверки состояния и нового коммита отката.

## 8. Остальные задачи

`docs/reports/iteration-005/TASKS.md`, `CONTINUE_PROMPT.md` в корне.
