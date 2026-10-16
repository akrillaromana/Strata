#requires -Version 7.0
<#
Личный запуск Unsloth Q8_0 без переквантования оригинальной n-gram PLE.
Проверяет все 6 GGUF и тип таблицы до любых изменений на RAM-диске.
По умолчанию сервер работает в терминале до Ctrl+C; -Detached оставлен
для обратной совместимости с другими запускателями.
#>
[CmdletBinding()]
param(
    [string]$ModelsDirectory,
    [string]$PackSource,
    [string]$MtpSource = 'E:\ai\Strata-data\mtp\rt',
    [switch]$PreparePack,
    [switch]$AllowBf16Conversion,
    [switch]$Detached,
    [switch]$Foreground,
    [switch]$IgnoreAutotune,
    [switch]$ExpertParityCuda
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($Detached -and $Foreground) { throw 'Нельзя совместить -Detached и -Foreground.' }

$Root = 'E:\ai\Strata-Q4-Fork'
$Data = 'E:\ai\Strata-data'
$Engine = Join-Path $Root 'engine\strata.exe'
$Server = Join-Path $Root 'serve\server.py'
$AimLl = 'C:\Program Files\AIM Toolkit\aim_ll.exe'
$ProfileSource = Join-Path $Root 'data\expert-profile.bin'
$Checker = Join-Path $Root 'tools\q8_ple_preflight.py'
$RamModel = 'R:\q8-model'
$RamRuntime = 'R:\strata-runtime-q8'
$RamPack = Join-Path $RamRuntime 'pack'
$RamMtp = Join-Path $RamRuntime 'mtp'
$RamProfile = Join-Path $RamRuntime 'data\expert-profile.bin'
$ConfigPath = Join-Path $Root 'strata-unsloth-q8_0.json'
$LogDir = Join-Path $Root 'logs\q8'
$RunId = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$EngineLog = Join-Path $LogDir "engine-$RunId.stderr.log"
$Names = @(1..6 | ForEach-Object { 'Qwen3.8-Flash-Next-Q8_0-{0:D5}-of-00006.gguf' -f $_ })
$CheckpointFile = Join-Path $LogDir 'Q8_START_LAST.txt'
New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
[IO.File]::WriteAllText($CheckpointFile, ("Запуск Q8_0, итерация 057, {0}`r`n" -f (Get-Date -Format 'o')),
    [Text.UTF8Encoding]::new($false))

function Write-Q8Checkpoint {
    param([Parameter(Mandatory)][string]$Message)
    $Line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message
    Write-Host $Line -ForegroundColor Cyan
    Add-Content -LiteralPath $CheckpointFile -Value $Line -Encoding utf8
}

function Assert-Q8SameNameAndSize {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$Label
    )
    $A = Get-Item -LiteralPath $Source -ErrorAction Stop
    $B = Get-Item -LiteralPath $Destination -ErrorAction Stop
    if (-not [string]::Equals($A.Name, $B.Name, [StringComparison]::OrdinalIgnoreCase) -or
        [int64]$A.Length -ne [int64]$B.Length) {
        throw ('{0}: имя/размер не совпадают: {1} ({2} байт) <> {3} ({4} байт).' -f
            $Label, $A.Name, $A.Length, $B.Name, $B.Length)
    }
}

Write-Host '============================================================'
Write-Host ' STRATA Q8_0 / НАТИВНАЯ PLE / RAM / КАЧЕСТВО'
Write-Host '============================================================'
Write-Host 'Q8_0 запускатель: итерация 057; подготовка пакета -PreparePack.'
Write-Host "Root: $Root"
Write-Host 'API:  http://127.0.0.1:8080/v1'

