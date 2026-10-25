#requires -Version 7.0
<#
Запуск Unsloth Qwen3.8 Flash Next Q6_K.
Использует отдельный engine-q6, собранный с STRATA_Q6K_EXPERTS + STRATA_MMQ_KQUANTS.
Пользовательские JSON read-only: рабочая конфигурация создаётся в logs\q6.
SHA не вычисляется: идентичность файлов проверяется по имени и точному размеру.
#>
[CmdletBinding()]
param(
    [string]$ModelsDirectory,
    [string]$PackSource,
    [string]$MtpSource = 'E:\ai\Strata-data\mtp\rt',
    [switch]$PreparePack,
    [switch]$AllowBf16Conversion,
    [switch]$PrepareOnly,
    [switch]$PleToRam,
    [switch]$Detached,
    [switch]$Foreground,
    [switch]$IgnoreAutotune
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($Detached -and $Foreground) { throw 'Нельзя совместить -Detached и -Foreground.' }

$Root = if (Test-Path -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'serve\server.py')) { (Split-Path $PSScriptRoot -Parent) } else { 'E:\ai\Strata-Q4-Fork' }
$Data = 'E:\ai\Strata-data'
$Engine = Join-Path $Root 'engine-q6\strata.exe'
$Server = Join-Path $Root 'serve\server.py'
$AimLl = 'C:\Program Files\AIM Toolkit\aim_ll.exe'
$ProfileSource = Join-Path $Root 'data\expert-profile.bin'
$Checker = Join-Path $Root 'tools\q6_ple_preflight.py'
$Builder = Join-Path $Root 'tools\iq_pack.py'
$DependencyCheck = Join-Path $Root 'tools\ensure_gguf_py.py'
$RamModel = 'R:\q6-model'
$RamRuntime = 'R:\strata-runtime-q6'
$RamPack = Join-Path $RamRuntime 'pack'
$RamMtp = Join-Path $RamRuntime 'mtp'
$RamProfile = Join-Path $RamRuntime 'data\expert-profile.bin'
$ConfigPath = Join-Path $Root 'strata-unsloth-q6_k-RAM.json'
$PersonalConfig = Join-Path $Root 'PERSONAL_START_E_ai_Strata-Q4-Fork\strata-unsloth-q6_k-RAM.json'
$LogDir = Join-Path $Root 'logs\q6'
$RunId = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$EngineLog = Join-Path $LogDir "engine-$RunId.stderr.log"
$CheckpointFile = Join-Path $LogDir 'Q6_START_LAST.txt'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
[IO.File]::WriteAllText($CheckpointFile, ("Запуск Q6_K, итерация 059, {0}`r`n" -f (Get-Date -Format 'o')), [Text.UTF8Encoding]::new($false))

function Write-Q6Checkpoint([string]$Message) {
    $Line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message
    Write-Host $Line -ForegroundColor Cyan
    Add-Content -LiteralPath $CheckpointFile -Value $Line -Encoding utf8
}
function Get-TreeBytes([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return [int64](Get-Item -LiteralPath $Path).Length }
    $M = Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction Stop | Measure-Object Length -Sum
    if ($null -eq $M.Sum) { return [int64]0 }
    return [int64]$M.Sum
}
function Assert-NameSize([string]$Source, [string]$Destination, [string]$Label) {
    $A = Get-Item -LiteralPath $Source -ErrorAction Stop
    $B = Get-Item -LiteralPath $Destination -ErrorAction Stop
    if (-not [string]::Equals($A.Name,$B.Name,[StringComparison]::OrdinalIgnoreCase) -or [int64]$A.Length -ne [int64]$B.Length) {
        throw "${Label}: имя/точный размер не совпали."
    }
}

