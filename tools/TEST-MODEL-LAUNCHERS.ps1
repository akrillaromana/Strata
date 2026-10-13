#requires -Version 7.0
# Разбор синтаксиса без запуска Python, CUDA, GGUF, сервера и работы с R:.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Root = Split-Path -Parent $PSScriptRoot
$Files = @(
    'STRATA-MODEL-LAUNCH-COMMON.ps1',
    'CHECK-STRATA-RAM-DISK.ps1',
    'START-Q4-RAM.ps1',
    'START-HUIHUI-Q4-RAM.ps1',
    'START-Q8-RAM.ps1',
    'PERSONAL_START_E_ai_Strata-Q4-Fork\START-Q4-RAM.ps1',
    'PERSONAL_START_E_ai_Strata-Q4-Fork\START-HUIHUI-Q4-RAM.ps1',
    'PERSONAL_START_E_ai_Strata-Q4-Fork\START-Q8-RAM.ps1',
    'GET-Q8-DIAGNOSTICS.ps1',
    'TUNE-MODEL.ps1',
    'START-IQ3S-RAM.ps1',
    'PERSONAL_START_E_ai_Strata-Q4-Fork\START-IQ3S-RAM.ps1',
    'tools\TEST-CONFIG-IMMUTABILITY.ps1',
    'BENCHMARK-MODEL.ps1',
    'TEST-REQUESTS.ps1'
)
foreach ($Relative in $Files) {
    $File = Join-Path $Root $Relative
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) {
        throw "Файл отсутствует: $Relative"
    }
    $Tokens = $null
    $Errors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $File, [ref]$Tokens, [ref]$Errors)
    if ($Errors.Count -gt 0) {
        foreach ($Item in $Errors) {
            Write-Host ("{0}:{1}: {2}" -f $Relative, $Item.Extent.StartLineNumber, $Item.Message) -ForegroundColor Red
        }
        throw "Ошибка синтаксиса: $Relative"
    }
    Write-Host "[OK] $Relative"
}

# Одной проверки синтаксиса недостаточно: предыдущая инсталляция Q8_0
# запускалась без -PreparePack, хотя этот параметр уже был в новом ZIP.
# Проверяем сигнатуры трёх копий, не выполняя их код.
$Q8Launchers = @(
    'START-Q8-RAM.ps1',
    'PERSONAL_START_E_ai_Strata-Q4-Fork\START-Q8-RAM.ps1',
    'tools\windows\q4-local-profiles\START-Q8-RAM.ps1'
)
$RequiredParameters = @('PreparePack', 'AllowBf16Conversion', 'ModelsDirectory',
                        'PackSource', 'MtpSource', 'Detached', 'Foreground', 'IgnoreAutotune')
foreach ($Relative in $Q8Launchers) {
    $File = Join-Path $Root $Relative
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) {
        throw "Не найден запускатель Q8: $Relative"
    }
    $Tokens = $null
    $Errors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $File, [ref]$Tokens, [ref]$Errors)
    if ($Errors.Count -gt 0 -or $null -eq $Ast.ParamBlock) {
        throw "Нет корректного блока параметров в запускателе Q8: $Relative"
    }
    $ParameterNames = @($Ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    foreach ($ParameterName in $RequiredParameters) {
        if ($ParameterNames -cnotcontains $ParameterName) {
            throw "Устаревший Q8-запускатель: $Relative не поддерживает -$ParameterName. Обновите весь комплект итерации 048."
        }
    }
    Write-Host "[OK] Q8 -PreparePack / -AllowBf16Conversion: $Relative"
}
$PersonalFile = Join-Path $Root $Q8Launchers[1]
$MirrorFile = Join-Path $Root $Q8Launchers[2]
$PersonalHash = (Get-FileHash -LiteralPath $PersonalFile -Algorithm SHA256).Hash
$MirrorHash = (Get-FileHash -LiteralPath $MirrorFile -Algorithm SHA256).Hash
if ($PersonalHash -ne $MirrorHash) {
    throw 'Личный и зеркальный запускатели Q8 различаются. Требуется согласованный комплект итерации 048.'
}
Write-Host '[OK] Обе внутренние копии Q8 идентичны по SHA-256.'
# Q8_0 содержит несколько полных SHA-256 по 50.66 ГиБ: при повторном запуске
# вывод прогресса обязателен, иначе это выглядит как безусловное зависание.
$Q8Text = Get-Content -LiteralPath $PersonalFile -Raw -Encoding utf8
if ($Q8Text -notmatch '(?m)^function Get-Q8FileSha256WithProgress\s*\{') {
    throw 'Отсутствует контроль прогресса SHA-256 Q8_0; проверьте полноту итерации 048.'
}
if ($Q8Text -notmatch [regex]::Escape("Q8_START_LAST.txt")) {
    throw 'Q8-запускатель не записывает контрольные точки: Q8_START_LAST.txt.'
}
if ($Q8Text -notmatch [regex]::Escape('копия PLE на R:')) {
    throw 'Q8-запускатель не сообщает о проверке 50.66-ГиБ PLE на RAM-диске.'
}
Write-Host '[OK] Q8: этапы подготовки и прогресс полного SHA-256 поддерживаются.'
# Пользовательские конфиги должны быть READ-ONLY: прежние сценарии
# перезаписывали корневой JSON при каждом запуске, теряя значения args.
$ProtectedLaunchers = @('START-IQ3S-RAM.ps1',
    'PERSONAL_START_E_ai_Strata-Q4-Fork\START-Q4-RAM.ps1',
    'PERSONAL_START_E_ai_Strata-Q4-Fork\START-HUIHUI-Q4-RAM.ps1',
    'PERSONAL_START_E_ai_Strata-Q4-Fork\START-Q8-RAM.ps1')
foreach ($Relative in $ProtectedLaunchers) {
    $Body = Get-Content -LiteralPath (Join-Path $Root $Relative) -Raw -Encoding utf8
    if ($Body -notmatch 'New-StrataModelRuntimeConfig' -or
        $Body -match 'Write-StrataModelConfiguration' -or
        $Body -match '(?m)\[IO\.File\]::Replace\(\$TemporaryConfig') {
        throw "Устаревший запускатель изменяет пользовательский JSON: $Relative"
    }
    Write-Host "[OK] Пользовательский JSON защищён от записи: $Relative"
}
$Common = Get-Content -LiteralPath (Join-Path $Root 'STRATA-MODEL-LAUNCH-COMMON.ps1') -Raw -Encoding utf8
if ($Common -notmatch 'New-StrataModelRuntimeConfig' -or
    $Common -notmatch 'IsNullOrWhiteSpace\(\$ReportedLabel\)') {
    throw 'Нет общего модуля независимых runtime-конфигов или поддержки RamDisk.'
}
Write-Host '[OK] Совместимость с ранее созданным R: RamDisk и отдельные runtime-конфиги.'


foreach ($Name in @('tools\ensure_gguf_py.py', 'tools\_paths.py')) {
    $Path = Join-Path $Root $Name
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Не найден обязательный компонент проверки GGUF: $Name"
    }
    Write-Host "[OK] $Name"
}
Write-Host '[OK] Синтаксис, параметры и согласованность запускателей проверены; модели и RAM-диск не затрагивались.' -ForegroundColor Green