# Предварительная проверка ничего не удаляет и не останавливает.
$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = [Security.Principal.WindowsPrincipal]::new($Identity)
if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Для создания RAM-диска и ссылок нужен PowerShell 7 от имени администратора.'
}
. (Join-Path $Root 'STRATA-MODEL-LAUNCH-COMMON.ps1')
$Python = Resolve-StrataModelPython -Root $Root
foreach ($Required in @($Engine, $Server, $AimLl, $Checker, $ProfileSource, $MtpSource)) {
    if (-not (Test-Path -LiteralPath $Required)) { throw "Не найден обязательный путь: $Required" }
}
if ([string]::IsNullOrWhiteSpace($ModelsDirectory)) {
    foreach ($Candidate in @(
        'E:\ai\models\unsloth\Qwen3.8-Flash-Next-GGUF',
        'E:\ai\Strata-data\models\Q8_0'
    )) {
        if (Test-Path -LiteralPath (Join-Path $Candidate $Names[0]) -PathType Leaf) {
            $ModelsDirectory = $Candidate
            break
        }
    }
}
if (-not $ModelsDirectory -or -not (Test-Path -LiteralPath $ModelsDirectory -PathType Container)) {
    throw 'Не найден каталог исходных Q8_0 GGUF. Укажите -ModelsDirectory "ПОЛНЫЙ_ПУТЬ_К_ШЕСТИ_GGUF".'
}
if (-not $PackSource) {
    foreach ($Candidate in @(
        (Join-Path $Data 'packs\unsloth-q8_0'),
        (Join-Path $Data 'packs\q8_0')
    )) {
        if (Test-Path -LiteralPath (Join-Path $Candidate 'tokenizer\vocab.json') -PathType Leaf) {
            $PackSource = $Candidate
            break
        }
    }
}
$SourceFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
foreach ($Name in $Names) {
    $Shard = Join-Path $ModelsDirectory $Name
    if (-not (Test-Path -LiteralPath $Shard -PathType Leaf)) {
        throw "Отсутствует исходный GGUF: $Shard"
    }
    $SourceFiles.Add((Get-Item -LiteralPath $Shard))
}

Write-Host '===== ПРОВЕРКА НАСТОЯЩЕЙ Q8_0 PLE ====='
$FirstShard = $SourceFiles[0].FullName
$PreflightOutput = @(& $Python $Checker $FirstShard --json 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "Исходная таблица Q8_0 не подтверждена; RAM не затронут. $($PreflightOutput -join ' ')"
}
try { $Preflight = ($PreflightOutput -join "`n") | ConvertFrom-Json -ErrorAction Stop }
catch { throw "Некорректный ответ проверки Q8_0: $($_.Exception.Message)" }
if ($Preflight.quantization -ne 'Q8_0' -or [int]$Preflight.shards -ne 6 -or
    -not $Preflight.source) {
    throw 'Проверка n-gram вернула неполный результат. Запуск остановлен.'
}
$PleSource = (Resolve-Path -LiteralPath ([string]$Preflight.source)).Path
$PleFile = Get-Item -LiteralPath $PleSource
if (-not ($SourceFiles.FullName -contains $PleSource)) {
    throw "PLE относится к постороннему GGUF: $PleSource"
}
Write-Host "PLE Q8_0: $($PleFile.Name) ($([math]::Round($PleFile.Length/1GB,2)) GiB)"
Write-Host 'Полные значения весов не проверяются: проверены GGUF-заголовки, тип и размещение таблицы.'

