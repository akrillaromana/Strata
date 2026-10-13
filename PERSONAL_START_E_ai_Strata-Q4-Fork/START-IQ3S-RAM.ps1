param(
    [switch]$Foreground,
    [switch]$Detached,
    [switch]$NoPrefillBorrow,
    [ValidateRange(0.0, 1.0)]
    [double]$PcieFrac = 0.26,
    [switch]$IgnoreAutotune
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($Foreground -and $Detached) {
    throw 'Нельзя одновременно выбрать -Foreground и -Detached.'
}

# Reuse the CURRENT Strata-Q4-Fork installation/engine/server.
# IQ3_S has its own model/pack/runtime paths; the persistent Q4 files on E: are not modified.
$Root   = "E:\ai\Strata-Q4-Fork"
$Data   = "E:\ai\Strata-data"
$Models = "E:\ai\Strata-data\models\IQ3_S"

$Python = "$Root\.venv\Scripts\python.exe"
$Server = "$Root\serve\server.py"
$Engine = "$Root\engine\strata.exe"
$AimLl  = "C:\Program Files\AIM Toolkit\aim_ll.exe"

$PackSrc    = "$Data\packs\iq3_s"
$MtpSrc     = "$Data\mtp\rt"
$ProfileSrc = "$Root\data\expert-profile.bin"
$TokenizerVocab = "$PackSrc\tokenizer\vocab.json"

# IQ3_S's second shard is the large PLE lookup table.  Keep it on the RAM disk
# during inference; shard 1 is linked from E: and Strata loads its experts into
# normal system RAM at startup.
$RamModel   = "R:\iq3s-model"
$RamRuntime = "R:\strata-iq3s-runtime"
$RamPack    = "$RamRuntime\pack"
$RamMtp     = "$RamRuntime\mtp"
$RamData    = "$RamRuntime\data"
$RamProfile = "$RamData\expert-profile.bin"

$Cfg = "$Root\strata-iq3_s-RAM.json"
$ServerLogDir = "$Root\logs\iq3s"
# Engine stderr must survive RAM-runtime cleanup and be visible on E: even
# when CUDA or Windows terminates strata.exe before it prints READY.
$ServerRunId = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$Log = Join-Path $ServerLogDir "engine-$ServerRunId.stderr.log"

$Names = @(
    "Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf",
    "Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00002-of-00002.gguf"
)

function Assert-Admin {
    $Id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $P  = [Security.Principal.WindowsPrincipal]::new($Id)
    if (-not $P.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Запустите PowerShell 7 ОТ ИМЕНИ АДМИНИСТРАТОРА."
    }
}

function TreeBytes([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return [int64](Get-Item -LiteralPath $Path).Length
    }

    $m = Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction Stop |
         Measure-Object Length -Sum

    if ($null -eq $m.Sum) { return [int64]0 }
    return [int64]$m.Sum
}

function Assert-Gguf([string]$Path) {
    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
        $buf = New-Object byte[] 4
        $read = $fs.Read($buf, 0, 4)
        if ($read -ne 4 -or [System.Text.Encoding]::ASCII.GetString($buf) -ne "GGUF") {
            throw "Файл не похож на GGUF: $Path"
        }
    }
    finally {
        $fs.Dispose()
    }
}

function Resolve-StrataPython {
    $Candidates = [System.Collections.Generic.List[string]]::new()
    $Candidates.Add("$Root\.venv\Scripts\python.exe")
    foreach ($Name in @('python.exe', 'python3.exe')) {
        $Command = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $Command -and -not $Candidates.Contains($Command.Source)) {
            $Candidates.Add($Command.Source)
        }
    }
    foreach ($Candidate in $Candidates) {
        if (-not (Test-Path -LiteralPath $Candidate -PathType Leaf)) { continue }
        # Windows Store aliases and incomplete installations must not be accepted.
        try {
            $Version = & $Candidate -c 'import sys; print(sys.version_info.major, sys.version_info.minor)' 2>$null
            if ($LASTEXITCODE -ne 0 -or -not $Version) { continue }
            $Parts = ([string]($Version | Select-Object -Last 1)).Trim().Split(' ')
            if ($Parts.Count -ne 2 -or [int]$Parts[0] -ne 3 -or [int]$Parts[1] -lt 10) { continue }
            Write-Host "Python: $Candidate (version $($Parts -join '.'))"
            return $Candidate
        }
        catch {
            Write-Warning "Не удалось запустить Python: $Candidate"
        }
    }
    throw "Python 3.10+ не найден. Установите Python либо создайте $Root\.venv. Проверены локальная среда и python.exe/python3.exe из PATH."
}

