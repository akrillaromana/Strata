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
    'TEST-REQUESTS.ps1',
    'TEST-PCIE-PARITY.ps1',
    'BUILD_AND_START_IQ3S.ps1'
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
                        'PackSource', 'MtpSource', 'Detached', 'Foreground', 'IgnoreAutotune', 'ExpertParityCuda')
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
            throw "Устаревший Q8-запускатель: $Relative не поддерживает -$ParameterName. Обновите весь комплект итерации 057."
        }
    }
    Write-Host "[OK] Q8 -PreparePack / -AllowBf16Conversion: $Relative"
}
$PersonalFile = Join-Path $Root $Q8Launchers[1]
$MirrorFile = Join-Path $Root $Q8Launchers[2]
$PersonalIdentity = Get-Item -LiteralPath $PersonalFile
$MirrorIdentity = Get-Item -LiteralPath $MirrorFile
if (-not [string]::Equals($PersonalIdentity.Name, $MirrorIdentity.Name, [StringComparison]::OrdinalIgnoreCase) -or
    [int64]$PersonalIdentity.Length -ne [int64]$MirrorIdentity.Length) {
    throw 'Личный и зеркальный запускатели Q8 различаются. Требуется согласованный комплект итерации 057.'
}
Write-Host '[OK] Обе внутренние копии Q8 совпадают по имени и точному размеру.'
# Q8_0 больше не читает десятки гигабайт ради контрольных сумм: идентичность
# файлов определяется только именем и точным размером в байтах.
$Q8Text = Get-Content -LiteralPath $PersonalFile -Raw -Encoding utf8
if ($Q8Text -match 'Get-FileHash|SHA-?256|IncrementalHash') {
    throw 'Q8-запускатель всё ещё содержит SHA-проверку файлов.'
}
if ($Q8Text -notmatch [regex]::Escape("Q8_START_LAST.txt")) {
    throw 'Q8-запускатель не записывает контрольные точки: Q8_START_LAST.txt.'
}
if ($Q8Text -notmatch [regex]::Escape('точному размеру')) {
    throw 'Q8-запускатель не проверяет PLE по имени и точному размеру.'
}
Write-Host '[OK] Q8: SHA-проверки файлов отсутствуют; используется имя + точный размер.'
# Экспериментальный parity-режим Q8 должен быть opt-in и fail-closed.
foreach ($Relative in $Q8Launchers) {
    $Body = Get-Content -LiteralPath (Join-Path $Root $Relative) -Raw -Encoding utf8
    if ($Body -notmatch 'ExpertParityCuda') { throw "Q8 parity switch отсутствует: $Relative" }
}
$Q8ConfigText = Get-Content -LiteralPath (Join-Path $Root 'strata-unsloth-q8_0.json') -Raw -Encoding utf8
if ($Q8ConfigText -match '--expert-parity') {
    throw 'Экспериментальный --expert-parity не должен быть включён в пользовательском Q8 JSON по умолчанию.'
}
foreach ($Name in @('START-Q8-PARITY.bat','TEST-PCIE-PARITY.bat','TEST-PCIE-PARITY.ps1','BUILD-Q8-PARITY.bat')) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $Name) -PathType Leaf)) { throw "Нет parity-компонента: $Name" }
}
$ParityTestText = Get-Content -LiteralPath (Join-Path $Root 'TEST-PCIE-PARITY.ps1') -Raw -Encoding utf8
foreach ($Needle in @('0.0','0.2','0.26','0.5','1.0','temperature = 0','PCIE_PARITY_LAST.json')) {
    if ($ParityTestText -notmatch [regex]::Escape($Needle)) { throw "TEST-PCIE-PARITY.ps1 не содержит $Needle" }
}
$BuildText = Get-Content -LiteralPath (Join-Path $Root 'BUILD_AND_START_IQ3S.ps1') -Raw -Encoding utf8
if ($BuildText -notmatch 'ParityTest' -or $BuildText -notmatch 'cuda-placement-parity-q8') {
    throw 'Сборка не содержит fail-closed CPU/CUDA Q8 parity test.'
}
Write-Host '[OK] Q8 parity: opt-in, прямой CPU/CUDA тест перед установкой engine и pcie=0..1 end-to-end тест.'

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
if ($Common -notmatch "-s 54G -m 'R:'" -or $Common -notmatch '\$MinimumBytes = 53GB') {
    throw 'Общий RAM-диск должен создаваться как 54 GiB и принимать номинальный 54 GiB том (>=53 GiB после форматирования).'
}
foreach ($Relative in @('START-IQ3S-RAM.ps1','PERSONAL_START_E_ai_Strata-Q4-Fork\START-Q8-RAM.ps1','PERSONAL_START_E_ai_Strata-Q4-Fork\START-Q6-RAM.ps1','PERSONAL_START_E_ai_Strata-Q4-Fork\START-Q4-RAM.ps1','PERSONAL_START_E_ai_Strata-Q4-Fork\START-HUIHUI-Q4-RAM.ps1')) {
    $RamBody = Get-Content -LiteralPath (Join-Path $Root $Relative) -Raw -Encoding utf8
    if ($RamBody -match '-s 64G' -or $RamBody -match '\$[^\r\n]*Size -lt 60GB') {
        throw "Старый лимит 64/60 GiB остался в активном запускателе: $Relative"
    }
}
Write-Host '[OK] RAM-диск: новый размер 54 GiB; старые 64G/60GB лимиты из активных запускателей удалены.'