# Пакет строится только из проверенного Q8_0 GGUF; оригинальные PLE и
# экспертные блоки сохраняются в GGUF-формате. Для отдельных небольших
# плотных проекций упаковщику может понадобиться округление до BF16.
if (-not $PackSource -or -not (Test-Path -LiteralPath (Join-Path $PackSource 'tokenizer\vocab.json') -PathType Leaf)) {
    if (-not $PreparePack) {
        throw 'Нет отдельного пакета Q8_0. Для его создания из шести GGUF запустите START-Q8-RAM.ps1 -PreparePack -AllowBf16Conversion. Исходные файлы не меняются.'
    }
    if (-not $AllowBf16Conversion) {
        throw 'Сборка Q8-пакета может округлять некоторые малые плотные проекции до BF16. Для согласия явно передайте -AllowBf16Conversion; оригинальные эксперты и PLE остаются Q8_0.'
    }
    if (-not $PackSource) { $PackSource = Join-Path $Data 'packs\unsloth-q8_0' }
    if (Test-Path -LiteralPath $PackSource) {
        throw "Неполный Q8-пакет уже существует: $PackSource. Не перезаписываю его автоматически."
    }
    $Builder = Join-Path $Root 'tools\iq_pack.py'
    if (-not (Test-Path -LiteralPath $Builder -PathType Leaf)) {
        throw "Сборщик нативных пакетов отсутствует: $Builder"
    }
    # Предыдущие версии искали gguf-py только в third_party, хотя CMake уже
    # загрузил закреплённую ревизию в build-iq3s-ninja-release\_deps.
    # Проверка ДО создания временного пакета, записи файлов и работы с R:.
    $DependencyCheck = Join-Path $Root 'tools\ensure_gguf_py.py'
    if (-not (Test-Path -LiteralPath $DependencyCheck -PathType Leaf)) {
        throw "Отсутствует проверка зависимости GGUF: $DependencyCheck"
    }
    Write-Host '===== ПРОВЕРКА gguf-py ДЛЯ Q8_0 ====='
    & $Python -u $DependencyCheck --install-if-missing
    if ($LASTEXITCODE -ne 0) {
        throw 'Нельзя подготовить Q8-пакет без закреплённой gguf-py. Смотрите сообщение проверки выше. GGUF и R: не изменены.'
    }
    # Незавершённый каталог *.building от итерации 044 НЕ удаляется:
    # повторный запуск получает собственный уникальный временный каталог.
    $Staging = "$PackSource.building-045-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path (Split-Path -Parent $PackSource) -Force | Out-Null
    Write-Host '===== СОЗДАНИЕ СОБСТВЕННОГО ПАКЕТА Q8_0 ====='
    Write-Host "Источник: $FirstShard"
    Write-Host "Временный каталог: $Staging"
    Write-Host 'Режим: оригинальные эксперты/PLE; совместимое BF16 для отдельных проекций.'
    & $Python -u $Builder --gguf $FirstShard --out $Staging --compat-bf16
    if ($LASTEXITCODE -ne 0) {
        throw "Подготовка Q8-пакета завершилась ошибкой. Каталог для проверки: $Staging"
    }
    foreach ($RequiredFile in @('index.txt', 'dense.bin', 'native_experts.txt', 'tokenizer\vocab.json')) {
        $Candidate = Join-Path $Staging $RequiredFile
        if (-not (Test-Path -LiteralPath $Candidate -PathType Leaf) -or
            (Get-Item -LiteralPath $Candidate).Length -eq 0) {
            throw "Сборщик завершился, но пакет неполный: $Candidate"
        }
    }
    $SourceStamp = [ordered]@{
        model = 'qwen3.8-flash-next-unsloth-q8_0'
        first_shard = $FirstShard
        shards = @($SourceFiles | ForEach-Object { [ordered]@{name=$_.Name;bytes=$_.Length} })
        native_ple = 'Q8_0'
        bf16_dense_compatibility = $true
    }
    $StampText = ($SourceStamp | ConvertTo-Json -Depth 8)
    [IO.File]::WriteAllText((Join-Path $Staging 'Q8-PACK-SOURCE.json'), $StampText,
        [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $Staging -Destination $PackSource -ErrorAction Stop
    Write-Host "Готов отдельный пакет Q8_0: $PackSource"
}
foreach ($RequiredFile in @('index.txt','dense.bin','native_experts.txt','tokenizer\vocab.json')) {
    $RequiredPath = Join-Path $PackSource $RequiredFile
    if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf)) {
        throw "Нативный Q8-пакет неполный: $RequiredPath"
    }
}
$ProvenanceFile = Join-Path $PackSource 'Q8-PACK-SOURCE.json'
if (Test-Path -LiteralPath $ProvenanceFile -PathType Leaf) {
    $Provenance = Get-Content -LiteralPath $ProvenanceFile -Raw |
        ConvertFrom-Json -ErrorAction Stop
    if ($Provenance.model -ne 'qwen3.8-flash-next-unsloth-q8_0' -or
        $Provenance.native_ple -ne 'Q8_0' -or
        @($Provenance.shards).Count -ne 6) {
        throw "Q8-пакет имеет чужое либо неполное происхождение: $ProvenanceFile"
    }
    foreach ($Index in 0..5) {
        if ($Provenance.shards[$Index].name -ne $SourceFiles[$Index].Name -or
            [long]$Provenance.shards[$Index].bytes -ne $SourceFiles[$Index].Length) {
            throw "Исходный GGUF изменился после сборки пакета: $($SourceFiles[$Index].Name). Повторная подготовка должна быть в отдельном каталоге."
        }
    }
    Write-Host 'Происхождение Q8-пакета проверено по точным именам и размерам всех шести GGUF.'
} else {
    Write-Warning 'Пакет Q8 без Q8-PACK-SOURCE.json: источник не подтверждён. Для строгой защиты подготовьте новый пакет через -PreparePack.'
}

Write-Q8Checkpoint 'Пакет принят. Проверяю отсутствие другого сервера на порту 8080.'
Assert-StrataModelServerStopped -Port 8080
$ActiveEngine = @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop |
    Where-Object {
        $_.ProcessId -ne $PID -and $_.CommandLine -and
        ($_.Name -in @('python.exe', 'python3.exe', 'strata.exe')) -and
        ($_.CommandLine.Contains("$Root\serve\server.py") -or
         $_.CommandLine.Contains("$Root\engine\strata.exe"))
    })
