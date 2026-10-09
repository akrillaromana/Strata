# Итерация 004 — стоп-последовательности. Установка на компьютер A:

## 1. Исходная точка

- Репозиторий: `https://github.com/akrillaromana/Strata`.
- Ветка: `strata-v0.1.39-custom`.
- Подтверждённый последний коммит: `f08ad2f` (итерация 003 опубликована пользователем).
- Рабочий каталог Git: `A:\worklab\project\App\Strata\Strata`.
- ZIP этого этапа: `Strata-custom-v0.1.39-iteration004-FULL.zip`.
- `E:\ai\Strata-Q4` на другом компьютере **не трогать**.

Это **полный архив исходников**. Для уже существующей ветки Git необходимо перенести только файлы из списка, а не заменять весь каталог. Исполняемые файлы, GGUF и локальные профили не менялись.

## 2. Что сделано

На панели **Sampling → Stop sequences** можно ввести до 16 стоп-последовательностей, одну на строку. Пустые строки игнорируются. Применение производится кнопкой **Apply**, без перезагрузки модели. Стоп сохраняется в локальных настройках веб-страницы, именованных предустановках и может передаваться общим параметром для других клиентов при включении **Use for other apps too**. Если внешний клиент явно отправляет своё поле `stop` / `stop_sequences`, оно имеет приоритет.

API OpenAI Chat Completions принимает `stop` строкой или массивом строк; Anthropic Messages — `stop_sequences` массивом; Responses API Strata — дополнительно `stop`. В обычных и потоковых ответах стоп не отображается, а при обнаружении прерывается сам генератор. Anthropic возвращает причину `stop_sequence` и конкретную совпавшую строку. Стопы сопоставляются в текстовой части, не внутри рассуждений и не в аргументах инструментов. Незаконченный префикс удерживается до следующего фрагмента. Это означает небольшую задержку для текста, оканчивающегося на начало длинного стопа, зато исключает утечку даже части стоп-строки.

Допустимо до 16 различных непустых значений длиной до 256 символов каждое, максимум 2048 символов суммарно. Веб-панель не предназначена для задания стопа с буквальным переводом строки; для этого можно отправить API-запрос. Старые предустановки JSON версии 1 поддерживаются и импортируются как версия 2 с пустым списком `stop`.

## 3. Точные команды установки в существующий форк

**Сначала вручную скачай ZIP** и помести его строго по пути:

`A:\worklab\project\App\Strata\Strata-custom-v0.1.39-iteration004-FULL.zip`

В PowerShell 7 запусти следующий блок **целиком**. Он останавливается, если нет ZIP, ветка/коммит неверные, есть сторонние локальные изменения или файлы архива отсутствуют.

```powershell
& {
    $ErrorActionPreference = 'Stop'
    $Root = 'A:\worklab\project\App\Strata'
    $Repo = Join-Path $Root 'Strata'
    $Zip = Join-Path $Root 'Strata-custom-v0.1.39-iteration004-FULL.zip'
    $Delivery = Join-Path $Root '_DELIVERY_004'
    $Source = Join-Path $Delivery 'Strata'

    if (-not (Test-Path -LiteralPath $Zip -PathType Leaf)) { throw "Сначала скачай ZIP: $Zip" }
    if (Test-Path -LiteralPath $Delivery) { throw "Каталог распаковки уже существует: $Delivery" }
    if (-not (Test-Path -LiteralPath (Join-Path $Repo '.git'))) { throw "Git-репозиторий не найден: $Repo" }

    $Branch = (& git -C $Repo branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0 -or $Branch -ne 'strata-v0.1.39-custom') { throw "Неожиданная ветка: $Branch" }
    $Commit = (& git -C $Repo rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $Commit.StartsWith('f08ad2f')) { throw "Ожидается f08ad2f, обнаружен $Commit" }
    $Pending = @(& git -C $Repo status --porcelain)
    if ($LASTEXITCODE -ne 0 -or $Pending.Count -ne 0) { $Pending; throw 'Есть незакоммиченные изменения' }

    Expand-Archive -LiteralPath $Zip -DestinationPath $Delivery
    $Changes = @(
        'serve\server.py',
        'serve\stops.py',
        'serve\test_stops.py',
        'serve\test_stop_browser.py',
        'serve\web\app.js',
        'serve\web\index.html',
        'serve\web\components.css',
        'serve\web\presets.js',
        'serve\web\test_presets.js',
        'README_RU_CUSTOM.md',
        'README_ITERATION_004.md',
        'CONTINUE_PROMPT.md'
    )
    foreach ($Relative in $Changes) {
        if (-not (Test-Path -LiteralPath (Join-Path $Source $Relative) -PathType Leaf)) {
            throw "В архиве отсутствует: $Relative"
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $Source 'docs\reports\iteration-004\REPORT.md'))) {
        throw 'В архиве отсутствует отчёт итерации 004'
    }
    foreach ($Relative in @('serve\stops.py', 'serve\test_stops.py', 'serve\test_stop_browser.py', 'README_ITERATION_004.md')) {
        if (Test-Path -LiteralPath (Join-Path $Repo $Relative)) {
            throw "Ожидался новый файл, но он уже существует: $Relative"
        }
    }
    if (Test-Path -LiteralPath (Join-Path $Repo 'docs\reports\iteration-004')) {
        throw 'Отчёт итерации 004 уже есть: сравни изменения, не перезаписывай автоматически'
    }

    foreach ($Relative in $Changes) {
        Copy-Item -LiteralPath (Join-Path $Source $Relative) -Destination (Join-Path $Repo $Relative)
        Write-Host "[OK] $Relative"
    }
    Copy-Item -LiteralPath (Join-Path $Source 'docs\reports\iteration-004') -Destination (Join-Path $Repo 'docs\reports') -Recurse
    Write-Host 'Итерация 004 скопирована. Публикация Git НЕ выполнялась.'
    & git -C $Repo status --short
}
```