foreach ($Name in @('tools\ensure_gguf_py.py', 'tools\_paths.py')) {
    $Path = Join-Path $Root $Name
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Не найден обязательный компонент проверки GGUF: $Name"
    }
    Write-Host "[OK] $Name"
}
Write-Host '[OK] Синтаксис, параметры и согласованность запускателей проверены; модели и RAM-диск не затрагивались.' -ForegroundColor Green

# Q6_K должен иметь отдельный opt-in engine и три согласованные копии запускателя.
$Q6Launchers = @(
    'START-Q6-RAM.ps1',
    'PERSONAL_START_E_ai_Strata-Q4-Fork\START-Q6-RAM.ps1',
    'tools\windows\q4-local-profiles\START-Q6-RAM.ps1'
)
$Q6Required = @('PreparePack','AllowBf16Conversion','PrepareOnly','PleToRam','ModelsDirectory','PackSource','MtpSource','Detached','IgnoreAutotune')
foreach ($Relative in $Q6Launchers) {
    $File = Join-Path $Root $Relative
    $Tokens=$null; $Errors=$null
    $Ast=[System.Management.Automation.Language.Parser]::ParseFile($File,[ref]$Tokens,[ref]$Errors)
    if($Errors.Count -gt 0 -or $null -eq $Ast.ParamBlock){throw "Некорректный Q6 запускатель: $Relative"}
    $Names=@($Ast.ParamBlock.Parameters|ForEach-Object{$_.Name.VariablePath.UserPath})
    foreach($Name in $Q6Required){if($Names -cnotcontains $Name){throw "Q6 запускатель $Relative не поддерживает -$Name"}}
    $Body=Get-Content -LiteralPath $File -Raw -Encoding utf8
    if($Body -match 'Get-FileHash|SHA-?256|IncrementalHash'){throw "Q6 запускатель содержит SHA-проверку: $Relative"}
    if($Body -notmatch 'engine-q6\\strata\.exe' -or $Body -notmatch 'New-StrataModelRuntimeConfig'){throw "Q6 запускатель не использует отдельный engine/runtime config: $Relative"}
    Write-Host "[OK] Q6 launch contract: $Relative"
}
$Q6A=Get-Item -LiteralPath (Join-Path $Root $Q6Launchers[1]); $Q6B=Get-Item -LiteralPath (Join-Path $Root $Q6Launchers[2])
if(-not [string]::Equals($Q6A.Name,$Q6B.Name,[StringComparison]::OrdinalIgnoreCase) -or [int64]$Q6A.Length -ne [int64]$Q6B.Length){throw 'Внутренние Q6-запускатели различаются по имени/точному размеру.'}
$Q6Build=Get-Content -LiteralPath (Join-Path $Root 'BUILD-Q6-ENGINE.ps1') -Raw -Encoding utf8
foreach($Needle in @('STRATA_Q6K_EXPERTS=ON','STRATA_MMQ_KQUANTS=ON','engine-q6')){if($Q6Build -notmatch [regex]::Escape($Needle)){throw "BUILD-Q6-ENGINE.ps1 не содержит $Needle"}}
if($Q6Build -match 'Get-FileHash|SHA-?256|IncrementalHash'){throw 'Q6 build script содержит SHA-проверку.'}
foreach($Name in @('tools\q6_ple_preflight.py','strata-unsloth-q6_k-RAM.json','SETUP-Q6.bat','START-Q6-K.bat','START-HERE Q6_K.bat','PREPARE-Q6.bat','TUNE-Q6.bat','BENCHMARK-Q6.bat','TEST-Q6.bat','VERIFY-Q6.bat','VERIFY-Q6-API.ps1','GET-Q6-DIAGNOSTICS.ps1','GET-Q6-DIAGNOSTICS.bat')){
    if(-not(Test-Path -LiteralPath (Join-Path $Root $Name) -PathType Leaf)){throw "Не найден Q6 компонент: $Name"}
}
# Q6_K должен быть именно пользовательским пятишардовым профилем, а его
# стартовые параметры должны совпадать с Q8_0. Различаются только пути/имя.
$Q6Config = Get-Content -LiteralPath (Join-Path $Root 'strata-unsloth-q6_k-RAM.json') -Raw -Encoding utf8 | ConvertFrom-Json
$Q8Config = Get-Content -LiteralPath (Join-Path $Root 'strata-unsloth-q8_0.json') -Raw -Encoding utf8 | ConvertFrom-Json
if ([string]$Q6Config.model_name -ne 'qwen3.8-flash-next-unsloth-q6_k') { throw 'Неверный model_name Q6_K.' }
$Q6Text = Get-Content -LiteralPath (Join-Path $Root 'START-Q6-RAM.ps1') -Raw -Encoding utf8
if ($Q6Text -match '00006|_XL|UD-') { throw 'Q6 launcher содержит чужой шестишардовый или XL/UD профиль.' }
if ($Q6Text -notmatch 'Qwen3\.8-Flash-Next-Q6_K-00001-of-00005\.gguf') { throw 'Q6 launcher не закреплён на пятишардовом Q6_K.' }
$PathFlags = @('--pack','--native','--expert-profile','--mtp')
function Get-ComparableArgs($Cfg) {
    $A = @($Cfg.args | ForEach-Object { [string]$_ })
    foreach ($Flag in $PathFlags) {
        $I = [Array]::IndexOf($A, $Flag)
        if ($I -lt 0 -or ($I + 1) -ge $A.Count) { throw "Нет $Flag в конфиге" }
        $A[$I + 1] = "<$Flag>"
    }
    return ($A -join "`n")
}
if ((Get-ComparableArgs $Q6Config) -cne (Get-ComparableArgs $Q8Config)) {
    throw 'Начальные параметры Q6_K не совпадают с Q8_0.'
}
Write-Host '[OK] Q6_K: ровно 5 шардов; стартовые параметры совпадают с Q8_0.'
Write-Host '[OK] Q6_K: отдельный engine, pack/preflight, RAM launcher, BAT, benchmark/autotune/test.'

foreach ($Name in @('tools\ensure_gguf_py.py', 'tools\_paths.py')) {
    $Path = Join-Path $Root $Name
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Не найден обязательный компонент проверки GGUF: $Name"
    }
    Write-Host "[OK] $Name"
}
Write-Host '[OK] Синтаксис, параметры и согласованность запускателей проверены; модели и RAM-диск не затрагивались.' -ForegroundColor Green