if ($ActiveEngine.Count -gt 0) {
    throw ('Продолжают работать процессы Strata ({0}). Завершите их штатно перед переключением RAM-диска.' -f
        (($ActiveEngine | ForEach-Object { $_.ProcessId }) -join ', '))
}
Write-Q8Checkpoint 'Другие процессы Strata не обнаружены; проверяю зависимости CUDA/MSVC.'
$DllDirs = @(Initialize-StrataModelDlls -Root $Root -Engine $Engine -LogDirectory $LogDir)
Write-Q8Checkpoint 'Проверяю доступность и состояние RAM-диска R:.'
Ensure-StrataModelRamDisk -AimLl $AimLl -Root $Root
Write-Q8Checkpoint 'RAM-диск обнаружен. Получаю сведения о томе NTFS и проверяю его размер.'
$Volume = Get-Volume -DriveLetter R -ErrorAction Stop
# Label compatibility is validated by Ensure-StrataModelRamDisk, including
# the existing legacy RamDisk volume if recognizable Strata staging exists.
if ($Volume.FileSystem -ne 'NTFS' -or $Volume.Size -lt 53GB) {
    throw 'R: должен быть NTFS RAM-диском номинально 54 GiB (размер тома не менее 53 GiB). Форматирование запрещено.'
}
Write-Q8Checkpoint ('R: подтверждён: {0:N2} ГиБ; свободно {1:N2} ГиБ. Считаю размер Q8-пакета и MTP.' -f
    ($Volume.Size / 1GB), ((Get-PSDrive R).Free / 1GB))
$PackBytes = Get-StrataDirectoryBytes -Path $PackSource
Write-Q8Checkpoint ('Размер Q8-пакета: {0:N2} ГиБ. Проверяю MTP.' -f ($PackBytes / 1GB))
$MtpBytes = Get-StrataDirectoryBytes -Path $MtpSource
$ProfileBytes = (Get-Item -LiteralPath $ProfileSource).Length
$TotalRequired = [int64]$PleFile.Length + $PackBytes + $MtpBytes + $ProfileBytes + 512MB
Write-Q8Checkpoint ('PLE {0:N2} + пакет {1:N2} + MTP {2:N2} + резерв 0.5 ГиБ = {3:N2} ГиБ.' -f
    ($PleFile.Length / 1GB), ($PackBytes / 1GB), ($MtpBytes / 1GB), ($TotalRequired / 1GB))
if ($TotalRequired -gt $Volume.Size) {
    throw ('Q8_0 PLE + пакет + MTP + 0.5 GiB резерва превышают размер R: ({0:N2} против {1:N2} GiB).' -f ($TotalRequired / 1GB), ($Volume.Size / 1GB))
}
Write-Q8Checkpoint 'Проверка ёмкости пройдена. Проверяю известные временные каталоги прежних моделей.'
# Только собственные временные каталоги предыдущих профилей в RAM.
# Пользовательские и неизвестные файлы никогда не удаляются.
$OtherCachePaths = @('R:\iq3s-model', 'R:\strata-iq3s-runtime',
                     'R:\q4-model', 'R:\strata-q4-runtime',
                     'R:\q6-model', 'R:\strata-runtime-q6')
