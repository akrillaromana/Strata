#requires -Version 7.0
# Дополнительные варианты Qwen3.8-Flash-Next из E:\ai\models.
# Никакие исходные GGUF, пользовательские JSON и существующие каталоги pack не перезаписываются.
[CmdletBinding()]
param(
    [string]$Name,
    [switch]$List,
    [switch]$Prepare,
    [switch]$PrepareOnly,
    [switch]$AllowBf16Conversion
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Root = $PSScriptRoot
$CatalogPath = Join-Path $Root 'MODEL-CATALOG.json'
$Catalog = Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable -ErrorAction Stop

if ($List) {
    foreach ($Item in $Catalog.models) {
        $Download = if (Test-Path -LiteralPath $Item.first_shard -PathType Leaf) {
            'файл найден'
        } elseif (@(Get-ChildItem -LiteralPath (Split-Path -Parent $Item.first_shard) -Filter '*.part' -File -ErrorAction SilentlyContinue).Count) {
            'ожидание загрузки'
        } else {
            'файл отсутствует'
        }
        $EngineState = if ($Item.architecture -eq 'qwen4exp') { 'доступен pack/engine' } else { 'движок пока не поддерживает' }
        '{0,-34} {1,-16} {2,-23} {3}' -f $Item.id, $Item.quant, $Download, $EngineState
    }
    return
}
if ([string]::IsNullOrWhiteSpace($Name)) {
    throw 'Укажите -Name <имя из списка> либо выполните .\START-CATALOG-MODEL.ps1 -List'
}
$SelectedProfiles = @($Catalog.models | Where-Object { $_.id -ceq $Name })
if ($SelectedProfiles.Count -ne 1) { throw "Неизвестный или неоднозначный профиль '$Name'. Используйте -List." }
$Model = $SelectedProfiles[0]
if ($Model.architecture -ne 'qwen4exp') {
    throw "Профиль $Name сохранён, но этот strata.exe ещё не умеет архитектуру $($Model.architecture). Требуется нативный перенос из Strata 0.1.45, подмена JSON не поможет."
}

$First = [string]$Model.first_shard
if (-not (Test-Path -LiteralPath $First -PathType Leaf)) {
    $PartFiles = @(Get-ChildItem -LiteralPath (Split-Path -Parent $First) -Filter '*.part' -File -ErrorAction SilentlyContinue)
    $Hint = if ($PartFiles.Count) { ' В каталоге есть файлы .part: дождитесь окончания загрузки и переименования загрузчиком.' } else { '' }
    throw "Не найден готовый первый сегмент: $First.$Hint"
}

$Engine = Join-Path $Root 'engine\strata.exe'
$Server = Join-Path $Root 'serve\server.py'
$Pack = [string]$Model.pack
$Token = Join-Path $Pack 'tokenizer\chat_template.jinja'
$Index = Join-Path $Pack 'index.txt'
$Experts = Join-Path $Pack 'native_experts.txt'
foreach ($Required in @($Engine, $Server, (Join-Path $Root 'tools\iq_pack.py'))) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) { throw "Отсутствует: $Required" }
}

. (Join-Path $Root 'STRATA-MODEL-LAUNCH-COMMON.ps1')
$Python = Resolve-StrataModelPython -Root $Root
Ensure-StrataServerPythonDependencies -Root $Root -Python $Python

