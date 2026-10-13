# Как применить итерацию 002 к форку на втором компьютере

## Условия

- Форк: `https://github.com/akrillaromana/Strata`.
- Ветка: `strata-v0.1.39-custom`.
- Ожидаемый опубликованный предыдущий коммит: `ba8b9d2` (проверьте локальный полный SHA командой `git rev-parse HEAD`).
- Папка репозитория на втором ПК: `A:\worklab\project\App\Strata\Strata`.
- Установка `E:\ai\Strata-Q4-Fork` на другом компьютере не затрагивается.

Архив содержит **полную копию исходников** на момент итерации 002. Не заменяйте всё дерево форка при установке. Скопируйте только затронутые файлы.

## 1. Распаковка — PowerShell 7 на втором ПК

Положите `Strata-custom-v0.1.39-iteration002-FULL.zip` в `A:\worklab\project\App\Strata\`.

```powershell
$ErrorActionPreference = 'Stop'
$Workspace = 'A:\worklab\project\App\Strata'
$Repo = Join-Path $Workspace 'Strata'
$Archive = Join-Path $Workspace 'Strata-custom-v0.1.39-iteration002-FULL.zip'
$Delivery = Join-Path $Workspace '_DELIVERY_002'
if (Test-Path -LiteralPath $Delivery) { throw 'Каталог доставки уже существует — не перезаписываем автоматически' }
Expand-Archive -LiteralPath $Archive -DestinationPath $Delivery
$Source = Join-Path $Delivery 'Strata'
if (-not (Test-Path -LiteralPath (Join-Path $Source 'serve\web\app.js'))) { throw 'Неправильная структура архива' }
```

## 2. Проверка безопасного состояния форка

```powershell
git -C $Repo switch strata-v0.1.39-custom
if ($LASTEXITCODE -ne 0) { throw 'Не удалось выбрать ветку' }
$Commit = (git -C $Repo rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or -not $Commit.StartsWith('ba8b9d2')) { throw "Ожидался коммит ba8b9d2; найден $Commit" }
$Status = @(git -C $Repo status --porcelain)
if ($LASTEXITCODE -ne 0 -or $Status.Count -ne 0) { $Status; throw 'Есть незакоммиченные изменения — не перезаписываем' }
```

## 3. Перенос точно указанных файлов

```powershell
$Changed = @(
  'serve\server.py',
  'serve\web\index.html',
  'serve\web\app.js',
  'serve\web\components.css',
  'serve\test_server.py',
  'README_RU_CUSTOM.md',
  'CONTINUE_PROMPT.md'
)
foreach ($Relative in $Changed) {
    Copy-Item -LiteralPath (Join-Path $Source $Relative) -Destination (Join-Path $Repo $Relative)
}
Copy-Item -LiteralPath (Join-Path $Source 'README_ITERATION_002.md') -Destination $Repo
if (Test-Path (Join-Path $Repo 'docs\reports\iteration-002')) { throw 'Отчёт итерации 002 уже есть — остановлено' }
Copy-Item -LiteralPath (Join-Path $Source 'docs\reports\iteration-002') -Destination (Join-Path $Repo 'docs\reports') -Recurse
```

## 4. Проверка и отправка в GitHub

```powershell
& python -m py_compile (Join-Path $Repo 'serve\server.py') (Join-Path $Repo 'serve\test_server.py')
if ($LASTEXITCODE -ne 0) { throw 'Ошибка Python' }
& node --check (Join-Path $Repo 'serve\web\app.js')
if ($LASTEXITCODE -ne 0) { throw 'Ошибка JavaScript' }

git -C $Repo status --short
git -C $Repo -c core.whitespace=cr-at-eol diff --check
if ($LASTEXITCODE -ne 0) { throw 'Ошибка форматирования' }
git -C $Repo diff --stat
```

Проверьте перечисленные изменения визуально. Запустите тесты (в окружении Python должны присутствовать зависимости Strata):

```powershell
Push-Location $Repo
python -m unittest serve.test_server.SharedSettings serve.test_server.SamplingKeys serve.test_server.WebApp serve.test_server.ClientShapes serve.test_server.ThinkingBudget -q
if ($LASTEXITCODE -ne 0) { throw 'Ошибки тестов серверных настроек' }
python -m unittest serve.test_runconfig serve.test_security serve.test_responses -q
if ($LASTEXITCODE -ne 0) { throw 'Ошибки дополнительных тестов' }
Pop-Location
```

После успешных проверок выполните:

```powershell
git -C $Repo add serve/server.py serve/web/index.html serve/web/app.js serve/web/components.css serve/test_server.py README_RU_CUSTOM.md README_ITERATION_002.md CONTINUE_PROMPT.md docs/reports/iteration-002

git -C $Repo -c core.whitespace=cr-at-eol diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Ошибка подготовленных изменений' }

git -C $Repo diff --cached --stat
git -C $Repo commit -m "Extend sampling controls and shared API settings"
if ($LASTEXITCODE -ne 0) { throw 'Не удалось создать коммит' }
git -C $Repo push origin strata-v0.1.39-custom
if ($LASTEXITCODE -ne 0) { throw 'Не удалось отправить коммит' }
```

**Не делайте `git push --force`, `git reset --hard` или копирование всего доставленного каталога поверх репозитория.** Если проверка исходного коммита не прошла — сначала разберитесь, какие новые изменения уже внесены.

## 5. Что увидите в веб-интерфейсе

Панель Sampling содержит новые пять регуляторов и поля точного ввода для всех семи ползунков. Нажмите Apply для локальных настроек браузера. Переключатель «Use for other apps too» сохраняет общие значения в `POST /settings`. Настройки доступны на следующем запросе без перезапуска. Сохраняются существующие Thinking, Seed, Max tokens и переключатели.

**При первом развёртывании этой версии один раз перезапустите процесс сервера Strata** (поскольку был изменён `serve/server.py`) и обновите страницу браузера. После этого само изменение параметров генерации между запросами не требует перезагрузки модели.

Настройки не обещают побитово одинаковой генерации с LM Studio: движки имеют разные вычислительные тракты. Верхний предел Top-k Strata в этой ветке — 64.

## 6. Как откатить только итерацию 002

Только если **последним коммитом** является именно созданный коммит итерации 002, рабочий каталог чистый и никто не добавлял поверх него изменения, можно создать новый коммит отмены (без переписывания истории):

```powershell
git -C $Repo log -2 --oneline
# Убедившись в идентификаторе коммита итерации 002:
git -C $Repo revert <ИДЕНТИФИКАТОР_КОММИТА_ИТЕРАЦИИ_002>
git -C $Repo push origin strata-v0.1.39-custom
```

Команду `git revert` с подстановкой идентификатора выполняйте только после проверки; она не нужна при нормальной установке.