foreach ($Old in $OtherCachePaths) {
    if (Test-Path -LiteralPath $Old) {
        Write-Host "Удаляю известный временный кэш предыдущей модели на R: $Old"
        Remove-Item -LiteralPath $Old -Recurse -Force
    }
}
Write-Q8Checkpoint 'Подготовка места завершена. Проверяю наличие ранее скопированной PLE Q8_0.'
New-Item -ItemType Directory -Path $RamModel -Force | Out-Null
$RamPle = Join-Path $RamModel $PleFile.Name
$PleValid = $false
if (Test-Path -LiteralPath $RamPle -PathType Leaf) {
    $OldRamFile = Get-Item -LiteralPath $RamPle
    if (-not $OldRamFile.LinkType -and
        [string]::Equals($OldRamFile.Name, $PleFile.Name, [StringComparison]::OrdinalIgnoreCase) -and
        [int64]$OldRamFile.Length -eq [int64]$PleFile.Length) {
        $PleValid = $true
        Write-Q8Checkpoint ('PLE на R: принята по имени и точному размеру: {0}, {1} байт.' -f
            $OldRamFile.Name, $OldRamFile.Length)
    }
}
if (-not $PleValid) {
    Write-Q8Checkpoint 'Действительная копия PLE Q8_0 не найдена; проверяю свободное место перед копированием.'
    if (Test-Path -LiteralPath $RamPle) { Remove-Item -LiteralPath $RamPle -Force }
    $Free = (Get-PSDrive R).Free
    $CopyNeed = [int64]$PleFile.Length + $PackBytes + $MtpBytes + $ProfileBytes + 512MB
    if ($Free -lt $CopyNeed) {
        throw ('Недостаточно места на R: для Q8_0. Нужно {0:N2} GiB, свободно {1:N2} GiB. Неизвестные файлы не удалены.' -f ($CopyNeed / 1GB), ($Free / 1GB))
    }
    Write-Q8Checkpoint ('Начинаю копирование PLE Q8_0: {0:N2} ГиБ. Исходный GGUF на E: не изменяется.' -f ($PleFile.Length / 1GB))
    $Partial = "$RamPle.partial-$([guid]::NewGuid().ToString('N'))"
    try {
        Copy-Item -LiteralPath $PleSource -Destination $Partial -ErrorAction Stop
        $PartialItem = Get-Item -LiteralPath $Partial
        if ([int64]$PartialItem.Length -ne [int64]$PleFile.Length) {
            throw 'Размер скопированной PLE не совпадает с оригиналом.'
        }
        Move-Item -LiteralPath $Partial -Destination $RamPle -ErrorAction Stop
        Assert-Q8SameNameAndSize -Source $PleSource -Destination $RamPle -Label 'Q8_0 PLE'
        Write-Q8Checkpoint 'Копия PLE Q8_0 принята по имени и точному размеру.'
    } finally {
        if (Test-Path -LiteralPath $Partial -PathType Leaf) {
            Remove-Item -LiteralPath $Partial -Force
        }
    }
} else {
    Write-Q8Checkpoint 'Q8_0 PLE на R: совпадает по имени и точному размеру; использую повторно.'
}
# Остальные пять шардов хранятся на E:, на R: размещены ссылки на них.
Write-Q8Checkpoint 'Проверяю символические ссылки на остальные пять GGUF.'
foreach ($Source in $SourceFiles) {
    if ($Source.FullName -eq $PleSource) { continue }
    $Destination = Join-Path $RamModel $Source.Name
    if (Test-Path -LiteralPath $Destination) {
        $Existing = Get-Item -LiteralPath $Destination -Force
        if ($Existing.LinkType -ne 'SymbolicLink' -or
            -not [string]::Equals([string]$Existing.Target, [string]$Source.FullName,
                                   [StringComparison]::OrdinalIgnoreCase)) {
            throw "Непредвиденный файл в каталоге Q8_0: $Destination. Не перезаписываю его."
        }
        continue
    }
    New-Item -ItemType SymbolicLink -Path $Destination -Target $Source.FullName -ErrorAction Stop | Out-Null
}
# Обновляем собственную временную среду Q8, не затрагивая GGUF/другие модели.
Write-Q8Checkpoint 'Копирую нативный пакет Q8_0, MTP и профиль на R:.'
if (Test-Path -LiteralPath $RamRuntime) {
    Remove-Item -LiteralPath $RamRuntime -Recurse -Force
}
New-Item -ItemType Directory -Path (Join-Path $RamRuntime 'data') -Force | Out-Null
Write-Host '===== ПОДГОТОВКА Q8_0 ПАКЕТА И MTP ====='
Copy-Item -LiteralPath $PackSource -Destination $RamPack -Recurse -Force -ErrorAction Stop
Copy-Item -LiteralPath $MtpSource -Destination $RamMtp -Recurse -Force -ErrorAction Stop
Copy-Item -LiteralPath $ProfileSource -Destination $RamProfile -Force -ErrorAction Stop
Write-Q8Checkpoint 'Рабочие данные Q8_0 скопированы. Формирую конфигурацию сервера.'

$EngineArgs = [System.Collections.Generic.List[string]]::new()
@('--pack', $RamPack,
  '--native', (Join-Path $RamModel $Names[0]),
  '--expert-profile', $RamProfile,
  '--expert-cache', 'auto', '--prefill', 'auto',
  '--spec', '4', '--spec-min-p', '0.9',
  '--suffix-draft', '0', '--mtp', $RamMtp,
  '--max-context', '262144', '--kv', 'int8', '--kv-resident', '32768',
  '--resident-budget-gib', '120', '--pcie-frac', '0.26',
  '--adapt-every', '0', '--adapt-swaps', '0', '--prompt-cache', '0',
  '--ple-require-type', 'Q8_0') | ForEach-Object { $EngineArgs.Add([string]$_) }
