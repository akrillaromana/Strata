param(
    [switch]$Foreground,
    [switch]$NoPrefillBorrow
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Reuse the CURRENT Strata-Q4 installation/engine/server.
# IQ3_S has its own model/pack/runtime paths; the persistent Q4 files on E: are not modified.
$Root   = "E:\ai\Strata-Q4"
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
$Log = "$RamRuntime\strata-iq3_s.log"

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

Assert-Admin

Write-Host ""
Write-Host "============================================================"
Write-Host " STRATA IQ3_S GSQ-RCO / RAM PLE / QUALITY"
Write-Host "============================================================"
Write-Host "Engine root: $Root"
Write-Host "Models:      $Models"
Write-Host "Bind:        0.0.0.0:8080"
Write-Host ""

foreach ($P in @(
    $Python,$Server,$Engine,$AimLl,$PackSrc,$MtpSrc,$ProfileSrc,$TokenizerVocab
)) {
    if (-not (Test-Path -LiteralPath $P)) {
        throw "Не найден обязательный путь: $P"
    }
}

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

# Stop whichever model from this Strata-Q4 root is currently using port/engine.
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

# Use the current Strata IQ3_S baseline, not Q4-specific copied tuning.
@(
	"--pcie-frac", "0.26",
    "--spec", "4",
    "--spec-min-p", "0.75",
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
    reasoning_budget_tokens = 10240
    log = $Log
    lib_dirs = @(
        "$Root\.venv\Lib\site-packages\nvidia\cu13\bin\x86_64"
    )
    host = "0.0.0.0"
    port = 8080
    gpu = 0
    gpus_asked = $true
}

# Keep user-editable server options when RAM paths are rebuilt.
# The generated engine/cwd/pack paths intentionally remain managed by this launcher.
# Fail closed on malformed JSON and keep a recoverable .bak before replacement.
$PreviousConfigText = $null
if (Test-Path -LiteralPath $Cfg -PathType Leaf) {
    $PreviousConfigText = [System.IO.File]::ReadAllText($Cfg, [System.Text.Encoding]::UTF8)
    if ([string]::IsNullOrWhiteSpace($PreviousConfigText)) {
        throw "Refusing to replace an empty existing configuration: $Cfg"
    }
    try {
        $PreviousConfig = ConvertFrom-Json -InputObject $PreviousConfigText -ErrorAction Stop
    }
    catch {
        throw "Invalid existing configuration $Cfg : $($_.Exception.Message)"
    }
    if ($PreviousConfig -isnot [pscustomobject]) {
        throw "Existing configuration must be a JSON object: $Cfg"
    }
    foreach ($Property in $PreviousConfig.PSObject.Properties) {
        if ($Property.Name -eq 'sampling') {
            if ($Property.Value -isnot [pscustomobject]) {
                throw "Existing sampling must be an object: $Cfg"
            }
            $Config['sampling'] = $Property.Value
        }
        elseif ($Property.Name -eq 'repeat_stop_tokens') {
            if (($Property.Value -isnot [int]) -and ($Property.Value -isnot [long])) {
                throw "Existing repeat_stop_tokens must be a non-negative integer: $Cfg"
            }
            if ($Property.Value -lt 0) {
                throw "Existing repeat_stop_tokens must not be negative: $Cfg"
            }
            $Config['repeat_stop_tokens'] = $Property.Value
        }
        elseif (-not $Config.Contains($Property.Name)) {
            $Config[$Property.Name] = $Property.Value
        }
    }
}
$NextConfigText = ($Config | ConvertTo-Json -Depth 64) + [Environment]::NewLine
$null = ConvertFrom-Json -InputObject $NextConfigText -ErrorAction Stop
if (-not [string]::Equals($PreviousConfigText, $NextConfigText, [System.StringComparison]::Ordinal)) {
    $TemporaryConfig = "$Cfg.tmp-$([guid]::NewGuid().ToString('N'))"
    try {
        $Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($TemporaryConfig, $NextConfigText, $Utf8NoBom)
        if (Test-Path -LiteralPath $Cfg -PathType Leaf) {
            [System.IO.File]::Replace($TemporaryConfig, $Cfg, "$Cfg.bak")
        }
        else {
            [System.IO.File]::Move($TemporaryConfig, $Cfg)
        }
    }
    finally {
        if (Test-Path -LiteralPath $TemporaryConfig -PathType Leaf) {
            Remove-Item -LiteralPath $TemporaryConfig -Force
        }
    }
}


$env:STRATA_SSD_KEEPALIVE = "0"

if (Test-Path -LiteralPath $Log) {
    Clear-Content -LiteralPath $Log
}

Write-Host ""
Write-Host "Config: $Cfg"
Write-Host "Bind:   0.0.0.0:8080"
Write-Host "Local:  http://127.0.0.1:8080/v1"
Write-Host "Mode:   $(if ($NoPrefillBorrow) {'NO-PREFILL-BORROW diagnostic'} else {'QUALITY baseline'})"

if ($Foreground) {
    Write-Host ""
    Write-Host "===== FOREGROUND START ====="
    & $Python $Server --engine strata --config $Cfg --host 0.0.0.0 --port 8080
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "===== START SERVER ====="
$Proc = Start-Process `
    -FilePath $Python `
    -WorkingDirectory $Root `
    -ArgumentList @(
        "`"$Server`"",
        "--engine","strata",
        "--config","`"$Cfg`"",
        "--host","0.0.0.0",
        "--port","8080"
    ) `
    -PassThru

$Ready = $false
$ModelsResponse = $null
for ($i=0; $i -lt 180; $i++) {
    Start-Sleep 2
    $Proc.Refresh()
    if ($Proc.HasExited) {
        Write-Host "Server exited early: $($Proc.ExitCode)"
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
    if (Test-Path -LiteralPath $Log) {
        Write-Host ""
        Get-Content -LiteralPath $Log -Tail 180
    }
    exit 1
}

Write-Host ""
Write-Host "R: free = $([math]::Round((Get-PSDrive R).Free/1GB,2)) GiB"
