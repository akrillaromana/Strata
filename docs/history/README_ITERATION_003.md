# Итерация 003 — предустановки генерации, установка на компьютер A:

## Подтверждённая исходная точка

- Репозиторий: `https://github.com/akrillaromana/Strata`.
- Ветка: `strata-v0.1.39-custom`.
- Предыдущий опубликованный коммит: `da1fe89` (итерация 002).
- Локальный репозиторий: `A:\worklab\project\App\Strata\Strata`.
- ZIP данного этапа: `Strata-custom-v0.1.39-iteration003-FULL.zip`.
- Это **полный архив исходников**, но для обновления уже опубликованного форка копируются **только перечисленные ниже файлы**.
- Нельзя распаковывать ZIP поверх репозитория или рабочей `E:\ai\Strata-Q4-Fork`.

## Что добавлено

В панели `Sampling` появилась секция «Named sampling presets»:

1. Назовите профиль и нажмите **Save preset**. Сохраняются **значения открытой панели**, даже если они ещё не применены к чату.
2. Выберите профиль в списке и нажмите **Load**. Поля панели изменятся, но активные настройки генерации не поменяются.
3. Для фактического применения нажмите штатную кнопку **Apply**. Опция «Use for other apps too» остаётся отдельным явным действием.
4. **Delete** удаляет выбранный профиль после подтверждения, не затрагивая активную генерацию.
5. **Export JSON** сохраняет все именованные профили в `strata-sampling-presets-v1.json`.
6. **Import JSON** проверяет файл и после отдельного подтверждения **заменяет** текущий набор профилей, не меняя активные параметры.

Хранение — **только в localStorage текущего браузера и адреса сервера**. Один и тот же IP/порт, открытый из разных браузеров, хранит разные профили. Перед очисткой данных браузера выполняйте экспорт. Импорт/экспорт не содержит API-ключей, модели, пути к GGUF, чатов или иных произвольных полей. Формат имеет явную версию 1. До 50 профилей, длина имени 1–60 символов, файл импорта максимум 128 КиБ, неизвестные поля не принимаются. При повреждении локальных данных запись нового профиля блокируется, чтобы не уничтожить старые данные без явного импорта.

Функция **не добавляет новое хранилище на сервере** и не меняет C++/CUDA; активные параметры продолжают проходить по пути из итерации 002. Внешние API-клиенты получают значения только при существующем явном включении «Use for other apps too».

## 1. Положить ZIP на компьютер A:

Скачайте архив и вручную сохраните ровно сюда:

`A:\worklab\project\App\Strata\Strata-custom-v0.1.39-iteration003-FULL.zip`

В PowerShell 7 выполните **одним блоком**:

```powershell
& {
    $ErrorActionPreference = 'Stop'
    $Root = 'A:\worklab\project\App\Strata'
    $Repo = Join-Path $Root 'Strata'
    $Zip = Join-Path $Root 'Strata-custom-v0.1.39-iteration003-FULL.zip'
    $Delivery = Join-Path $Root '_DELIVERY_003'
    $Source = Join-Path $Delivery 'Strata'

    if (-not (Test-Path -LiteralPath $Zip -PathType Leaf)) { throw "Архив отсутствует: $Zip" }
    if (Test-Path -LiteralPath $Delivery) { throw "Папка доставки уже существует: $Delivery" }
    if (-not (Test-Path -LiteralPath (Join-Path $Repo '.git'))) { throw "Репозиторий не найден: $Repo" }

    $Branch = (& git -C $Repo branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0 -or $Branch -ne 'strata-v0.1.39-custom') { throw "Неподходящая ветка: $Branch" }
    $Commit = (& git -C $Repo rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $Commit.StartsWith('da1fe89')) { throw "Ожидается da1fe89, обнаружен $Commit" }
    $Pending = @(& git -C $Repo status --porcelain)
    if ($LASTEXITCODE -ne 0 -or $Pending.Count -ne 0) { $Pending; throw 'В репозитории есть несохранённые изменения' }

    Expand-Archive -LiteralPath $Zip -DestinationPath $Delivery

    $Changes = @(
        'serve\web\app.js',
        'serve\web\components.css',
        'serve\web\index.html',
        'serve\web\presets.js',
        'serve\web\test_presets.js',
        'serve\test_server.py',
        'README_RU_CUSTOM.md',
        'CONTINUE_PROMPT.md',
        'README_ITERATION_003.md'
    )
    foreach ($Relative in $Changes) {
        if (-not (Test-Path -LiteralPath (Join-Path $Source $Relative) -PathType Leaf)) {
            throw "В архиве отсутствует: $Relative"
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $Source 'docs\reports\iteration-003\REPORT.md'))) {
        throw 'В архиве нет отчёта итерации 003'
    }
    foreach ($Relative in @('serve\web\presets.js', 'serve\web\test_presets.js')) {
        if (Test-Path -LiteralPath (Join-Path $Repo $Relative)) {
            throw "Новый файл уже существует в форке, нужно сравнение: $Relative"
        }
    }
    if (Test-Path -LiteralPath (Join-Path $Repo 'docs\reports\iteration-003')) {
        throw 'Отчёт итерации 003 уже существует'
    }

    foreach ($Relative in $Changes) {
        Copy-Item -LiteralPath (Join-Path $Source $Relative) -Destination (Join-Path $Repo $Relative)
        Write-Host "[OK] $Relative"
    }
    Copy-Item -LiteralPath (Join-Path $Source 'docs\reports\iteration-003') -Destination (Join-Path $Repo 'docs\reports') -Recurse
    Write-Host 'Доставка 003 скопирована. Коммит пока не выполнялся.'
    & git -C $Repo status --short
}
```