$Config = [ordered]@{
    exe = $Engine
    args = @($EngineArgs.ToArray())
    cwd = $Root
    tokenizer = (Join-Path $RamPack 'tokenizer')
    model_name = 'qwen3.8-flash-next-unsloth-q8_0'
    reasoning_budget_tokens = 10240
    log = $EngineLog
    lib_dirs = @($DllDirs)
    autotune = $false
    host = '0.0.0.0'
    port = 8080
    gpu = 0
    gpus_asked = $true
}
$ParityFlags = @{}
if ($ExpertParityCuda) { $ParityFlags['--expert-parity'] = 'cuda' }
$RuntimeConfig = New-StrataModelRuntimeConfig -RootConfig $ConfigPath `
    -PersonalConfig (Join-Path $Root 'PERSONAL_START_E_ai_Strata-Q4-Fork\strata-unsloth-q8_0.json') `
    -Defaults $Config -RuntimeFlags @{
        '--pack'=$RamPack
        '--native'=(Join-Path $RamModel $Names[0])
        '--expert-profile'=$RamProfile
        '--mtp'=$RamMtp
        '--ple-require-type'='Q8_0'
    } -LogDirectory $LogDir -RunId $RunId -IgnoreAutotune:$IgnoreAutotune -ExplicitFlags $ParityFlags
$env:STRATA_SSD_KEEPALIVE = '0'
$env:STRATA_IQ_MT_MIN = '1'
Write-Host "Конфигурация сервера: $RuntimeConfig"
if ($ExpertParityCuda) {
    Write-Host 'EXPERIMENTAL: --expert-parity cuda включён. Для Q8_0 CPU/CUDA expert path использует единый parity-контракт.' -ForegroundColor Yellow
}
Write-Host "Лог движка: $EngineLog"
Write-Host ('Свободно на R: {0:N2} GiB' -f ((Get-PSDrive R).Free / 1GB))
Write-Q8Checkpoint 'Подготовка Q8_0 завершена. Запускаю сервер и ожидаю его готовности.'
if (-not $Detached) {
    Write-Host '===== ЖИВОЙ ВЫВОД: запросы, префилл, генерация токенов ====='
    Write-Host 'Остановить: Ctrl+C. Для фонового запуска используйте -Detached.'
    & $Python -u $Server --engine strata --config $RuntimeConfig --host 0.0.0.0 --port 8080
    if ($LASTEXITCODE -ne 0) { throw "Сервер Q8_0 завершился с кодом $LASTEXITCODE. Лог: $EngineLog" }
    return
}
$Stdout = Join-Path $LogDir "server-$RunId.stdout.log"
$Stderr = Join-Path $LogDir "server-$RunId.stderr.log"
$Process = Start-Process -FilePath $Python -WorkingDirectory $Root -PassThru `
    -ArgumentList @('-u', "`"$Server`"", '--engine', 'strata', '--config', "`"$RuntimeConfig`"", '--host', '0.0.0.0', '--port', '8080') `
    -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr
$Ready = $false
for ($Attempt = 0; $Attempt -lt 180; $Attempt++) {
    Start-Sleep -Seconds 2
    $Process.Refresh()
    if ($Process.HasExited) {
        Write-Host "Сервер Q8_0 завершился: $($Process.ExitCode)"
        break
    }
    try {
        $Response = Invoke-RestMethod -Uri 'http://127.0.0.1:8080/v1/models' -TimeoutSec 2
        if (@($Response.data | Where-Object { $_.id -eq 'qwen3.8-flash-next-unsloth-q8_0' }).Count -eq 1) {
            $Ready = $true
            break
        }
    } catch { }
}
if (-not $Ready) {
    if (Test-Path -LiteralPath $Stderr) { Get-Content -LiteralPath $Stderr -Tail 120 }
    if (Test-Path -LiteralPath $EngineLog) { Get-Content -LiteralPath $EngineLog -Tail 120 }
    throw "Q8_0 не готова. Подробности: $Stderr и $EngineLog"
}
Write-Host 'Q8_0 READY: http://127.0.0.1:8080/v1'
Write-Host "Логи: $Stdout / $Stderr"
