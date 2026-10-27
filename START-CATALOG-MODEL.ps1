#requires -Version 7.0
# Единый интерактивный запускатель всех моделей из configs\MODEL-CATALOG.json.
# Вопросы при запуске: модель -> vision -> RAM-диск (режим, буква, размер) -> настройки
# (макс. токены, thinking, temperature, top_k, top_p, min_p; эталон - значения IQ3_S).
# RAM-диск пересоздаётся и веса перекидываются только если изменились модель, буква или
# размер; при прежнем запуске той же модели с теми же параметрами диск переиспользуется.
# Никакие исходные GGUF, пользовательские JSON и существующие каталоги pack не перезаписываются.
[CmdletBinding()]
param(
    [string]$Name,
    [switch]$List,
    [switch]$Prepare,
    [switch]$PrepareOnly,
    [switch]$AllowBf16Conversion,
    [switch]$NoVision,
    [switch]$Vision,
    [ValidateSet('Default', 'Use', 'None')]
    [string]$RamDisk = 'Default',
    [ValidatePattern('^[A-Za-z]$')]
    [string]$RamLetter = 'R',
    [int]$RamSizeGiB = 0,
    [hashtable]$SamplingOverride = @{},
    [int]$ReasoningBudget = -1
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Root = $PSScriptRoot
$CatalogPath = Join-Path $Root 'configs\MODEL-CATALOG.json'
$Catalog = Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable -ErrorAction Stop

# Эталон значений по умолчанию = IQ3_S (configs\strata-iq3_s-RAM.json): greedy, без фильтров,
# бюджет thinking 10240, макс. токены запроса не ограничены (0 = до конца контекста).
$Ref = [ordered]@{
    max_tokens              = 0
    reasoning_budget_tokens = 10240
    temperature             = 0.0
    top_k                   = 0
    top_p                   = 1.0
    min_p                   = 0.0
}
$RefLabels = [ordered]@{
    max_tokens              = 'макс. токенов ответа (0 = без ограничения)'
    reasoning_budget_tokens = 'макс. токенов режима thinking'
    temperature             = 'temperature'
    top_k                   = 'top_k (0 = выключен)'
    top_p                   = 'top_p'
    min_p                   = 'min_p'
}

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

function Read-Int([string]$Prompt) {
    while ($true) {
        $answer = Read-Host $Prompt
        if ($answer -match '^\d+$') { return [int]$answer }
        Write-Host 'Нужно целое число.' -ForegroundColor Yellow
    }
}

function Read-Number([string]$Prompt) {
    while ($true) {
        $answer = Read-Host $Prompt
        if ($answer -match '^-?\d+(\.\d+)?$') { return [double]$answer }
        Write-Host 'Нужно число (например 0.7 или 20).' -ForegroundColor Yellow
    }
}

function Read-Letter([string]$Prompt) {
    while ($true) {
        $answer = (Read-Host $Prompt).Trim().ToUpper()
        if ($answer -match '^[A-Z]$' -and $answer -ne 'C') { return $answer }
        Write-Host 'Одна буква латиницы, не C.' -ForegroundColor Yellow
    }
}

function Assert-RamLetterUsable([string]$Letter) {
    # Буква должна быть свободна или принадлежать нашему Strata RAM-диску.
    # Физический диск, сетевой том или чужая имитация - отказ.
    $vol = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -eq $Letter.ToUpper() }
    if ($null -eq $vol) { return }
    $root = ('{0}:\' -f $Letter.ToUpper())
    $marker = Join-Path $root 'STRATA_RAM_DISK.marker'
    if ((Test-Path -LiteralPath $marker -PathType Leaf) -or $vol.FileSystemLabel -eq 'STRATA_PLE') { return }
    $desc = if ([string]::IsNullOrWhiteSpace($vol.FileSystemLabel)) { 'том без метки Strata' } else { "метка '$($vol.FileSystemLabel)'" }
    throw "Буква $Letter занята ($desc - физический или чужой виртуальный диск). Использовать её для RAM-диска нельзя - выбери другую букву."
}

$Interactive = [string]::IsNullOrWhiteSpace($Name)
if ($Interactive) {
    $Ready = @($Catalog.models | Where-Object { $_.architecture -eq 'qwen4exp' })
    Write-Host 'Какая модель?' -ForegroundColor Cyan
    for ($i = 0; $i -lt $Ready.Count; $i++) {
        $m = $Ready[$i]
        $state = if (Test-Path -LiteralPath $m.first_shard -PathType Leaf) { 'готова' } else { 'нет файлов' }
        '{0,2}. {1,-26} {2,-14} {3}' -f ($i + 1), $m.id, $m.quant, $state
    }
    $pick = Read-Int 'Номер модели'
    if ($pick -lt 1 -or $pick -gt $Ready.Count) { throw "Нет такого номера: $pick" }
    $Name = [string]$Ready[$pick - 1].id

    if (-not $Vision -and -not $NoVision) {
        $hasMmproj = $Ready[$pick - 1].ContainsKey('mmproj') -and (Test-Path -LiteralPath $Ready[$pick - 1].mmproj -PathType Leaf)
        $mmNote = if ($hasMmproj) { 'mmproj найден' } else { 'mmproj не найден - vision будет недоступен' }
        Write-Host "Vision (картинки): $mmNote" -ForegroundColor Cyan
        $v = Read-Int 'Включить vision? 1 = да, 2 = нет'
        $Vision = ($v -eq 1)
        $NoVision = ($v -eq 2)
    }

    Write-Host ''
    Write-Host 'RAM-диск для весов модели (PLE/n-gram).' -ForegroundColor Cyan
    $r = Read-Int 'RAM-диск: 1 = по умолчанию для этой модели, 2 = юзать, 3 = не юзать'
    switch ($r) {
        1 { $RamDisk = 'Default' }
        2 { $RamDisk = 'Use' }
        3 { $RamDisk = 'None' }
        default { throw "Нет такого варианта: $r" }
    }
    if ($RamDisk -ne 'None') {
        while ($true) {
            $RamLetter = Read-Letter 'Буква RAM-диска (по умолчанию R)'
            try { Assert-RamLetterUsable $RamLetter; break }
            catch { Write-Host $_.Exception.Message -ForegroundColor Red }
        }
        $s = Read-Int 'Размер: 1 = по умолчанию для этой модели, 2 = свой размер в ГиБ'
        if ($s -eq 2) { $RamSizeGiB = Read-Int 'Размер в ГиБ' }
    }

    Write-Host ''
    Write-Host 'Настройки генерации. Эталон по умолчанию - значения IQ3_S.' -ForegroundColor Cyan
    $s = Read-Int 'Оставить настройки по умолчанию? 1 = да, 2 = менять'
    if ($s -eq 2) {
        foreach ($key in $Ref.Keys) {
            Write-Host ("{0}: по умолчанию {1}" -f $RefLabels[$key], $Ref[$key])
            $c = Read-Int '1 = оставить, 2 = своё значение'
            if ($c -eq 2) {
                $val = Read-Number 'Введите значение'
                $SamplingOverride[$key] = $val
            }
        }
    }
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

# Полный список сегментов модели (по суффиксу -0000X-of-0000N у первого сегмента).
$Shards = [System.Collections.Generic.List[object]]::new()
$Leaf = Split-Path -Leaf $First
if ($Leaf -match '^(.*-)(\d{5})-of-(\d{5})(\.gguf)$') {
    $total = [int]$Matches[3]
    $dir = Split-Path -Parent $First
    for ($n = 1; $n -le $total; $n++) {
        $p = Join-Path $dir ('{0}{1:d5}-of-{2:d5}{3}' -f $Matches[1], $n, $total, $Matches[4])
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "Не найден сегмент $n из $total : $p" }
        $Shards.Add((Get-Item -LiteralPath $p))
    }
} else {
    $Shards.Add((Get-Item -LiteralPath $First))
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
    $PackLogDir = Join-Path $Root ('logs\catalog\' + $Name)
    New-Item -ItemType Directory -Path $PackLogDir -Force | Out-Null
    $PackLog = Join-Path $PackLogDir ('iq-pack-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
    $BuilderArgs = @((Join-Path $Root 'tools\iq_pack.py'), '--gguf', $First, '--out', $Stage)
    if ($AllowBf16Conversion) { $BuilderArgs += '--compat-bf16' }
    Write-Host "Подготовка нового пакета в $Stage; файлы модели только читаются. Лог: $PackLog"
    & $Python -u @BuilderArgs *>&1 | Tee-Object -LiteralPath $PackLog
    if ($LASTEXITCODE -ne 0 -and -not $AllowBf16Conversion -and
            (Select-String -LiteralPath $PackLog -Pattern 'compat-bf16' -Quiet)) {
        # Кванты вне GSQ-RCO (IQ3_M, IQ4_XS, Q8_0, UD-*) хранят малые проекции не в BF16:
        # движок читает их из pack только BF16. Повтор с округлением малых проекций;
        # эксперты и PLE-таблица не меняются - так же собраны паки живой установки.
        Write-Host 'Квант хранит малые проекции не в BF16 - повторяю подготовку с --compat-bf16 (эксперты и PLE без изменений).' -ForegroundColor Yellow
        & $Python -u @($BuilderArgs + '--compat-bf16') *>&1 | Tee-Object -LiteralPath ($PackLog + '.compat')
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Подготовка завершилась с ошибкой. Незавершённые данные оставлены для диагностики: $Stage Лог: $PackLog"
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

# ---------- RAM-диск ----------
$UseRam = $RamDisk -ne 'None'
$AimLl = 'C:\Program Files\AIM Toolkit\aim_ll.exe'
$MtpSrc = [string]$Catalog.defaults.mtp_runtime
$ProfileSrc = Join-Path $Root 'data\expert-profile.bin'
$StatePath = Join-Path $Root 'logs\ram-disk\ram-state.json'

function Get-TreeBytes([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return [int64]0 }
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return [int64](Get-Item -LiteralPath $Path).Length }
    $m = Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction SilentlyContinue | Measure-Object Length -Sum
    if ($null -eq $m.Sum) { return [int64]0 }
    return [int64]$m.Sum
}

$NativePath = $First
$PlePath = $null
$PackPath = $Pack
$MtpPath = $MtpSrc
$ProfilePath = $ProfileSrc

if ($UseRam) {
    if (-not (Test-Path -LiteralPath $AimLl -PathType Leaf)) { throw "Не найден $AimLl (AIM Toolkit) - RAM-диск недоступен." }
    $Id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $P = [Security.Principal.WindowsPrincipal]::new($Id)
    if (-not $P.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Для создания RAM-диска нужен запуск от администратора (или выбери "не юзать рамдиск").'
    }
    $ShardBytes = [int64]0
    foreach ($s in $Shards) { $ShardBytes += [int64]$s.Length }
    $DefaultNeed = $ShardBytes + (Get-TreeBytes $Pack) + (Get-TreeBytes $MtpSrc) + (Get-Item -LiteralPath $ProfileSrc).Length + 3GB
    $DefaultGiB = [int][math]::Ceiling($DefaultNeed / 1GB) + 1
    $SizeGiB = if ($RamSizeGiB -gt 0) { $RamSizeGiB } else { $DefaultGiB }
    $Mount = ('{0}:\' -f $RamLetter.ToUpper())
    Assert-RamLetterUsable $RamLetter

    $ShardSig = @($Shards | ForEach-Object { $_.Name + ':' + $_.Length })
    $State = $null
    if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
        try { $State = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $State = $null }
    }
    $SameSetup = $State -and
                 $State.model_id -ceq $Name -and
                 ([string]$State.letter).ToUpper() -eq $RamLetter.ToUpper() -and
                 [int]$State.size_gib -eq $SizeGiB -and
                 (@($State.shards) -join '|') -eq ($ShardSig -join '|')
    $DiskOk = $false
    if ($SameSetup) {
        $vol = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -eq $RamLetter.ToUpper() }
        $DiskOk = $null -ne $vol -and [int64][math]::Floor($vol.Size / 1GB) -eq $SizeGiB
    }
    $RamModelDir = Join-Path $Mount ($Name + '-model')
    $RamRuntimeDir = Join-Path $Mount ($Name + '-runtime')
    $FilesOk = $false
    if ($SameSetup -and $DiskOk) {
        $FilesOk = $true
        foreach ($s in $Shards) {
            $dst = Join-Path $RamModelDir $s.Name
            if (-not (Test-Path -LiteralPath $dst -PathType Leaf) -or (Get-Item -LiteralPath $dst).Length -ne $s.Length) { $FilesOk = $false; break }
        }
        foreach ($req in @((Join-Path $RamRuntimeDir 'pack\index.txt'), (Join-Path $RamRuntimeDir 'mtp'), (Join-Path $RamRuntimeDir 'data\expert-profile.bin'))) {
            if (-not (Test-Path -LiteralPath $req)) { $FilesOk = $false; break }
        }
    }

    if ($SameSetup -and $DiskOk -and $FilesOk) {
        Write-Host "RAM-диск $Mount прежний (модель/буква/размер не менялись) - переиспользую без пересоздания и перекопирования." -ForegroundColor Green
    } else {
        Ensure-StrataModelRamDisk -AimLl $AimLl -Root $Root -RequiredBytes ($DefaultNeed) -DriveLetter $RamLetter.ToUpper() -TargetGiBOverride $SizeGiB
        if (Test-Path -LiteralPath $RamRuntimeDir) { Remove-Item -LiteralPath $RamRuntimeDir -Recurse -Force }
        New-Item -ItemType Directory -Path $RamModelDir -Force | Out-Null
        New-Item -ItemType Directory -Path $RamRuntimeDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $RamRuntimeDir 'data') -Force | Out-Null
        foreach ($s in $Shards) {
            $dst = Join-Path $RamModelDir $s.Name
            if ((Test-Path -LiteralPath $dst -PathType Leaf) -and (Get-Item -LiteralPath $dst).Length -eq $s.Length) {
                Write-Host ("есть на R: без изменений: {0}" -f $s.Name)
                continue
            }
            Write-Host ("COPY -> {0}: {1:N2} GiB" -f $RamLetter.ToUpper(), ($s.Length / 1GB))
            Copy-Item -LiteralPath $s.FullName -Destination $dst -Force
            if ((Get-Item -LiteralPath $dst).Length -ne $s.Length) { throw "Размер после копирования не совпал: $dst" }
        }
        Copy-Item -LiteralPath $Pack -Destination (Join-Path $RamRuntimeDir 'pack') -Recurse -Force
        Copy-Item -LiteralPath $MtpSrc -Destination (Join-Path $RamRuntimeDir 'mtp') -Recurse -Force
        Copy-Item -LiteralPath $ProfileSrc -Destination (Join-Path $RamRuntimeDir 'data\expert-profile.bin') -Force
        $StateObj = [ordered]@{
            model_id = $Name
            letter   = $RamLetter.ToUpper()
            size_gib = $SizeGiB
            shards   = $ShardSig
            saved_at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $StatePath) -Force | Out-Null
        [IO.File]::WriteAllText($StatePath, ($StateObj | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    }
    Set-Content -LiteralPath (Join-Path $Mount 'STRATA_RAM_DISK.marker') -Value ('strata-ram-disk model=' + $Name + ' size_gib=' + $SizeGiB) -Encoding utf8
    $NativePath = Join-Path $RamModelDir $Shards[0].Name
    if ($Shards.Count -gt 1) { $PlePath = Join-Path $RamModelDir $Shards[-1].Name }
    $PackPath = Join-Path $RamRuntimeDir 'pack'
    $MtpPath = Join-Path $RamRuntimeDir 'mtp'
    $ProfilePath = Join-Path $RamRuntimeDir 'data\expert-profile.bin'
}

Assert-StrataModelServerStopped -Port 8080
Assert-StrataModelEngineStopped -Root $Root
$LogDir = Join-Path $Root ('logs\catalog\' + $Name)
$DllDirs = @(Initialize-StrataModelDlls -Root $Root -Engine $Engine -LogDirectory $LogDir)
$D = $Catalog.defaults
$ArgsList = [System.Collections.Generic.List[string]]::new()
foreach ($Part in @('--pack', $PackPath, '--native', $NativePath,
                    '--expert-profile', $ProfilePath,
                    '--expert-cache', 'auto', '--prefill', 'auto',
                    '--pcie-frac', ([string]$D.pcie_frac), '--spec', ([string]$D.spec),
                    '--spec-min-p', ([string]$D.spec_min_p), '--suffix-draft', '0',
                    '--max-context', ([string]$D.max_context), '--kv', ([string]$D.kv),
                    '--kv-resident', ([string]$D.kv_resident),
                    '--resident-budget-gib', ([string]$(if ($Model.ContainsKey('resident_budget_gib')) { $Model.resident_budget_gib } else { $D.resident_budget_gib })),
                    '--adapt-every', '0', '--adapt-swaps', '0', '--prompt-cache', '0')) {
    $ArgsList.Add([string]$Part)
}
if ($PlePath) { $ArgsList.Add('--ple-gguf'); $ArgsList.Add($PlePath) }
if (-not (Test-Path -LiteralPath $MtpPath -PathType Container)) {
    throw "Не найден готовый MTP runtime: $MtpPath. У движка этой итерации режим --serve пока требует MTP."
}
$ArgsList.Add('--mtp')
$ArgsList.Add($MtpPath)

$VisionSection = $null
if ($Vision) {
    if (-not $Model.ContainsKey('mmproj') -or -not (Test-Path -LiteralPath $Model.mmproj -PathType Leaf)) {
        throw "Для $Name нет mmproj в каталоге - vision недоступен."
    }
    $VisionExe = Join-Path $Root 'engine\strata-vision.exe'
    if (-not (Test-Path -LiteralPath $VisionExe -PathType Leaf)) { throw "Отсутствует $VisionExe" }
    $ArgsList.Add('--vision')
    $VisionSection = [ordered]@{
        exe            = $VisionExe
        mmproj         = [string]$Model.mmproj
        model          = $NativePath
        gpu            = $false
        gpu_on_demand  = $true
        max_tokens     = 1024
    }
}

$Sampling = [ordered]@{ temperature = $Ref.temperature }
foreach ($key in @('max_tokens', 'top_k', 'top_p', 'min_p')) {
    if ($SamplingOverride.ContainsKey($key)) { $Sampling[$key] = $SamplingOverride[$key] }
}
$Budget = if ($ReasoningBudget -ge 0) { $ReasoningBudget }
          elseif ($SamplingOverride.ContainsKey('reasoning_budget_tokens')) { [int]$SamplingOverride.reasoning_budget_tokens }
          else { [int]$Ref.reasoning_budget_tokens }

$RuntimeConfig = [ordered]@{
    exe = $Engine
    args = @($ArgsList.ToArray())
    cwd = $Root
    tokenizer = (Join-Path $PackPath 'tokenizer')
    model_name = [string]$Model.id
    reasoning_budget_tokens = $Budget
    autotune = $false
    parallel = [int]$D.parallel
    log = (Join-Path $LogDir 'engine.log')
    lib_dirs = @($DllDirs)
    host = '0.0.0.0'
    port = 8080
    gpu = 0
    gpus_asked = $true
    sampling = $Sampling
}
if ($VisionSection) { $RuntimeConfig['vision'] = $VisionSection }
$RuntimeName = ('runtime-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.json')
$RuntimePath = Join-Path $LogDir $RuntimeName
[IO.File]::WriteAllText($RuntimePath, (($RuntimeConfig | ConvertTo-Json -Depth 64) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
Write-Host "Модель: $Name | RAM=$([bool]$UseRam)$(if ($UseRam) { " $RamLetter`: $SizeGiB GiB" }) | vision=$([bool]$VisionSection) | thinking=$Budget"
Write-Host "Исходные каталоги и GGUF не изменяются. Временная конфигурация: $RuntimePath"
Write-Host 'Для остановки нажмите Ctrl+C.'
& $Python -u $Server --engine strata --config $RuntimePath --host 0.0.0.0 --port 8080
exit $LASTEXITCODE