## 2. Локальные проверки перед коммитом

В том же PowerShell:

```powershell
$Repo = 'A:\worklab\project\App\Strata\Strata'
& node --check "$Repo\serve\web\app.js"
if ($LASTEXITCODE -ne 0) { throw 'Ошибка синтаксиса app.js' }
& node --check "$Repo\serve\web\presets.js"
if ($LASTEXITCODE -ne 0) { throw 'Ошибка синтаксиса presets.js' }
& node --test "$Repo\serve\web\test_presets.js"
if ($LASTEXITCODE -ne 0) { throw 'Проверки предустановок не пройдены' }
& python -m py_compile "$Repo\serve\test_server.py"
if ($LASTEXITCODE -ne 0) { throw 'Ошибка синтаксиса серверных тестов' }
& git -C $Repo -c core.whitespace=cr-at-eol diff --check
if ($LASTEXITCODE -ne 0) { throw 'Ошибка пробелов в изменениях' }
& git -C $Repo diff --stat
& git -C $Repo status --short
```

Если зависимости Python установлены, дополнительно выполните из каталога репозитория:

```powershell
Set-Location 'A:\worklab\project\App\Strata\Strata'
python -m unittest -v serve.test_server.SamplingKeys serve.test_server.SharedSettings serve.test_server.WebApp
if ($LASTEXITCODE -ne 0) { throw 'Проверки сервера не пройдены' }
```

На Windows введите в веб-интерфейсе хотя бы два профиля, сохраните, перезагрузите страницу, импортируйте/экспортируйте JSON и проверьте, что API и генерация после **Apply** используют выбранные значения. Эти действия на машине пользователя в этой итерации пока не проводились.

## 3. Фиксация и отправка в GitHub

```powershell
$Repo = 'A:\worklab\project\App\Strata\Strata'
git -C $Repo add serve/web/app.js serve/web/components.css serve/web/index.html serve/web/presets.js serve/web/test_presets.js serve/test_server.py README_RU_CUSTOM.md README_ITERATION_003.md CONTINUE_PROMPT.md docs/reports/iteration-003
if ($LASTEXITCODE -ne 0) { throw 'Не удалось подготовить файлы' }
git -C $Repo -c core.whitespace=cr-at-eol diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Ошибка подготовки коммита' }
git -C $Repo diff --cached --stat
git -C $Repo commit -m 'Add validated browser-local sampling presets'
if ($LASTEXITCODE -ne 0) { throw 'Коммит не создан' }
git -C $Repo push origin strata-v0.1.39-custom
if ($LASTEXITCODE -ne 0) { throw 'Публикация не выполнена' }
```

Ни одна из команд не содержит `push --force` и не перезаписывает работающую установку Strata-Q4-Fork на компьютере E:.

## 4. Откат

Если изменения уже опубликованы, не изменяйте историю общей ветки командой `reset --hard` и не применяйте `push --force`. Выполните `git revert` для **нового коммита итерации 003**, а затем обычный `git push`. До создания коммита можно вернуть шесть изменённых файлов через `git restore` и вручную удалить добавленные два `.js`, документ и отчёт. Сначала просмотрите `git status --short`.

## 5. Область проверок и ограничения

- 16 проверок чистой логики Node.js: пройдены.
- 22 теста групп `SamplingKeys`, `SharedSettings`, `WebApp`: пройдены.
- Браузерная проверка интерфейса (Chromium, встроенный DOM без настоящего Strata): save/load/apply/export/delete/import/reject и мобильная ширина 375 пикселей — пройдены.
- Полная CUDA-сборка, полноценный сквозной запуск на пользовательском Windows и проверка сервера с настоящей моделью **не выполнялись**.
- Полные проверки всех серверных тестов не заявлены.