Write-Host '============================================================'
Write-Host ' STRATA Q6_K / NATIVE EXPERTS / RAM RUNTIME / QUALITY'
Write-Host '============================================================'
Write-Host "Root: $Root"
Write-Host 'API:  http://127.0.0.1:8080/v1'
Write-Host ('PLE:  {0}' -f $(if ($PleToRam) {'копия исходного PLE-шарда на R:'} else {'исходный GGUF на E: через ссылку (по умолчанию)'}))

$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = [Security.Principal.WindowsPrincipal]::new($Identity)
if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Запустите PowerShell 7 от имени администратора: нужны R: и символические ссылки.'
}
. (Join-Path $Root 'STRATA-MODEL-LAUNCH-COMMON.ps1')
$Python = Resolve-StrataModelPython -Root $Root
Ensure-StrataServerPythonDependencies -Root $Root -Python $Python
foreach ($Required in @($Server,$AimLl,$Checker,$Builder,$DependencyCheck,$ProfileSource,$MtpSource)) {
    if (-not (Test-Path -LiteralPath $Required)) { throw "Не найден обязательный путь: $Required" }
}
if (-not (Test-Path -LiteralPath $Engine -PathType Leaf)) {
    throw 'Отдельный Q6 engine не найден. Сначала запустите BUILD-Q6-ENGINE.bat (или BUILD-Q6-ENGINE.ps1). Основной engine\strata.exe не заменяется.'
}

# Пользовательская модель Q6_K: ровно пять GGUF-шардов.
$FirstName = $null
if ([string]::IsNullOrWhiteSpace($ModelsDirectory)) {
    foreach ($Candidate in @('E:\ai\models\unsloth\Qwen3.8-Flash-Next-GGUF','E:\ai\Strata-data\models\Q6_K')) {
        $First = 'Qwen3.8-Flash-Next-Q6_K-00001-of-00005.gguf'
        if (Test-Path -LiteralPath (Join-Path $Candidate $First) -PathType Leaf) { $ModelsDirectory=$Candidate; $FirstName=$First; break }
    }
} else {
    $First = 'Qwen3.8-Flash-Next-Q6_K-00001-of-00005.gguf'
    if (Test-Path -LiteralPath (Join-Path $ModelsDirectory $First) -PathType Leaf) { $FirstName=$First }
}
if (-not $ModelsDirectory -or -not $FirstName) {
    throw 'Не найден комплект Q6_K из пяти шардов Qwen3.8-Flash-Next-Q6_K-00001-of-00005.gguf ... 00005-of-00005.gguf; можно передать -ModelsDirectory.'
}
$FirstShard = Join-Path $ModelsDirectory $FirstName
Write-Q6Checkpoint "Проверяю GGUF-заголовки Q6_K: $FirstShard"
$AuditOutput = @(& $Python $Checker $FirstShard --json 2>&1)
if ($LASTEXITCODE -ne 0) { throw "Q6_K preflight отклонил модель: $($AuditOutput -join ' ')" }
try { $Audit = ($AuditOutput -join "`n") | ConvertFrom-Json -ErrorAction Stop } catch { throw "Некорректный JSON preflight Q6_K: $($_.Exception.Message)" }
if ([int]$Audit.shards -ne 5 -or -not $Audit.ple_source -or [string]$Audit.ple_type -ne 'Q8_0') { throw 'Q6_K preflight вернул неполные данные.' }
$SourceFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
foreach ($Entry in $Audit.files) {
    $Path = Join-Path $ModelsDirectory ([string]$Entry.name)
    $Item = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ([int64]$Item.Length -ne [int64]$Entry.bytes) { throw "Размер GGUF изменился после проверки заголовков: $($Item.Name)" }
    $SourceFiles.Add($Item)
}
$PleSource = (Resolve-Path -LiteralPath ([string]$Audit.ple_source)).Path
$PleFile = Get-Item -LiteralPath $PleSource
Write-Q6Checkpoint ('Q6_K: {0} шардов; PLE={1}, файл={2}, {3:N2} ГиБ.' -f $SourceFiles.Count,$Audit.ple_type,$PleFile.Name,($PleFile.Length/1GB))