if (-not ((Test-Path -LiteralPath $Index -PathType Leaf) -and
           (Test-Path -LiteralPath $Experts -PathType Leaf) -and
           (Test-Path -LiteralPath $Token -PathType Leaf))) {
    if (-not $Prepare -and -not $PrepareOnly) {
        throw "Native pack ещё не подготовлен: $Pack. Запустите снова с -Prepare. Исходные GGUF не изменяются."
    }
    if (Test-Path -LiteralPath $Pack) {
        throw "Каталог pack существует, но не завершён: $Pack. Он не удаляется и не перезаписывается автоматически."
    }
    $Parent = Split-Path -Parent $Pack
    New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    $PreviousStages = @(Get-ChildItem -LiteralPath $Parent -Directory -Filter ('.pending-' + $Name + '-*') -ErrorAction SilentlyContinue)
    if ($PreviousStages.Count) {
        throw "Обнаружена незавершённая подготовка $Name в $Parent. Сохраняю её без удаления; разберите ошибку перед повтором."
    }
    $Stage = Join-Path $Parent ('.pending-' + $Name + '-' + [guid]::NewGuid().ToString('N'))
    $BuilderArgs = @((Join-Path $Root 'tools\iq_pack.py'), '--gguf', $First, '--out', $Stage)
    if ($AllowBf16Conversion) { $BuilderArgs += '--compat-bf16' }
    Write-Host "Подготовка нового пакета в $Stage; файлы модели только читаются."
    & $Python @BuilderArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Подготовка завершилась с ошибкой. Незавершённые данные оставлены для диагностики: $Stage"
    }
    foreach ($Required in @('index.txt', 'native_experts.txt', 'tokenizer\chat_template.jinja')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Stage $Required) -PathType Leaf)) {
            throw "Pack неполный: $Stage; отсутствует $Required. Папка оставлена без удаления."
        }
    }
    if (Test-Path -LiteralPath $Pack) { throw "Целевой каталог появился во время сборки: $Pack" }
    Move-Item -LiteralPath $Stage -Destination $Pack -ErrorAction Stop
    Write-Host "Pack подготовлен: $Pack" -ForegroundColor Green
}
if ($PrepareOnly) { return }

Assert-StrataModelServerStopped -Port 8080
Assert-StrataModelEngineStopped -Root $Root
$LogDir = Join-Path $Root ('logs\catalog\' + $Name)
$DllDirs = @(Initialize-StrataModelDlls -Root $Root -Engine $Engine -LogDirectory $LogDir)
$D = $Catalog.defaults
$ArgsList = [System.Collections.Generic.List[string]]::new()
foreach ($Part in @('--pack', $Pack, '--native', $First,
                    '--expert-profile', (Join-Path $Root 'data\expert-profile.bin'),
                    '--expert-cache', 'auto', '--prefill', 'auto',
                    '--pcie-frac', ([string]$D.pcie_frac), '--spec', ([string]$D.spec),
                    '--spec-min-p', ([string]$D.spec_min_p), '--suffix-draft', '0',
                    '--max-context', ([string]$D.max_context), '--kv', ([string]$D.kv),
                    '--kv-resident', ([string]$D.kv_resident),
                    '--resident-budget-gib', ([string]$(if ($Model.ContainsKey('resident_budget_gib')) { $Model.resident_budget_gib } else { $D.resident_budget_gib })),
                    '--adapt-every', '0', '--adapt-swaps', '0', '--prompt-cache', '0')) {
    $ArgsList.Add([string]$Part)
}
$MtpDir = [string]$D.mtp_runtime
if (-not (Test-Path -LiteralPath $MtpDir -PathType Container)) {
    throw "Не найден готовый MTP runtime: $MtpDir. У движка этой итерации режим --serve пока требует MTP."
}
$ArgsList.Add('--mtp')
$ArgsList.Add($MtpDir)
if (-not (Test-Path -LiteralPath (Join-Path $Root 'data\expert-profile.bin') -PathType Leaf)) {
    throw 'Отсутствует data\expert-profile.bin; генерация профиля не выполняется автоматически.'
}
$RuntimeConfig = [ordered]@{
    exe = $Engine
    args = @($ArgsList.ToArray())
    cwd = $Root
    tokenizer = (Join-Path $Pack 'tokenizer')
    model_name = [string]$Model.id
    reasoning_budget_tokens = [int]$D.reasoning_budget_tokens
    autotune = $false
    parallel = [int]$D.parallel
    log = (Join-Path $LogDir 'engine.log')
    lib_dirs = @($DllDirs)
    host = '0.0.0.0'
    port = 8080
    gpu = 0
    gpus_asked = $true
}
$RuntimeName = ('runtime-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.json')
$RuntimePath = Join-Path $LogDir $RuntimeName
[IO.File]::WriteAllText($RuntimePath, (($RuntimeConfig | ConvertTo-Json -Depth 64) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
Write-Host "Модель: $Name | PCIe=$($D.pcie_frac) | MTP=$($D.spec_min_p) | parallel=$($D.parallel)"
Write-Host "GGUF E: читается непосредственно; копирование в R: в этом универсальном запускателе не выполняется."
Write-Host "Исходный каталог и исходные GGUF не изменяются. Временная конфигурация: $RuntimePath"
Write-Host 'Для остановки нажмите Ctrl+C.'
& $Python -u $Server --engine strata --config $RuntimePath --host 0.0.0.0 --port 8080
exit $LASTEXITCODE
