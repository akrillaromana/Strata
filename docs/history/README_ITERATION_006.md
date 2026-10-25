# Strata Custom 0.1.39 — итерация 006

## Что находится в архиве

Полный исходный код форка после 001–006, а не готовый Windows `strata.exe`. Внесены: история нескольких бесед, удаление сообщений и ответов, нативное чтение Q8_0 для PLE n-gram, экспериментальные CUDA-ветви Q6_K, образцы отдельной конфигурации Unsloth Q6_K и Huihui Q8_0, проверки и отчёты на русском. **Работающий на E: движок не трогать.**

### Достоверные границы готовности

Чат и PLE Q8_0: закончены по исходному коду с локальными проверками. Q6_K CUDA: реализован исходный путь, но ещё не скомпилирован и не проверен на RTX 3060. Huihui Q8_0: образцы конфигурации есть, реальная модель ещё не предоставлена для тестов — статус «не подтверждена». Полный перенос всех изменений нового донора `Strata-main(1).zip` не выполнен; это отдельная задача. Во избежание риска для других моделей Q6_K по умолчанию выключен.

## 1. Обязательная последовательность установки на компьютер A:

Первой должна быть применена **итерация 005**. Последний подтверждённый пользователем `git push` был `7f179d5` итерации 004. Если `005` ещё не установлена, сначала следуй `README_ITERATION_005.md` из предыдущего полного архива, выполни её проверки, `git commit` и `git push`. **Нельзя** класть файлы 006 поверх 004, минуя 005: иначе исчезнут изменения серверных системных инструкций и шаблонов.

