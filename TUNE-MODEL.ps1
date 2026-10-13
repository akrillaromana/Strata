#requires -Version 7.0
<#
Универсальный калибровщик моделей Strata. Без параметра -Model показывает список профилей.
Не переключает и не загружает другую модель: выбранная модель должна уже работать на -Port.
-Apply сохраняет профиль только после измеренного ускорения; профиль применяется сервером при следующем запуске.
#>
[CmdletBinding()]
param(
    [string]$Model,
    [string]$ConfigPath,
    [ValidateRange(1,65535)][int]$Port = 8080,
    [ValidateRange(2,5)][int]$Rounds = 3,
    [ValidateRange(96,1024)][int]$MaxTokens = 192,
    [ValidateRange(0.01,0.20)][double]$MinGain = 0.03,
    [switch]$Apply
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Invariant = [Globalization.CultureInfo]::InvariantCulture
$Api = "http://127.0.0.1:$Port"
$Headers = @{ 'Content-Type' = 'application/json; charset=utf-8' }

function Get-FlagValue([string[]]$Arguments, [string]$Flag) {
    $I = [array]::IndexOf($Arguments, $Flag)
    if ($I -lt 0 -or $I + 1 -ge $Arguments.Count) { return $null }
    return [string]$Arguments[$I + 1]
}
function Parse-Probability([string]$Text, [string]$Name) {
    if ($null -eq $Text) { return $null }
    $Number = [double]0
    if (-not [double]::TryParse($Text, [Globalization.NumberStyles]::Float, $Invariant, [ref]$Number) -or
        [double]::IsNaN($Number) -or $Number -lt 0 -or $Number -gt 1) {
        throw "Недопустимый параметр ${Name}: $Text"
    }
    return $Number
}
function Get-TuningMedian([double[]]$Numbers) {
    if ($Numbers.Count -eq 0) { throw 'Нет достоверных результатов измерений.' }
    $Ordered = @($Numbers | Sort-Object)
    $Half = [int][math]::Floor($Ordered.Count / 2)
    if ($Ordered.Count % 2) { return [double]$Ordered[$Half] }
    return ([double]$Ordered[$Half - 1] + [double]$Ordered[$Half]) / 2.0
}
function Get-Profile([string]$Path) {
    try {
        $Cfg = Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json -ErrorAction Stop
        if ($Cfg -isnot [pscustomobject]) { return $null }
        # Служебные JSON (общие настройки, автоподбор) не являются профилями.
        # Проверка наличия свойств должна предшествовать обращению к ним при StrictMode.
        foreach ($Name in @('model_name', 'exe', 'args')) {
            if ($null -eq $Cfg.PSObject.Properties[$Name]) { return $null }
        }
        if ($Cfg.model_name -isnot [string] -or [string]::IsNullOrWhiteSpace($Cfg.model_name) -or
            $Cfg.exe -isnot [string] -or [string]::IsNullOrWhiteSpace($Cfg.exe) -or
            $Cfg.args -isnot [array] -or $Cfg.args.Count -eq 0) { return $null }
        return [pscustomobject]@{ Path = $Path; Config = $Cfg; Model = [string]$Cfg.model_name }
    } catch {
        Write-Warning "Пропущен повреждённый профиль ${Path}: $($_.Exception.Message)"
        return $null
    }
}

$Available = [System.Collections.Generic.List[object]]::new()
if ($ConfigPath) {
    $Resolved = (Resolve-Path -LiteralPath $ConfigPath -ErrorAction Stop).Path
    $Chosen = Get-Profile $Resolved
    if (-not $Chosen) { throw "Недействительный профиль: $Resolved" }
    $Available.Add($Chosen)
} else {
    # Копии одного шаблона в трёх каталогах не должны занимать три пункта меню.
    # Приоритет: рабочая конфигурация из корня, затем личная, затем шаблон.
    $SeenNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($Dir in @($Root, (Join-Path $Root 'PERSONAL_START_E_ai_Strata-Q4-Fork'),
                        (Join-Path $Root 'tools\windows\q4-local-profiles'))) {
        if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { continue }
        foreach ($File in @(Get-ChildItem -LiteralPath $Dir -Filter '*.json' -File | Sort-Object Name)) {
            if ($File.Name.EndsWith('.shared-settings.json', [StringComparison]::OrdinalIgnoreCase) -or
                $File.Name.EndsWith('.autotune.json', [StringComparison]::OrdinalIgnoreCase)) { continue }
            if ($SeenNames.Contains($File.Name)) { continue }
            $Profile = Get-Profile $File.FullName
            if ($Profile) {
                $Available.Add($Profile)
                $null = $SeenNames.Add($File.Name)
            }
        }
    }
}
if ($Available.Count -eq 0) {
    throw 'Конфигурации моделей не найдены. Запустите сервер модели или укажите -ConfigPath.'
}

Write-Host '=== КАЛИБРОВКА МОДЕЛЕЙ STRATA ===' -ForegroundColor Cyan
Write-Host 'Какую модель калибруем?'
for ($I = 0; $I -lt $Available.Count; $I++) {
    Write-Host ('  {0,2}. {1}  [{2}]' -f ($I + 1), $Available[$I].Model,
                (Split-Path -Leaf $Available[$I].Path))
}
$Selected = $null
if ($ConfigPath) {
    $Selected = $Available[0]
} elseif ($Model) {
    $ProfileMatches = @($Available | Where-Object { $_.Model -eq $Model -or
        (Split-Path -Leaf $_.Path) -eq $Model })
    if ($ProfileMatches.Count -ne 1) {
        throw "Неоднозначная/неизвестная модель '$Model'. Используйте -ConfigPath для точного выбора профиля."
    }
    $Selected = $ProfileMatches[0]
} else {
    $InputNumber = Read-Host 'Введите номер модели из списка'
    $SelectedNumber = 0
    if (-not [int]::TryParse($InputNumber, [ref]$SelectedNumber) -or
        $SelectedNumber -lt 1 -or $SelectedNumber -gt $Available.Count) {
        throw 'Номер модели неверен. Конфигурации и сервер не изменены.'
    }
    $Selected = $Available[$SelectedNumber - 1]
}
$Cfg = $Selected.Config
$ModelName = $Selected.Model
$EngineArguments = [string[]]@($Cfg.args)
$Native = Get-FlagValue $EngineArguments '--native'
if (-not $Native) { throw 'Для этого профиля нет --native; безопасная привязка к модели пока невозможна.' }
$Exe = [string]$Cfg.exe
if (-not [IO.Path]::IsPathRooted($Exe)) {
    $WorkDir = if ($null -ne $Cfg.PSObject.Properties['cwd'] -and $Cfg.cwd) {
        [string]$Cfg.cwd
    } else { Split-Path -Parent $Selected.Path }
    $Exe = Join-Path $WorkDir $Exe
}
if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) { throw "Движок отсутствует: $Exe" }