## 4. Проверки на компьютере A:

```powershell
$ErrorActionPreference = 'Stop'
$Repo = 'A:\worklab\project\App\Strata\Strata'

& python -m py_compile "$Repo\serve\server.py" "$Repo\serve\stops.py" "$Repo\serve\test_stops.py"
if ($LASTEXITCODE -ne 0) { throw 'Ошибка синтаксиса Python' }
& node --check "$Repo\serve\web\app.js"
if ($LASTEXITCODE -ne 0) { throw 'Ошибка синтаксиса app.js' }
& node --check "$Repo\serve\web\presets.js"
if ($LASTEXITCODE -ne 0) { throw 'Ошибка синтаксиса presets.js' }
& node --test "$Repo\serve\web\test_presets.js"
if ($LASTEXITCODE -ne 0) { throw 'Ошибка тестов предустановок' }

# Необязательная проверка Chromium при наличии Playwright и браузера:
# & python "$Repo\serve\test_stop_browser.py"
# Здесь следует ждать [OK] и код 0; без Playwright проверка НЕ выполнена.

# Следующие Python-тесты требуют модули, которые использует штатный сервер Strata.
Push-Location $Repo
try {
    & python -m unittest -q serve.test_stops
    if ($LASTEXITCODE -ne 0) { throw 'Ошибка тестов стоп-последовательностей' }
    & python -m unittest -q serve.test_server.SharedSettings serve.test_server.ClientShapes serve.test_server.ThinkingBudget serve.test_server.WebApp
    if ($LASTEXITCODE -ne 0) { throw 'Ошибка регрессионных тестов сервера' }
} finally {
    Pop-Location
}

& git -C $Repo -c core.whitespace=cr-at-eol diff --check
if ($LASTEXITCODE -ne 0) { throw 'Ошибка в пробелах/концах строк изменений' }
& git -C $Repo status --short
& git -C $Repo diff --stat
```

В случае отсутствия Python-зависимостей **не считать тесты пройденными**: установи зависимости из штатной документации Strata или сообщи ошибку. Для запуска тестов нужен выбранный Python с доступными Jinja2 и другими зависимостями сервера. C++/CUDA этой итерацией не менялись.

## 5. Проверить коммит и опубликовать на GitHub

Если все предыдущие проверки прошли и нет посторонних файлов:

```powershell
$ErrorActionPreference = 'Stop'
$Repo = 'A:\worklab\project\App\Strata\Strata'
& git -C $Repo add serve/server.py serve/stops.py serve/test_stops.py serve/test_stop_browser.py `
    serve/web/app.js serve/web/index.html serve/web/components.css `
    serve/web/presets.js serve/web/test_presets.js `
    docs/reports/iteration-004 README_RU_CUSTOM.md README_ITERATION_004.md CONTINUE_PROMPT.md
if ($LASTEXITCODE -ne 0) { throw 'Не удалось добавить изменения' }
& git -C $Repo -c core.whitespace=cr-at-eol diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Ошибка проверки подготовленного коммита' }
& git -C $Repo diff --cached --stat
```

**Просмотри перечень изменений.** Если всё правильно:

```powershell
$Repo = 'A:\worklab\project\App\Strata\Strata'
& git -C $Repo commit -m 'Add streaming-safe stop sequences and preset migration'
if ($LASTEXITCODE -ne 0) { throw 'Коммит не создан' }
& git -C $Repo push origin strata-v0.1.39-custom
if ($LASTEXITCODE -ne 0) { throw 'GitHub не обновлён' }
& git -C $Repo status --short
```

Если `git push` прошёл, пришли вывод и новый короткий SHA. **Не выполнять `push --force`.**

## 6. Откат

До коммита (только если перечисленные файлы не содержат чужих изменений и ты точно отменяешь доставку 004):

```powershell
$Repo = 'A:\worklab\project\App\Strata\Strata'
& git -C $Repo restore --staged --worktree -- serve/server.py serve/web/app.js `
    serve/web/index.html serve/web/components.css serve/web/presets.js `
    serve/web/test_presets.js README_RU_CUSTOM.md CONTINUE_PROMPT.md
Remove-Item -LiteralPath "$Repo\serve\stops.py", "$Repo\serve\test_stops.py", "$Repo\serve\test_stop_browser.py", `
    "$Repo\README_ITERATION_004.md" -ErrorAction Stop
Remove-Item -LiteralPath "$Repo\docs\reports\iteration-004" -Recurse -ErrorAction Stop
```

После опубликованного коммита предпочтительно `git revert <SHA_коммита_004>` и обычный `git push`, а не переписывание истории. До отката сохранить при необходимости рабочие изменения и проверить `git status`.

## 7. Что проверить на рабочем компьютере E: позже

Только после подтверждения сборки и осознанного решения обновить локальную Strata: проверить короткий и длинный стоп, Unicode, SSE без префикса стопа, отсутствие ложного совпадения внутри reasoning, работу `--batch` и обычную/пользовательскую Q4. Продолжаем держать рабочую Strata-Q4 отдельной до успешных проверок.
