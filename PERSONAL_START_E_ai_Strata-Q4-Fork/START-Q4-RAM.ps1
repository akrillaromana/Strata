param(
    [switch]$Foreground,
    [switch]$NoPrefillBorrow,
    [switch]$Detached
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Root   = "E:\ai\Strata-Q4-Fork"
$Data   = "E:\ai\Strata-data"
$Models = "E:\ai\models\unsloth\Qwen3.8-Flash-Next-GGUF"

$Python = $null
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
if ($Foreground -and $Detached) { throw 'Нельзя одновременно использовать -Foreground и -Detached.' }
. (Join-Path $Root 'STRATA-MODEL-LAUNCH-COMMON.ps1')
$Python = Resolve-StrataModelPython -Root $Root

Write-Host ""
Write-Host "========================================"
Write-Host " STRATA Q4_K_XL QUALITY RAM LAUNCHER"
Write-Host "========================================"

foreach ($P in @(
    $Server,$Engine,$AimLl,$PackSrc,$MtpSrc,$ProfileSrc
)) {
    if (-not (Test-Path -LiteralPath $P)) {
        throw "Не найден обязательный путь: $P"
    }
}

$SourceShards = @()
$ServerLogDir = Join-Path $Root 'logs\q4'
$RuntimeDllDirs = @(Initialize-StrataModelDlls -Root $Root -Engine $Engine -LogDirectory $ServerLogDir)
foreach ($N in $Names) {
    $P = Join-Path $Models $N
    if (-not (Test-Path -LiteralPath $P)) {
        throw "Не найден Q4 shard: $P"
    }
    $SourceShards += Get-Item -LiteralPath $P
}

Assert-StrataModelServerStopped -Port 8080
Assert-StrataModelEngineStopped -Root $Root
Ensure-StrataModelRamDisk -AimLl $AimLl -Root $Root

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
    "--spec-min-p", "0.75",
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
    lib_dirs = @($RuntimeDllDirs)
    autotune = $true
    host = "0.0.0.0"
    port = 8080
    gpu = 0
    gpus_asked = $true
}

# User configuration stays byte-for-byte unchanged. Only the transient
# server copy gets paths to the freshly staged runtime on R:.
$RuntimeConfig = New-StrataModelRuntimeConfig -RootConfig $Cfg `
    -PersonalConfig (Join-Path $Root 'PERSONAL_START_E_ai_Strata-Q4-Fork\strata-unsloth-ud-q4_k_xl-RAM.json') `
    -Defaults $Config -RuntimeFlags @{
        '--pack'=$RamPack
        '--native'=(Join-Path $RamModel $Names[0])
        '--expert-profile'=$RamProfile
        '--mtp'=$RamMtp
    } -LogDirectory $ServerLogDir -RunId (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
Write-Host 'Пользовательский JSON не изменён.'

$env:STRATA_SSD_KEEPALIVE = "0"
$env:STRATA_IQ_MT_MIN     = "1"

if (Test-Path -LiteralPath $Log) {
    Clear-Content -LiteralPath $Log
}

Write-Host ""
Write-Host "Config: $RuntimeConfig"
Write-Host "API:    http://127.0.0.1:8080/v1"
Write-Host "Mode:   $(if ($NoPrefillBorrow) {'NO-PREFILL-BORROW diagnostic'} else {'QUALITY'})"

if (-not $Detached) {
    Write-Host ""
    Write-Host "===== ЖИВОЙ ВЫВОД: запросы, префилл, генерация токенов ====="
    Write-Host 'Для остановки нажмите Ctrl+C; прежний фоновый режим: -Detached.'
    & $Python -u $Server --engine strata --config $RuntimeConfig --host 0.0.0.0 --port 8080
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
        "--config","`"$RuntimeConfig`"",
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