if (-not $PackSource) {
    foreach ($Candidate in @((Join-Path $Data 'packs\unsloth-q6_k'),(Join-Path $Data 'packs\q6_k'))) {
        if (Test-Path -LiteralPath (Join-Path $Candidate 'tokenizer\vocab.json') -PathType Leaf) { $PackSource=$Candidate; break }
    }
}
if (-not $PackSource) { $PackSource = Join-Path $Data 'packs\unsloth-q6_k' }
if (-not (Test-Path -LiteralPath (Join-Path $PackSource 'tokenizer\vocab.json') -PathType Leaf)) {
    if (-not $PreparePack) { throw 'Нативный Q6 pack не найден. Запустите PREPARE-Q6.bat либо START-Q6-RAM.ps1 -PreparePack -AllowBf16Conversion.' }
    if (-not $AllowBf16Conversion) { throw 'Q6 pack требует -AllowBf16Conversion для совместимых плотных проекций; Q6_K/Q8_0 эксперты и PLE не переквантуются.' }
    if (Test-Path -LiteralPath $PackSource) { throw "Неполный Q6 pack уже существует: $PackSource. Автоматически не перезаписываю." }
    Write-Host '===== ПРОВЕРКА gguf-py ====='
    & $Python -u $DependencyCheck --install-if-missing
    if ($LASTEXITCODE -ne 0) { throw 'gguf-py недоступен; Q6 pack не создан.' }
    $Staging = "$PackSource.building-051-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path (Split-Path -Parent $PackSource) -Force | Out-Null
    Write-Q6Checkpoint "Строю native Q6 pack во временном каталоге: $Staging"
    & $Python -u $Builder --gguf $FirstShard --out $Staging --compat-bf16
    if ($LASTEXITCODE -ne 0) { throw "Сборка Q6 pack завершилась ошибкой: $Staging" }
    foreach ($RequiredFile in @('index.txt','dense.bin','native_experts.txt','tokenizer\vocab.json')) {
        $P = Join-Path $Staging $RequiredFile
        if (-not (Test-Path -LiteralPath $P -PathType Leaf) -or (Get-Item -LiteralPath $P).Length -eq 0) { throw "Неполный Q6 pack: $P" }
    }
    $Stamp = [ordered]@{model='qwen3.8-flash-next-unsloth-q6_k'; files=@($SourceFiles | ForEach-Object {[ordered]@{name=$_.Name;bytes=[int64]$_.Length}}); ple_type=[string]$Audit.ple_type; compat_bf16=$true}
    [IO.File]::WriteAllText((Join-Path $Staging 'Q6-PACK-SOURCE.json'), ($Stamp|ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $Staging -Destination $PackSource -ErrorAction Stop
    Write-Q6Checkpoint "Q6 pack готов: $PackSource"
}
foreach ($RequiredFile in @('index.txt','dense.bin','native_experts.txt','tokenizer\vocab.json')) {
    $P = Join-Path $PackSource $RequiredFile
    if (-not (Test-Path -LiteralPath $P -PathType Leaf)) { throw "Q6 pack неполный: $P" }
}
$StampPath = Join-Path $PackSource 'Q6-PACK-SOURCE.json'
if (Test-Path -LiteralPath $StampPath -PathType Leaf) {
    $Stamp = Get-Content -LiteralPath $StampPath -Raw -Encoding utf8 | ConvertFrom-Json
    if (@($Stamp.files).Count -ne $SourceFiles.Count) { throw 'Q6 pack относится к другому числу GGUF-шардов.' }
    for ($I=0; $I -lt $SourceFiles.Count; $I++) {
        if (-not [string]::Equals([string]$Stamp.files[$I].name,$SourceFiles[$I].Name,[StringComparison]::OrdinalIgnoreCase) -or [int64]$Stamp.files[$I].bytes -ne [int64]$SourceFiles[$I].Length) {
            throw "Q6 pack не соответствует текущему GGUF по имени/точному размеру: $($SourceFiles[$I].Name)"
        }
    }
}
if ($PrepareOnly) { Write-Host 'Q6 pack подготовлен/проверен. -PrepareOnly: запуск сервера пропущен.' -ForegroundColor Green; return }

Assert-StrataModelServerStopped -Port 8080
Assert-StrataModelEngineStopped -Root $Root
$DllDirs = @(Initialize-StrataModelDlls -Root $Root -Engine $Engine -LogDirectory $LogDir)
$PackBytes = Get-TreeBytes $PackSource
$MtpBytes = Get-TreeBytes $MtpSource
$ProfileBytes = (Get-Item -LiteralPath $ProfileSource).Length
$PleBytes = if ($PleToRam) {[int64]$PleFile.Length} else {0L}
$Need = $PackBytes + $MtpBytes + $ProfileBytes + $PleBytes + 2GB
Ensure-StrataModelRamDisk -AimLl $AimLl -Root $Root -RequiredBytes $Need
$Volume = Get-Volume -DriveLetter R -ErrorAction Stop
if ($Volume.FileSystem -ne 'NTFS') { throw 'R: должен быть NTFS RAM-диском.' }

# Удаляем только известные временные кэши других профилей, не неизвестные файлы.
foreach ($Old in @('R:\iq3s-model','R:\strata-iq3s-runtime','R:\q4-model','R:\strata-q4-runtime','R:\q8-model','R:\strata-runtime-q8')) {
    if (Test-Path -LiteralPath $Old) { Write-Host "Удаляю временный кэш другой модели: $Old"; Remove-Item -LiteralPath $Old -Recurse -Force }
}
foreach ($Own in @($RamModel,$RamRuntime)) { if (Test-Path -LiteralPath $Own) { Remove-Item -LiteralPath $Own -Recurse -Force } }
New-Item -ItemType Directory -Path $RamModel -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $RamRuntime 'data') -Force | Out-Null

$PackBytes = Get-TreeBytes $PackSource
$MtpBytes = Get-TreeBytes $MtpSource
$ProfileBytes = (Get-Item -LiteralPath $ProfileSource).Length
$PleBytes = if ($PleToRam) {[int64]$PleFile.Length} else {0L}
$Need = $PackBytes + $MtpBytes + $ProfileBytes + $PleBytes + 2GB
$Free = (Get-PSDrive R).Free
Write-Q6Checkpoint ('R: нужно {0:N2} ГиБ, свободно {1:N2} ГиБ. PLE->RAM={2}.' -f ($Need/1GB),($Free/1GB),[bool]$PleToRam)
if ($Free -lt $Need) { throw 'На R: недостаточно места для выбранного режима Q6. Повторите без -PleToRam или освободите RAM-диск вручную.' }

# На R: создаётся полный split-namespace. Один PLE-шард можно физически положить в RAM; остальные остаются ссылками на E:.
foreach ($Source in $SourceFiles) {
    $Dst = Join-Path $RamModel $Source.Name
    if ($PleToRam -and [string]::Equals($Source.FullName,$PleSource,[StringComparison]::OrdinalIgnoreCase)) {
        Write-Q6Checkpoint ('Копирую PLE-шард Q6 в RAM: {0:N2} ГиБ.' -f ($Source.Length/1GB))
        Copy-Item -LiteralPath $Source.FullName -Destination $Dst -ErrorAction Stop
        Assert-NameSize -Source $Source.FullName -Destination $Dst -Label 'Q6 PLE'
    } else {
        New-Item -ItemType SymbolicLink -Path $Dst -Target $Source.FullName -ErrorAction Stop | Out-Null
    }
}
Write-Q6Checkpoint 'Копирую Q6 pack, MTP и expert-profile на R:.'
Copy-Item -LiteralPath $PackSource -Destination $RamPack -Recurse -Force -ErrorAction Stop
Copy-Item -LiteralPath $MtpSource -Destination $RamMtp -Recurse -Force -ErrorAction Stop
Copy-Item -LiteralPath $ProfileSource -Destination $RamProfile -Force -ErrorAction Stop

$FirstRam = Join-Path $RamModel $SourceFiles[0].Name
$EngineArgs = [System.Collections.Generic.List[string]]::new()
@('--pack',$RamPack,'--native',$FirstRam,'--expert-profile',$RamProfile,'--expert-cache','auto','--prefill','auto',
  '--pcie-frac','0.09','--spec','4','--spec-min-p','0.9','--suffix-draft','0','--mtp',$RamMtp,'--max-context','262144','--kv','int8','--kv-resident','32768',
  '--resident-budget-gib','120','--adapt-every','0','--adapt-swaps','0','--prompt-cache','0','--ple-require-type',[string]$Audit.ple_type) |
    ForEach-Object { $EngineArgs.Add([string]$_) }
$Config = [ordered]@{exe=$Engine;args=@($EngineArgs.ToArray());cwd=$Root;tokenizer=(Join-Path $RamPack 'tokenizer');model_name='qwen3.8-flash-next-unsloth-q6_k';log=(Join-Path $RamRuntime 'strata-unsloth-q6_k.log');lib_dirs=@($DllDirs);port=8080;parallel=2;gpu=0;gpus_asked=$true}
$RuntimeConfig = New-StrataModelRuntimeConfig -RootConfig $ConfigPath -PersonalConfig $PersonalConfig -Defaults $Config -RuntimeFlags @{
    '--pack'=$RamPack;'--native'=$FirstRam;'--expert-profile'=$RamProfile;'--mtp'=$RamMtp;'--ple-require-type'=[string]$Audit.ple_type
} -LogDirectory $LogDir -RunId $RunId -IgnoreAutotune:$IgnoreAutotune
$env:STRATA_SSD_KEEPALIVE='0'
$env:STRATA_IQ_MT_MIN='1'
Write-Host "Пользовательский JSON не изменён. Runtime config: $RuntimeConfig"
Write-Host ('Свободно на R: {0:N2} GiB' -f ((Get-PSDrive R).Free/1GB))
Write-Q6Checkpoint 'Q6 runtime готов. Запускаю server.py.'
if (-not $Detached) {
    Write-Host '===== ЖИВОЙ ВЫВОД: запросы, префилл, генерация ====='
    Write-Host 'Остановить: Ctrl+C. Фоновый режим: -Detached.'
    & $Python -u $Server --engine strata --config $RuntimeConfig --host 0.0.0.0 --port 8080
    if ($LASTEXITCODE -ne 0) { throw "Q6 server завершился с кодом $LASTEXITCODE. Лог: $EngineLog" }
    return
}
$Stdout=Join-Path $LogDir "server-$RunId.stdout.log"; $Stderr=Join-Path $LogDir "server-$RunId.stderr.log"
$Process=Start-Process -FilePath $Python -WorkingDirectory $Root -PassThru -ArgumentList @('-u',"`"$Server`"",'--engine','strata','--config',"`"$RuntimeConfig`"",'--host','0.0.0.0','--port','8080') -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr
$Ready=$false
for($Attempt=0;$Attempt -lt 180;$Attempt++){
    Start-Sleep -Seconds 2; $Process.Refresh(); if($Process.HasExited){break}
    try { $R=Invoke-RestMethod -Uri 'http://127.0.0.1:8080/v1/models' -TimeoutSec 2; if(@($R.data|Where-Object {$_.id -eq 'qwen3.8-flash-next-unsloth-q6_k'}).Count -gt 0){$Ready=$true;break} } catch {}
}
if(-not $Ready){ throw "Q6 не вышел в READY. stdout=$Stdout stderr=$Stderr engine=$EngineLog" }
Write-Host 'Q6_K READY: http://127.0.0.1:8080/v1' -ForegroundColor Green