После 005 скопируй файл `Strata-custom-v0.1.39-iteration006-FULL.zip` в `A:\worklab\project\App\Strata\` и выполни **всё одним блоком** в PowerShell (до первой ошибки последующие команды не выполнять):

```powershell
& {
    $ErrorActionPreference = 'Stop'
    $Root = 'A:\worklab\project\App\Strata'
    $Repo = Join-Path $Root 'Strata'
    $Zip = Join-Path $Root 'Strata-custom-v0.1.39-iteration006-FULL.zip'
    $Dst = Join-Path $Root '_DELIVERY_006'
    $Source = Join-Path $Dst 'Strata'

    if (-not (Test-Path -LiteralPath $Zip -PathType Leaf)) { throw "Сначала скачай ZIP: $Zip" }
    if (Test-Path -LiteralPath $Dst) { throw "Папка распаковки уже существует: $Dst" }
    $Branch = (git -C $Repo branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0 -or $Branch -ne 'strata-v0.1.39-custom') { throw 'Неправильная ветка' }
    if (@(git -C $Repo status --porcelain).Count -ne 0) { throw 'Есть несохранённые изменения' }
    if (-not (Test-Path "$Repo\serve\system_prompts.py") -or
        -not (Test-Path "$Repo\docs\reports\iteration-005\REPORT.md")) {
        throw 'Итерация 005 ещё не применена. Сначала установи 005 и опубликуй коммит.'
    }

    Expand-Archive -LiteralPath $Zip -DestinationPath $Dst
    $Files = @(
        'CMakeLists.txt',
        'include\strata\kernels\ngram.hpp',
        'src\kernels\ngram.cpp',
        'src\ngram\ple_reader_test.cpp',
        'src\kernels\cuda\iq_kernels.cu',
        'src\kernels\native_grouped_parity.cpp',
        'src\prefill\moe_mmq.cu',
        'serve\web\chat_sessions.js',
        'serve\web\test_chat_sessions.js',
        'serve\web\app.js',
        'serve\web\index.html',
        'serve\web\components.css',
        'tests\cpu\ple_q8_row_test.cpp',
        'README_ITERATION_006.md',
        'README_RU_CUSTOM.md',
        'CONTINUE_PROMPT.md'
    )
    foreach ($File in $Files) {
        if (-not (Test-Path -LiteralPath "$Source\$File" -PathType Leaf)) {
            throw "В архиве отсутствует: $File"
        }
    }
    foreach ($New in @('serve\web\chat_sessions.js', 'serve\web\test_chat_sessions.js',
                       'tests\cpu\ple_q8_row_test.cpp', 'README_ITERATION_006.md')) {
        if (Test-Path -LiteralPath "$Repo\$New") { throw "Новый файл уже существует: $New" }
    }
    foreach ($Dir in @('docs\reports\iteration-006', 'tools\windows\native-high-quant')) {
        if (Test-Path -LiteralPath "$Repo\$Dir") { throw "Новый каталог уже существует: $Dir" }
        if (-not (Test-Path -LiteralPath "$Source\$Dir" -PathType Container)) {
            throw "В архиве отсутствует каталог: $Dir"
        }
    }
    foreach ($File in $Files) {
        $Out = "$Repo\$File"
        $Parent = Split-Path -Parent $Out
        if (-not (Test-Path -LiteralPath $Parent)) {
            New-Item -ItemType Directory -Path $Parent -Force | Out-Null
        }
        Copy-Item -LiteralPath "$Source\$File" -Destination $Out
        Write-Host "[OK] $File"
    }
    Copy-Item -LiteralPath "$Source\docs\reports\iteration-006" -Destination "$Repo\docs\reports" -Recurse
    Copy-Item -LiteralPath "$Source\tools\windows\native-high-quant" -Destination "$Repo\tools\windows" -Recurse
    git -C $Repo status --short
    if ($LASTEXITCODE -ne 0) { throw 'Ошибка получения состояния Git' }
    Write-Host 'ФАЙЛЫ ИТЕРАЦИИ 006 ПЕРЕНЕСЕНЫ. ЕЩЁ НЕ ОТПРАВЛЕНЫ НА GITHUB.'
}
```

## 2. Проверка на A: перед фиксацией

```powershell
$ErrorActionPreference = 'Stop'
$Repo = 'A:\worklab\project\App\Strata\Strata'
node --check "$Repo\serve\web\app.js"
if ($LASTEXITCODE -ne 0) { throw 'Ошибка app.js' }
node --test "$Repo\serve\web\test_chat_sessions.js" "$Repo\serve\web\test_presets.js" "$Repo\serve\web\test_system_prompts.js"
if ($LASTEXITCODE -ne 0) { throw 'Ошибка тестов интерфейса' }
python -m py_compile "$Repo\serve\server.py"
if ($LASTEXITCODE -ne 0) { throw 'Ошибка Python' }
Push-Location $Repo
try {
    python -m unittest -q serve.test_stops serve.test_system_prompts
    if ($LASTEXITCODE -ne 0) { throw 'Ошибка серверных тестов' }
} finally { Pop-Location }
git -C $Repo -c core.whitespace=cr-at-eol diff --check
if ($LASTEXITCODE -ne 0) { throw 'Ошибка пробелов в исходниках' }
```

Проверка C++/CUDA требует настроенного компилятора; полные команды выделены в `tools/windows/native-high-quant/README_RU.md`. Если установлена MSVC/CUDA на A: и доступно место, собери **отдельно**, НЕ поверх E:/Q4. Сборка CPU Q8 `ple_q8_row_test` не зависит от CUDA, но на Windows для неё нужен компилятор с поддержкой C++20.

## 3. Публикация только после проверок

```powershell
$Repo = 'A:\worklab\project\App\Strata\Strata'
git -C $Repo add CMakeLists.txt include/strata/kernels/ngram.hpp src/kernels/ngram.cpp src/ngram/ple_reader_test.cpp src/kernels/cuda/iq_kernels.cu src/kernels/native_grouped_parity.cpp src/prefill/moe_mmq.cu serve/web/app.js serve/web/index.html serve/web/components.css serve/web/chat_sessions.js serve/web/test_chat_sessions.js tests/cpu/ple_q8_row_test.cpp tools/windows/native-high-quant/ docs/reports/iteration-006/ README_ITERATION_006.md README_RU_CUSTOM.md CONTINUE_PROMPT.md
if ($LASTEXITCODE -ne 0) { throw 'Ошибка git add' }
git -C $Repo -c core.whitespace=cr-at-eol diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Ошибка проверки добавленного' }
git -C $Repo diff --cached --stat
```

Внимательно проверь перечень изменённых файлов и отсутствие секретов, затем:

```powershell
git -C $Repo commit -m "Add chat management and native Q8 PLE with opt-in Q6K"
if ($LASTEXITCODE -ne 0) { throw 'Ошибка фиксации' }
git -C $Repo push origin strata-v0.1.39-custom
if ($LASTEXITCODE -ne 0) { throw 'Ошибка отправки' }
```

## 4. Откат без переписывания истории GitHub

Если ещё не было коммита: `git -C $Repo restore .`, затем `git -C $Repo clean -nd` для **предварительного просмотра** неотслеживаемых новых файлов. Не запускай `git clean -fd` без просмотра: это может удалить личные локальные данные. После опубликованного коммита предпочитай `git revert <НОВЫЙ_КОММИТ>`, а не `reset --hard`/`push --force`.

## 5. Контроль результата

Выполни `git -C $Repo log -2 --oneline` и пришли вывод. Не копируй готовый `strata.exe` в текущий рабочий каталог Q4; Q6/Huihui Q8 пока экспериментальны. Подробные пределы поддержки перечислены в `docs/reports/iteration-006/MODEL_SUPPORT.md` и `TASKS.md`.