Assert-Admin

Write-Host ""
Write-Host "============================================================"
Write-Host " STRATA IQ3_S GSQ-RCO / RAM PLE / QUALITY"
Write-Host "============================================================"
Write-Host "Engine root: $Root"
Write-Host "Models:      $Models"
Write-Host "Bind:        0.0.0.0:8080"
Write-Host ""

$Python = Resolve-StrataPython
foreach ($P in @(
    $Server,$Engine,$AimLl,$PackSrc,$MtpSrc,$ProfileSrc,$TokenizerVocab
)) {
    if (-not (Test-Path -LiteralPath $P)) {
        throw "Не найден обязательный путь: $P"
    }
}

# Проверяем загрузку исполняемого файла и его DLL ДО тяжелой подготовки R:.
# Новый процесс Python наследует добавленные каталоги CUDA и MSVC из PATH.
$RuntimeHelper = Join-Path $Root 'STRATA-WINDOWS-RUNTIME.ps1'
if (-not (Test-Path -LiteralPath $RuntimeHelper -PathType Leaf)) {
    throw "Не найден сценарий проверки DLL: $RuntimeHelper"
}
. $RuntimeHelper
Initialize-StrataWindowsRuntime -Engine $Engine -Root $Root -LogDir $ServerLogDir -RepairMissingCublas
$RuntimeDllDirs = @(Get-StrataRuntimeDirectories -Engine $Engine -Root $Root)

$SourceShards = @()
foreach ($N in $Names) {
    $P = Join-Path $Models $N
    if (-not (Test-Path -LiteralPath $P -PathType Leaf)) {
        throw "Не найден IQ3_S shard: $P"
    }
    Assert-Gguf $P
    $SourceShards += Get-Item -LiteralPath $P
}

if ($SourceShards.Count -ne 2) {
    throw "Ожидалось ровно 2 IQ3_S shard, найдено: $($SourceShards.Count)"
}

Write-Host "IQ3_S shards:"
for ($i=0; $i -lt $SourceShards.Count; $i++) {
    Write-Host ("  shard {0}: {1:N2} GiB  {2}" -f ($i+1), ($SourceShards[$i].Length/1GB), $SourceShards[$i].Name)
}

# Stop whichever model from this Strata-Q4-Fork root is currently using port/engine.
Get-CimInstance Win32_Process |
    Where-Object {
        $_.ProcessId -ne $PID -and
        $_.CommandLine -and (
            $_.CommandLine -like "*$Root\serve\server.py*" -or
            $_.CommandLine -like "*$Root\engine\strata.exe*"
        )
    } |
    ForEach-Object {
        Write-Host "Stopping PID $($_.ProcessId) $($_.Name)"
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }

Start-Sleep 2

