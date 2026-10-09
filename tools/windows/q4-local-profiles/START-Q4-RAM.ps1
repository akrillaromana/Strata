param(
    [switch]$Foreground,
    [switch]$NoPrefillBorrow
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Root   = "E:\ai\Strata-Q4"
$Data   = "E:\ai\Strata-data"
$Models = "E:\ai\models\unsloth\Qwen3.8-Flash-Next-GGUF"

$Python = "$Root\.venv\Scripts\python.exe"
$Server = "$Root\serve\server.py"
$Engine = "$Root\engine\strata.exe"
$AimLl  = "C:\Program Files\AIM Toolkit\aim_ll.exe"

$PackSrc    = "$Data\packs\unsloth-ud-q4_k_xl"
$MtpSrc     = "$Data\mtp\rt"
$ProfileSrc = "$Root\data\expert-profile.bin"

$RamModel   = "R:\q4-model"
$RamRuntime = "R:\strata-q4-runtime"
$RamPack    = "$RamRuntime\pack"
$RamMtp     = "$RamRuntime\mtp"
$RamData    = "$RamRuntime\data"
$RamProfile = "$RamData\expert-profile.bin"

$Cfg = "$Root\strata-unsloth-ud-q4_k_xl-RAM.json"
$Log = "$RamRuntime\strata-unsloth-ud-q4_k_xl.log"

$Names = @(
    "Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf",
    "Qwen3.8-Flash-Next-UD-Q4_K_XL-00002-of-00004.gguf",
    "Qwen3.8-Flash-Next-UD-Q4_K_XL-00003-of-00004.gguf",
    "Qwen3.8-Flash-Next-UD-Q4_K_XL-00004-of-00004.gguf"
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

Assert-Admin

Write-Host ""
Write-Host "========================================"
Write-Host " STRATA Q4_K_XL QUALITY RAM LAUNCHER"
Write-Host "========================================"

foreach ($P in @(
    $Python,$Server,$Engine,$AimLl,$PackSrc,$MtpSrc,$ProfileSrc
)) {
    if (-not (Test-Path -LiteralPath $P)) {
        throw "Не найден обязательный путь: $P"
    }
}

$SourceShards = @()
foreach ($N in $Names) {
    $P = Join-Path $Models $N
    if (-not (Test-Path -LiteralPath $P)) {
        throw "Не найден Q4 shard: $P"
    }
    $SourceShards += Get-Item -LiteralPath $P
}

Get-CimInstance Win32_Process |
    Where-Object {
        $_.ProcessId -ne $PID -and
        $_.CommandLine -and (
            $_.CommandLine -like "*$Root\serve\server.py*" -or
            $_.CommandLine -like "*$Root\engine\strata.exe*" -or
            $_.CommandLine -like "*strata-unsloth-ud-q4_k_xl-RAM.json*"
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


# ------------------------------------------------------------
# Clean only the OLD Q4 RAM layout from earlier iterations.
# These are ephemeral RAM-disk files/links; originals on E: are untouched.
# Do NOT automatically remove q8-* paths here: a separate Q8 installation
# may intentionally be using the shared RAM disk.
# ------------------------------------------------------------
$LegacyQ4RamPaths = @(
    "R:\Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf",
    "R:\Qwen3.8-Flash-Next-UD-Q4_K_XL-00002-of-00004.gguf",
    "R:\Qwen3.8-Flash-Next-UD-Q4_K_XL-00003-of-00004.gguf",
    "R:\Qwen3.8-Flash-Next-UD-Q4_K_XL-00004-of-00004.gguf",
    "R:\strata-runtime"
)

foreach ($P in $LegacyQ4RamPaths) {
    if (Test-Path -LiteralPath $P) {
        Write-Host "Removing legacy Q4 RAM-only path: $P"
        Remove-Item -LiteralPath $P -Recurse -Force
    }
}

# Switching IQ3_S -> Q4: remove only the known ephemeral IQ3_S RAM copy/runtime.
foreach ($P in @("R:\iq3s-model", "R:\strata-iq3s-runtime")) {
    if (Test-Path -LiteralPath $P) {
        Write-Host "Removing conflicting ephemeral IQ3_S RAM path: $P"
        Remove-Item -LiteralPath $P -Recurse -Force
    }
}

foreach ($P in @($RamModel,$RamRuntime)) {
    if (Test-Path -LiteralPath $P) {
        Remove-Item -LiteralPath $P -Recurse -Force
    }
}

New-Item -ItemType Directory -Path $RamModel -Force | Out-Null
New-Item -ItemType Directory -Path $RamRuntime -Force | Out-Null
New-Item -ItemType Directory -Path $RamData -Force | Out-Null

$Need = [int64]$SourceShards[1].Length +
        (TreeBytes $PackSrc) +
        (TreeBytes $MtpSrc) +
        (Get-Item -LiteralPath $ProfileSrc).Length +
        3GB

$Free = (Get-PSDrive R).Free

Write-Host ""
Write-Host "R: free     = $([math]::Round($Free/1GB,2)) GiB"
Write-Host "Q4 required = $([math]::Round($Need/1GB,2)) GiB incl. reserve"

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

Write-Host ""
Write-Host "===== Q4 SPLIT -> RAM ====="

for ($i=0; $i -lt 4; $i++) {
    $Src = $SourceShards[$i].FullName
    $Dst = Join-Path $RamModel $Names[$i]

    if ($i -eq 1) {
        Write-Host "COPY shard2 (PLE) -> RAM"
        Copy-Item -LiteralPath $Src -Destination $Dst -Force

        if ((Get-Item -LiteralPath $Src).Length -ne (Get-Item -LiteralPath $Dst).Length) {
            throw "Размер shard2 после копирования не совпадает."
        }
    }
    else {
        Write-Host "LINK shard $($i+1) -> E:"
        New-Item -ItemType SymbolicLink -Path $Dst -Target $Src | Out-Null
    }
}

Write-Host ""
Write-Host "===== HOT RUNTIME -> RAM ====="

Copy-Item -LiteralPath $PackSrc -Destination $RamPack -Recurse -Force
Copy-Item -LiteralPath $MtpSrc  -Destination $RamMtp  -Recurse -Force
Copy-Item -LiteralPath $ProfileSrc -Destination $RamProfile -Force

$EngineArgs = [System.Collections.Generic.List[string]]::new()

@(
    "--pack", $RamPack,
    "--native", (Join-Path $RamModel $Names[0]),
    "--expert-profile", $RamProfile,
    "--expert-cache", "auto",
    "--prefill", "auto"
) | ForEach-Object { $EngineArgs.Add([string]$_) }

if ($NoPrefillBorrow) {
    $EngineArgs.Add("--no-prefill-borrow")
}

@(
    "--spec", "4",
    "--spec-min-p", "0.5",
    "--suffix-draft", "0",
    "--mtp", $RamMtp,
    "--max-context", "262144",
    "--kv", "int8",
    "--kv-resident", "32768",
    "--resident-budget-gib", "80",
    "--pcie-frac", "0",
    "--adapt-every", "0",
    "--adapt-swaps", "0",
    "--prompt-cache", "0"
) | ForEach-Object { $EngineArgs.Add([string]$_) }

$Config = [ordered]@{
    exe = $Engine
    args = @($EngineArgs)
    cwd = $Root
    tokenizer = "$RamPack\tokenizer"
    model_name = "qwen3.8-flash-next-unsloth-ud-q4_k_xl"
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

$Config |
    ConvertTo-Json -Depth 32 |
    Set-Content -LiteralPath $Cfg -Encoding utf8

$env:STRATA_SSD_KEEPALIVE = "0"
$env:STRATA_IQ_MT_MIN     = "1"

if (Test-Path -LiteralPath $Log) {
    Clear-Content -LiteralPath $Log
}

Write-Host ""
Write-Host "Config: $Cfg"
Write-Host "API:    http://127.0.0.1:8080/v1"
Write-Host "Mode:   $(if ($NoPrefillBorrow) {'NO-PREFILL-BORROW diagnostic'} else {'QUALITY'})"

if ($Foreground) {
    Write-Host ""
    Write-Host "===== FOREGROUND START ====="
    & $Python $Server --engine strata --config $Cfg --port 8080
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
        "--port","8080"
    ) `
    -PassThru

$Ready = $false

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
        Get-Content -LiteralPath $Log -Tail 5
    }
}

Write-Host ""
Write-Host "========================================"

if ($Ready) {
    Write-Host "Q4_K_XL READY"
    Write-Host "http://127.0.0.1:8080/v1"
    Write-Host "========================================"
    Write-Host ""
    $ModelsResponse | ConvertTo-Json -Depth 10
}
else {
    Write-Host "Q4_K_XL NOT READY"
    Write-Host "========================================"
    if (Test-Path -LiteralPath $Log) {
        Write-Host ""
        Get-Content -LiteralPath $Log -Tail 150
    }
    exit 1
}

Write-Host ""
Write-Host "R: free = $([math]::Round((Get-PSDrive R).Free/1GB,2)) GiB"