if ($Cfg.PSObject.Properties['api_key'] -and $Cfg.api_key) {
    $Headers.Authorization = "Bearer $($Cfg.api_key)"
}
$Health = Invoke-RestMethod -Uri "$Api/health" -Headers $Headers -TimeoutSec 15
if ($Health.status -ne 'ok' -or $Health.loaded -ne $true) {
    throw 'Сервер не загрузил модель. Запустите выбранный профиль и повторите калибровку.'
}
$List = Invoke-RestMethod -Uri "$Api/v1/models" -Headers $Headers -TimeoutSec 15
if (@($List.data | Where-Object { $_.id -eq $ModelName }).Count -ne 1) {
    throw "Выбрана $ModelName, но на порту $Port запущена другая модель. Ничего не изменено."
}
$Properties = Invoke-RestMethod -Uri "$Api/props" -Headers $Headers -TimeoutSec 15
if (-not $Properties.model_path) {
    throw 'Сервер не раскрыл путь активной модели (/props). Нельзя безопасно сопоставить профиль.'
}
if (-not [string]::Equals([string]$Properties.model_path, $Native,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "Выбранный профиль не соответствует работающей модели. Сервер: $($Properties.model_path); профиль: $Native"
}
$BaselinePcie = Parse-Probability (Get-FlagValue $EngineArguments '--pcie-frac') 'pcie-frac'
$BaselineSpec = Parse-Probability (Get-FlagValue $EngineArguments '--spec-min-p') 'spec-min-p'
$SpecEnabled = ($null -ne (Get-FlagValue $EngineArguments '--spec') -and
    (Get-FlagValue $EngineArguments '--spec') -ne '0' -and $null -ne (Get-FlagValue $EngineArguments '--mtp'))
$Prompts = @(
  'Объясни подробно механизм ускорения нейросетей с ограниченной видеопамятью, включая кеширование экспертов и передачу данных PCIe. Напиши несколько абзацев.',
  'Подробно сравни предварительную обработку длинного контекста с последовательной генерацией токенов. Приведи примеры оптимизации и ограничения.',
  'Объясни принципы работы спекулятивного декодирования и компромисс между скоростью, памятью и качеством. Ответь развёрнуто.'
)
$Samples = [System.Collections.Generic.List[object]]::new()
function Invoke-TuningSample([object]$Pcie, [object]$Spec, [int]$Round, [string]$Stage) {
    $Prompt = $Prompts[($Round - 1) % $Prompts.Count]
    $Body = @{
        model = $ModelName
        messages = @(@{ role='user'; content=$Prompt })
        stream = $false
        temperature = 0
        max_tokens = $MaxTokens
        reasoning_budget_tokens = 0
        chat_template_kwargs = @{ enable_thinking = $false }
    }
    $Tune = @{}
    if ($null -ne $Pcie) { $Tune.pcie_frac = [double]$Pcie }
    if ($null -ne $Spec -and $SpecEnabled) { $Tune.spec_min_p = [double]$Spec }
    if ($Tune.Count) { $Body.strata_tune = $Tune }
    $Json = $Body | ConvertTo-Json -Depth 12 -Compress
    $Answer = Invoke-RestMethod -Uri "$Api/v1/chat/completions" -Method Post -Headers $Headers `
        -Body ([Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 600
    if (-not $Answer.timings) { throw 'Нет серверных timings; измерение не принято.' }
    $Speed = [double]$Answer.timings.predicted_per_second
    $Tokens = [int]$Answer.timings.predicted_n
    if ($Tokens -lt 16 -or $Speed -le 0 -or [double]::IsNaN($Speed) -or
        [double]::IsInfinity($Speed)) {
        throw "Недостаточно достоверных токенов для сравнения: ${Tokens}, скорость ${Speed}."
    }
    $Samples.Add([pscustomobject]@{
        stage=$Stage; round=$Round; pcie_frac=$Pcie; spec_min_p=$Spec
        decode_tok_s=$Speed; output_tokens=$Tokens
        prefill_tok_s=$Answer.timings.prompt_per_second
    })
    Write-Host ('  {0} | PCIe={1} | MTP={2} | {3:0.0} ток/с' -f $Stage, $Pcie, $Spec, $Speed)
    return $Speed
}
function Measure-TuningCandidates([object[]]$Values, [string]$Axis, [object]$Fixed) {
    $History = @{}
    foreach ($Value in $Values) {
        $Key = if ($null -eq $Value) { 'auto' } else { ([double]$Value).ToString('0.0000', $Invariant) }
        $History[$Key] = [System.Collections.Generic.List[double]]::new()
    }
    for ($Round = 1; $Round -le $Rounds; $Round++) {
        $Order = @($Values)
        if ($Round % 2 -eq 0) { [array]::Reverse($Order) }
        foreach ($Value in $Order) {
            $Pcie = if ($Axis -eq 'pcie') { $Value } else { $Fixed }
            $Spec = if ($Axis -eq 'spec') { $Value } else { $BaselineSpec }
            if ($Axis -eq 'pcie') { $Spec = $BaselineSpec }
            $ValueKey = if ($null -eq $Value) { 'auto' } else { ([double]$Value).ToString('0.0000', $Invariant) }
            $History[$ValueKey].Add([double](Invoke-TuningSample $Pcie $Spec $Round $Axis))
        }
    }
    $Results = @{}
    foreach ($Value in $Values) {
        $ValueKey = if ($null -eq $Value) { 'auto' } else { ([double]$Value).ToString('0.0000', $Invariant) }
        $Results[$ValueKey] = Get-TuningMedian $History[$ValueKey].ToArray()
    }
    return $Results
}
function Get-TuningScore([hashtable]$Results, [object]$Value) {
    $K = if ($null -eq $Value) { 'auto' } else { ([double]$Value).ToString('0.0000', $Invariant) }
    return [double]$Results[$K]
}

Write-Host "Выбрана: $ModelName" -ForegroundColor Cyan
Write-Host "Профиль: $($Selected.Path)"
Write-Host "Движок: $Exe"
Write-Host "Исходное PCIe=$BaselinePcie, MTP=$BaselineSpec. Измерение не изменит работающий профиль."
$null = Invoke-TuningSample $BaselinePcie $BaselineSpec 1 'warmup'
$PcieValues = @($BaselinePcie)
foreach ($Value in @(0.0,0.2,0.35,0.55,0.75,1.0)) {
    if ($null -eq $BaselinePcie -or $Value -ne $BaselinePcie) { $PcieValues += $Value }
}
$PcieScores = Measure-TuningCandidates $PcieValues 'pcie' $BaselineSpec
$BestPcie = $BaselinePcie
foreach ($Candidate in $PcieValues) {
    if ((Get-TuningScore $PcieScores $Candidate) -gt (Get-TuningScore $PcieScores $BestPcie)) { $BestPcie = $Candidate }
}
$BestSpec = $BaselineSpec
$SpecScores = @{}
if ($SpecEnabled) {
    $SpecValues = @($BaselineSpec)
    foreach ($Value in @(0.3,0.5,0.7,0.75,0.9,1)) {
        if ($null -eq $BaselineSpec -or $Value -ne $BaselineSpec) { $SpecValues += $Value }
    }
    # Здесь фиксируем лучшее значение PCIe и варьируем только порог MTP.
    $SpecScores = Measure-TuningCandidates $SpecValues 'spec' $BestPcie
    foreach ($Candidate in $SpecValues) {
        if ((Get-TuningScore $SpecScores $Candidate) -gt (Get-TuningScore $SpecScores $BestSpec)) { $BestSpec = $Candidate }
    }
} else {
    Write-Host 'Спекулятивный MTP отключён в этой модели: подбор его порога пропущен.'
}
$Base = [System.Collections.Generic.List[double]]::new()
$Trial = [System.Collections.Generic.List[double]]::new()
for ($R = 1; $R -le $Rounds; $R++) {
    if ($R % 2) {
        $Base.Add([double](Invoke-TuningSample $BaselinePcie $BaselineSpec $R 'baseline'))
        $Trial.Add([double](Invoke-TuningSample $BestPcie $BestSpec $R 'candidate'))
    } else {
        $Trial.Add([double](Invoke-TuningSample $BestPcie $BestSpec $R 'candidate'))
        $Base.Add([double](Invoke-TuningSample $BaselinePcie $BaselineSpec $R 'baseline'))
    }
}
$BaseMedian = Get-TuningMedian $Base.ToArray()
$TrialMedian = Get-TuningMedian $Trial.ToArray()
$Gain = $TrialMedian / $BaseMedian - 1.0
$ThresholdDifference = $Gain - $MinGain
$Changed = (($null -eq $BaselinePcie -and $null -ne $BestPcie) -or
            ($null -ne $BaselinePcie -and $BaselinePcie -ne $BestPcie) -or
            ($SpecEnabled -and $BaselineSpec -ne $BestSpec))
$Accepted = $Changed -and $Gain -ge $MinGain
$EngineItem = Get-Item -LiteralPath $Exe -ErrorAction Stop
$NativeItem = Get-Item -LiteralPath $Native -ErrorAction Stop
$SafeModel = ($ModelName -replace '[^A-Za-z0-9._-]+', '_').Trim('_')
$SafeNative = ($NativeItem.Name -replace '[^A-Za-z0-9._-]+', '_').Trim('_')
$SafeEngine = ($EngineItem.Name -replace '[^A-Za-z0-9._-]+', '_').Trim('_')
$Key = '{0}--{1}--{2}--{3}--{4}' -f $SafeModel, $SafeNative, $NativeItem.Length, $SafeEngine, $EngineItem.Length
$ReportDir = Join-Path $Root 'logs\autotune'
$ProfileDir = Join-Path $Root 'model-autotune'
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
$ReportPath = Join-Path $ReportDir "$Key-LAST.json"
$Settings = @{}
if ($Accepted) {
    if ($null -ne $BestPcie) { $Settings.pcie_frac = [double]$BestPcie }
    if ($SpecEnabled -and $null -ne $BestSpec) { $Settings.spec_min_p = [double]$BestSpec }
}
$Report = [ordered]@{
    version=2; timestamp=(Get-Date -Format o); model_name=$ModelName
    profile=$Selected.Path; native=$Native; profile_key=$Key
    native_name=$NativeItem.Name; native_bytes=[int64]$NativeItem.Length
    engine_name=$EngineItem.Name; engine_bytes=[int64]$EngineItem.Length
    baseline=@{pcie_frac=$BaselinePcie; spec_min_p=$BaselineSpec; decode_tok_s=$BaseMedian}
    candidate=@{pcie_frac=$BestPcie; spec_min_p=$BestSpec; decode_tok_s=$TrialMedian}
    measured_gain_percent=[math]::Round(100 * $Gain,5); min_gain=$MinGain
    threshold_difference_percent=[math]::Round(100 * $ThresholdDifference,5)
    accepted=$Accepted; settings=$Settings
    pcie_medians=$PcieScores; spec_medians=$SpecScores; samples=@($Samples.ToArray())
}
$Report | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $ReportPath -Encoding utf8
Write-Host ('База: {0:0.000} ток/с; кандидат: {1:0.000} ток/с; прирост: {2:+0.000;-0.000;0.000}%; порог: {3:0.000}%' -f `
    $BaseMedian, $TrialMedian, (100 * $Gain), (100 * $MinGain))
Write-Host "Отчёт: $ReportPath"
if (-not $Accepted) {
    if ($Changed -and $Gain -gt 0 -and $Gain -lt $MinGain) {
        Write-Host ('Прирост ниже порога на {0:0.000} процентного пункта; округление до одного знака могло показать ровно порог.' -f (-100 * $ThresholdDifference))
    } else {
        Write-Host 'Кандидат не доказал преимущества относительно исходного профиля.'
    }
    Write-Host 'Ни исходный профиль, ни прежние настройки не меняются.'
} elseif ($Apply) {
    New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null
    $OutFile = Join-Path $ProfileDir "$Key.json"
    $Tuning = [ordered]@{
        version=2; saved_at=(Get-Date -Format o); model_name=$ModelName; native=$Native
        profile_key=$Key; native_name=$NativeItem.Name; native_bytes=[int64]$NativeItem.Length
        engine_name=$EngineItem.Name; engine_bytes=[int64]$EngineItem.Length; settings=$Settings
    }
    $Tmp = "$OutFile.tmp-$([guid]::NewGuid().ToString('N'))"
    try {
        [IO.File]::WriteAllText($Tmp, ($Tuning | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $OutFile -PathType Leaf) {
            [IO.File]::Replace($Tmp, $OutFile, "$OutFile.bak")
        } else { [IO.File]::Move($Tmp, $OutFile) }
    } finally {
        if (Test-Path -LiteralPath $Tmp) { Remove-Item -LiteralPath $Tmp -Force }
    }
    Write-Host "Сохранено только для $ModelName : $OutFile" -ForegroundColor Green
    Write-Host 'Результат будет применён только при следующем запуске выбранной модели.'
} else {
    Write-Host 'Это тестовый прогон. Для сохранения запустите калибровку с -Apply.'
}