if (-not (Test-Path "R:\")) {
    Write-Host ""
    Write-Host "R: отсутствует. Создаю 64 GiB AWE RAM disk..."

    & $AimLl -a -t file -o awe -s 64G -m R: -p "/fs:ntfs /q /y /v:STRATA_PLE"

    if ($LASTEXITCODE -ne 0) {
        throw "AIM Toolkit не смог создать R:. Exit code: $LASTEXITCODE"
    }

    for ($i=0; $i -lt 20; $i++) {
        if (Test-Path "R:\") { break }
        Start-Sleep 1
    }

    if (-not (Test-Path "R:\")) {
        throw "После AIM attach диск R: не появился."
    }
}

$Vol = Get-Volume -DriveLetter R -ErrorAction Stop
if ($Vol.FileSystem -ne "NTFS") {
    throw "R: существует, но FileSystem=$($Vol.FileSystem), ожидался NTFS. Ничего автоматически не форматирую."
}
if ($Vol.Size -lt 60GB) {
    throw "R: слишком мал: $([math]::Round($Vol.Size/1GB,2)) GiB. Ожидалось около 64 GiB."
}

# Switching Q4 -> IQ3_S: remove ONLY known ephemeral Q4 RAM copies/links.
# Persistent files on E: are never removed here.
$ConflictingRamPaths = @(
    "R:\q4-model",
    "R:\strata-q4-runtime",
    "R:\strata-runtime",
    "R:\Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf",
    "R:\Qwen3.8-Flash-Next-UD-Q4_K_XL-00002-of-00004.gguf",
    "R:\Qwen3.8-Flash-Next-UD-Q4_K_XL-00003-of-00004.gguf",
    "R:\Qwen3.8-Flash-Next-UD-Q4_K_XL-00004-of-00004.gguf"
)
foreach ($P in $ConflictingRamPaths) {
    if (Test-Path -LiteralPath $P) {
        Write-Host "Removing conflicting ephemeral RAM path: $P"
        Remove-Item -LiteralPath $P -Recurse -Force
    }
}

# Keep a valid IQ3_S PLE copy between repeated IQ3_S launches; rebuild only the hot runtime.
if (-not (Test-Path -LiteralPath $RamModel)) {
    New-Item -ItemType Directory -Path $RamModel -Force | Out-Null
}
if (Test-Path -LiteralPath $RamRuntime) {
    # Older launchers wrote the engine's only diagnostic to R: and then deleted
    # the whole runtime at the next start. Preserve that evidence first.
    $LegacyLog = Join-Path $RamRuntime 'strata-iq3_s.log'
    if (Test-Path -LiteralPath $LegacyLog -PathType Leaf) {
        New-Item -ItemType Directory -Path $ServerLogDir -Force | Out-Null
        $PreservedLog = Join-Path $ServerLogDir "engine-previous-R-$ServerRunId.stderr.log"
        Copy-Item -LiteralPath $LegacyLog -Destination $PreservedLog -Force
        Write-Host "Preserved previous R: engine log: $PreservedLog"
    }
    Remove-Item -LiteralPath $RamRuntime -Recurse -Force
}
New-Item -ItemType Directory -Path $RamRuntime -Force | Out-Null
New-Item -ItemType Directory -Path $RamData -Force | Out-Null

$RamShard1 = Join-Path $RamModel $Names[0]
$RamShard2 = Join-Path $RamModel $Names[1]

# Shard 1 is only a link: Strata loads its expert arena into system RAM at startup.
if (Test-Path -LiteralPath $RamShard1) {
    Remove-Item -LiteralPath $RamShard1 -Force
}
New-Item -ItemType SymbolicLink -Path $RamShard1 -Target ($SourceShards[0].FullName) | Out-Null

$NeedShard2Copy = $true
if (Test-Path -LiteralPath $RamShard2 -PathType Leaf) {
    $RamShard2Item = Get-Item -LiteralPath $RamShard2
    if (-not $RamShard2Item.LinkType -and $RamShard2Item.Length -eq $SourceShards[1].Length) {
        $NeedShard2Copy = $false
        Write-Host "PLE shard2 already valid on R:; reusing it."
    }
    else {
        Remove-Item -LiteralPath $RamShard2 -Force
    }
}

$Need = (TreeBytes $PackSrc) +
        (TreeBytes $MtpSrc) +
        (Get-Item -LiteralPath $ProfileSrc).Length +
        3GB
if ($NeedShard2Copy) {
    $Need += [int64]($SourceShards[1].Length)
}

$Free = (Get-PSDrive R).Free
Write-Host ""
Write-Host "R: free          = $([math]::Round($Free/1GB,2)) GiB"
Write-Host "IQ3_S need now   = $([math]::Round($Need/1GB,2)) GiB incl. reserve"

if ($Free -lt $Need) {
    Write-Host ""
    Write-Host "Содержимое корня R:"
    Get-ChildItem "R:\" -Force |
        Select-Object Name,LinkType,Target,@{n="GiB";e={
            if (-not $_.PSIsContainer -and -not $_.LinkType) {
                [math]::Round($_.Length/1GB,3)
            }
        }} |
        Format-Table -AutoSize
    throw "На R: недостаточно места. Неизвестные/Q8 файлы автоматически не удаляются."
}

if ($NeedShard2Copy) {
    Write-Host ""
    Write-Host "===== IQ3_S PLE -> RAM ====="
    Write-Host "COPY shard2 / PLE -> R:"
    Copy-Item -LiteralPath $SourceShards[1].FullName -Destination $RamShard2 -Force
    if ((Get-Item -LiteralPath $RamShard2).Length -ne $SourceShards[1].Length) {
        throw "Размер IQ3_S shard2 после копирования не совпадает."
    }
}

Write-Host ""
Write-Host "===== HOT RUNTIME -> RAM ====="
Copy-Item -LiteralPath $PackSrc -Destination $RamPack -Recurse -Force
Copy-Item -LiteralPath $MtpSrc  -Destination $RamMtp  -Recurse -Force
Copy-Item -LiteralPath $ProfileSrc -Destination $RamProfile -Force

if (-not (Test-Path -LiteralPath "$RamPack\tokenizer\vocab.json" -PathType Leaf)) {
    throw "После копирования pack отсутствует tokenizer vocab: $RamPack\tokenizer\vocab.json"
}

$EngineArgs = [System.Collections.Generic.List[string]]::new()
@(
    "--pack", $RamPack,
    "--native", $RamShard1,
    "--ple-gguf", $RamShard2,
    "--expert-profile", $RamProfile,
    "--expert-cache", "auto",
    "--prefill", "auto"
) | ForEach-Object { $EngineArgs.Add([string]$_) }

if ($NoPrefillBorrow) {
    $EngineArgs.Add("--no-prefill-borrow")
}

# Результат калибровки хранится отдельно от служебной конфигурации и от
# шаблонов. Его можно применить только к тому же собранному движку и модели.
# Параметр -PcieFrac, переданный пользователем явно, всегда имеет приоритет.
$EffectivePcieFrac = $PcieFrac
$EffectiveSpecMinP = 0.90
$TuningFile = Join-Path $Root 'IQ3S_AUTOTUNE.json'
if (-not $IgnoreAutotune -and (Test-Path -LiteralPath $TuningFile -PathType Leaf)) {
    try {
        $Tuning = Get-Content -LiteralPath $TuningFile -Raw -Encoding utf8 |
            ConvertFrom-Json -ErrorAction Stop
        $EngineItem = Get-Item -LiteralPath $Engine -ErrorAction Stop
        if ($Tuning.version -ne 2 -or
            $Tuning.model_name -ne 'qwen3.8-flash-next-iq3_s' -or
            $Tuning.engine_name -ne $EngineItem.Name -or
            [int64]$Tuning.engine_bytes -ne [int64]$EngineItem.Length) {
            Write-Warning 'Автонастройка относится к другой модели или сборке; использую штатные значения.'
        }
        else {
            $TunedPcie = [double]$Tuning.settings.pcie_frac
            $TunedSpec = [double]$Tuning.settings.spec_min_p
            if ([double]::IsNaN($TunedPcie) -or [double]::IsNaN($TunedSpec) -or
                $TunedPcie -lt 0 -or $TunedPcie -gt 1 -or
                $TunedSpec -lt 0 -or $TunedSpec -gt 1) {
                throw 'В файле автонастройки недопустимые числовые значения.'
            }
            if (-not $PSBoundParameters.ContainsKey('PcieFrac')) {
                $EffectivePcieFrac = $TunedPcie
            }
            $EffectiveSpecMinP = $TunedSpec
            Write-Host "Автонастройка IQ3_S: PCIe=$EffectivePcieFrac, MTP draft=$EffectiveSpecMinP"
        }
    }
    catch {
        Write-Warning "Не удалось применить автонастройку ($($_.Exception.Message)); штатный профиль сохранён."
        $EffectivePcieFrac = $PcieFrac
        $EffectiveSpecMinP = 0.90
    }
}

# Preserve the existing GSQ-RCO baseline. A different PCIe share must be an
# explicit, measurable choice, not a silent change to the quality profile.
@(
    "--pcie-frac", $EffectivePcieFrac.ToString('0.00', [Globalization.CultureInfo]::InvariantCulture),
    "--spec", "4",
    "--spec-min-p", $EffectiveSpecMinP.ToString('0.00', [Globalization.CultureInfo]::InvariantCulture),
    "--mtp", $RamMtp,
    "--max-context", "262144",
    "--kv", "int8",
    "--kv-resident", "32768"
) | ForEach-Object { $EngineArgs.Add([string]$_) }

$Config = [ordered]@{
    exe = $Engine
    args = @($EngineArgs)
    cwd = $Root
    tokenizer = "$RamPack\tokenizer"
    model_name = "qwen3.8-flash-next-iq3_s"
    autotune = (-not $IgnoreAutotune)
    reasoning_budget_tokens = 10240
    log = $Log
    lib_dirs = $RuntimeDllDirs
    host = "0.0.0.0"
    port = 8080
    gpu = 0
    gpus_asked = $true
}

# Never regenerate/overwrite either user-edited config.  Root JSON wins;
# the PERSONAL_START copy is a read-only fallback.  Server receives a private
# runtime copy whose staged paths match this launch.
. (Join-Path $Root 'STRATA-MODEL-LAUNCH-COMMON.ps1')
$ExplicitArgs = @{}
if ($PSBoundParameters.ContainsKey('PcieFrac')) {
    $ExplicitArgs['--pcie-frac'] = $PcieFrac.ToString('0.00', [Globalization.CultureInfo]::InvariantCulture)
}
$RuntimeConfig = New-StrataModelRuntimeConfig -RootConfig $Cfg `
    -PersonalConfig (Join-Path $Root 'PERSONAL_START_E_ai_Strata-Q4-Fork\strata-iq3_s-RAM.json') `
    -Defaults $Config -RuntimeFlags @{
        '--pack'=$RamPack
        '--native'=$RamShard1
        '--ple-gguf'=$RamShard2
        '--expert-profile'=$RamProfile
        '--mtp'=$RamMtp
    } -ExplicitFlags $ExplicitArgs -LogDirectory $ServerLogDir -RunId $ServerRunId `
    -IgnoreAutotune:$IgnoreAutotune
Write-Host 'Пользовательский JSON не изменён.'

$env:STRATA_SSD_KEEPALIVE = "0"
# Keep the original server's progress and throughput lines visible.  The
# previous detached launcher hid them in files after printing READY.
$env:STRATA_REQUEST_LINES = '1'
$env:PYTHONUNBUFFERED = '1'

New-Item -ItemType Directory -Path $ServerLogDir -Force | Out-Null

Write-Host ""
Write-Host "Config: $RuntimeConfig"
Write-Host "Engine stderr: $Log"
Write-Host "Bind:   0.0.0.0:8080"
Write-Host "Local:  http://127.0.0.1:8080/v1"
Write-Host "Mode:   $(if ($NoPrefillBorrow) {'NO-PREFILL-BORROW diagnostic'} else {'QUALITY baseline'})"
Write-Host "PCIe fraction: $($EffectivePcieFrac.ToString('0.00', [Globalization.CultureInfo]::InvariantCulture)) (baseline 0.26)"
Write-Host "MTP spec-min-p: $($EffectiveSpecMinP.ToString('0.00', [Globalization.CultureInfo]::InvariantCulture)) (baseline 0.90)"
try {
    $Memory = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    Write-Host ("System RAM available before engine: {0:N2} GiB of {1:N2} GiB" -f `
        ($Memory.FreePhysicalMemory * 1KB / 1GB), ($Memory.TotalVisibleMemorySize * 1KB / 1GB))
}
catch {
    Write-Warning "Не удалось получить доступную системную память: $($_.Exception.Message)"
}

if (-not $Detached) {
    Write-Host ""
    Write-Host "===== LIVE SERVER: запросы, префилл, токены и скорость ====="
    Write-Host "Остановить: Ctrl+C. Прежний фоновый режим: -Detached."
    $ConsoleLog = Join-Path $ServerLogDir "console-$ServerRunId.log"
    $TranscriptStarted = $false
    try {
        try {
            # BUILD_AND_START may already have an active transcript.  An
            # unsupported nested transcript must never prevent the server
            # from running or obscure its live console output.
            Start-Transcript -LiteralPath $ConsoleLog -Append -ErrorAction Stop | Out-Null
            $TranscriptStarted = $true
        }
        catch {
            Write-Warning "Не удалось открыть дополнительный журнал консоли: $($_.Exception.Message)"
        }
        & $Python -u $Server --engine strata --config $RuntimeConfig --host 0.0.0.0 --port 8080
        $ServerExit = $LASTEXITCODE
    }
    finally {
        if ($TranscriptStarted) { Stop-Transcript | Out-Null }
    }
    if ($ServerExit -ne 0) { throw "Сервер завершился с кодом $ServerExit. Журнал: $ConsoleLog" }
    return
}

Write-Host ""
Write-Host "===== START SERVER ====="
# Python's traceback is not written to the engine log: the old detached
# Start-Process lost the actual reason for an exit code 1.  Keep both streams
# on persistent E:, outside the RAM runtime directory erased at each launch.
New-Item -ItemType Directory -Path $ServerLogDir -Force | Out-Null
$ServerStdout = Join-Path $ServerLogDir "server-$ServerRunId.stdout.log"
$ServerStderr = Join-Path $ServerLogDir "server-$ServerRunId.stderr.log"
Write-Host "Server stdout: $ServerStdout"
Write-Host "Server stderr: $ServerStderr"
$Proc = Start-Process `
    -FilePath $Python `
    -WorkingDirectory $Root `
    -ArgumentList @(
        '-u',
        "`"$Server`"",
        "--engine","strata",
        "--config","`"$RuntimeConfig`"",
        "--host","0.0.0.0",
        "--port","8080"
    ) `
    -RedirectStandardOutput $ServerStdout `
    -RedirectStandardError $ServerStderr `
    -PassThru

$Ready = $false
$ModelsResponse = $null
for ($i=0; $i -lt 180; $i++) {
    Start-Sleep 2
    $Proc.Refresh()
    if ($Proc.HasExited) {
        Write-Host "Server exited early: $($Proc.ExitCode)"
        $Proc.WaitForExit()
        break
    }

    try {
        $ModelsResponse = Invoke-RestMethod `
            -Uri "http://127.0.0.1:8080/v1/models" `
            -TimeoutSec 2
        $Ready = $true
        break
    }
    catch {
    }

    if (($i % 10) -eq 0 -and (Test-Path -LiteralPath $Log)) {
        Write-Host ""
        Get-Content -LiteralPath $Log -Tail 8
    }
    if (($i % 10) -eq 0 -and (Test-Path -LiteralPath $ServerStdout)) {
        Get-Content -LiteralPath $ServerStdout -Tail 4
    }
}

Write-Host ""
Write-Host "============================================================"
if ($Ready) {
    Write-Host "IQ3_S GSQ-RCO READY"
    Write-Host "Local API: http://127.0.0.1:8080/v1"
    Write-Host "LAN bind:  0.0.0.0:8080"
    Write-Host "============================================================"
    Write-Host ""
    $ModelsResponse | ConvertTo-Json -Depth 10
}
else {
    Write-Host "IQ3_S GSQ-RCO NOT READY"
    Write-Host "============================================================"
    Write-Host ""
    Write-Host "===== PYTHON SERVER STDERR ====="
    if (Test-Path -LiteralPath $ServerStderr) {
        Get-Content -LiteralPath $ServerStderr -Tail 100
    }
    Write-Host ""
    Write-Host "===== PYTHON SERVER STDOUT ====="
    if (Test-Path -LiteralPath $ServerStdout) {
        Get-Content -LiteralPath $ServerStdout -Tail 100
    }
    Write-Host ""
    Write-Host "Сохранены журналы: $ServerLogDir"
    if (Test-Path -LiteralPath $Log) {
        Write-Host "===== STRATA ENGINE STDERR ====="
        Write-Host "Engine stderr file: $Log"
        Get-Content -LiteralPath $Log -Tail 180
    }
    else {
        Write-Host "Движок не создал журнал ошибок: $Log"
    }
    exit 1
}

Write-Host ""
Write-Host "R: free = $([math]::Round((Get-PSDrive R).Free/1GB,2)) GiB"
