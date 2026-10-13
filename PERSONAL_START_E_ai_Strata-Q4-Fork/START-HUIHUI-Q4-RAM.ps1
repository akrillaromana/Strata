param(
    [switch]$Foreground,
    [switch]$NoPrefillBorrow,
    [switch]$ResumeRam,
    [switch]$UseSourceNative,
    [switch]$ExplicitNativeDense,
    [switch]$Detached
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Root   = "E:\ai\Strata-Q4-Fork"
$Data   = "E:\ai\Strata-data"
$Models = "E:\ai\models\huihui-ai\Huihui-Qwen3.8-Flash-Next-abliterated-GGUF"

$Python = $null
$Server = "$Root\serve\server.py"
$Engine = "$Root\engine\strata.exe"
$AimLl  = "C:\Program Files\AIM Toolkit\aim_ll.exe"

$PackSrc    = "$Data\packs\huihui-ud-q4_k_xl"
$MtpSrc     = "$Data\mtp\rt"
$ProfileSrc = "$Root\data\expert-profile.bin"

$RamModel   = "R:\q4-model"
$RamRuntime = "R:\strata-q4-runtime"
$RamPack    = "$RamRuntime\pack"
$RamMtp     = "$RamRuntime\mtp"
$RamData    = "$RamRuntime\data"
$RamProfile = "$RamData\expert-profile.bin"

$Cfg = "$Root\strata-huihui-ud-q4_k_xl-RAM.json"
$Log = "$RamRuntime\strata-huihui-ud-q4_k_xl.log"

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
Write-Host " STRATA HUIHUI UD-Q4_K_XL RAM LAUNCHER"
Write-Host "========================================"

foreach ($P in @(
    $Server,$Engine,$AimLl,$PackSrc,$MtpSrc,$ProfileSrc
)) {
    if (-not (Test-Path -LiteralPath $P)) {
        throw "Не найден обязательный путь: $P"
    }
}

$SourceShards = @()
$ServerLogDir = Join-Path $Root 'logs\huihui-q4'
$RuntimeDllDirs = @(Initialize-StrataModelDlls -Root $Root -Engine $Engine -LogDirectory $ServerLogDir)
foreach ($N in $Names) {
    $P = Join-Path $Models $N
    if (-not (Test-Path -LiteralPath $P)) {
        throw "Не найден Q4 shard: $P"
    }
    $SourceShards += Get-Item -LiteralPath $P
}

# Validate GGUF geometry and the provenance of the dedicated Huihui native pack
# before killing the current model or copying 46 GiB to R:.
$Checker = Join-Path $PSScriptRoot "PREPARE-HUIHUI-Q4.py"
if (-not (Test-Path -LiteralPath $Checker)) {
    throw "Отсутствует $Checker; скопируйте все файлы архива в E:\ai\Strata-Q4-Fork."
}
Write-Host "===== HUIHUI GGUF + NATIVE PACK CHECK ====="
& $Python $Checker --check-pack
if ($LASTEXITCODE -ne 0) {
    throw "Huihui GGUF/pack несовместим или не собран. Сначала запустите PREPARE-HUIHUI-Q4.cmd."
}
Write-Host "===== HUIHUI PACK VERIFIED ====="

# -ResumeRam must NOT fail merely because the last RAM setup was cleaned up by
# Q4/IQ3S or lost after a reboot. It now safely falls back to the ordinary
# staging path when the known Huihui staging directories/files are absent.
# A partially populated R: tree is removed/rebuilt ONLY by the normal branch.
Assert-StrataModelServerStopped -Port 8080
Assert-StrataModelEngineStopped -Root $Root
$ReuseStaging = [bool]$ResumeRam
if ($ReuseStaging) {
    $RequiredStaging = @($RamModel, $RamPack, $RamMtp, $RamProfile)
    foreach ($N in $Names) {
        $RequiredStaging += (Join-Path $RamModel $N)
    }
    $MissingStaging = @($RequiredStaging | Where-Object {
        -not (Test-Path -LiteralPath $_)
    })
    if ($MissingStaging.Count -gt 0) {
        Write-Host '===== NO COMPLETE RAM STAGING ====='
        Write-Host ('Missing: ' + ($MissingStaging -join ', '))
        Write-Host 'Automatic first-time RAM staging will now run.'
        Write-Host 'This MAY COPY the Huihui 46 GiB PLE from E: to R:.'
        $ReuseStaging = $false
    }
}

if (-not $ReuseStaging) {

Assert-StrataModelServerStopped -Port 8080
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
Write-Host "Huihui Q4 required = $([math]::Round($Need/1GB,2)) GiB incl. reserve"

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

    if ($i -eq 0) {
        # Shard1 has GGUF metadata and 0 tensors (~10 MB). A physical copy on R:
        # removes the cross-volume symlink from the engine's split-reader path.
        Write-Host "COPY shard1 (GGUF metadata, ~10 MB) -> RAM"
        Copy-Item -LiteralPath $Src -Destination $Dst -Force
        $SourceItem = Get-Item -LiteralPath $Src
        $DestItem = Get-Item -LiteralPath $Dst
        if (-not [string]::Equals($SourceItem.Name, $DestItem.Name, [StringComparison]::OrdinalIgnoreCase) -or
            [int64]$SourceItem.Length -ne [int64]$DestItem.Length) {
            throw 'Shard1 GGUF metadata name/size mismatch after copy.'
        }
    }
    elseif ($i -eq 1) {
        Write-Host "COPY shard2 (PLE) -> RAM"
        Copy-Item -LiteralPath $Src -Destination $Dst -Force

        if ((Get-Item -LiteralPath $Src).Length -ne (Get-Item -LiteralPath $Dst).Length) {
            throw "Размер shard2 после копирования не совпадает."
        }
        $SourceItem = Get-Item -LiteralPath $Src
        $DestItem = Get-Item -LiteralPath $Dst
        if (-not [string]::Equals($SourceItem.Name, $DestItem.Name, [StringComparison]::OrdinalIgnoreCase) -or
            [int64]$SourceItem.Length -ne [int64]$DestItem.Length) {
            throw 'Copied PLE does not match source Huihui GGUF by name/size.'
        }
        Write-Host "PLE name/size verified: $($DestItem.Name), $($DestItem.Length) bytes"
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


} else {
    # Diagnostic mode: do NOT kill other processes, remove RAM dirs or copy 46 GB again.
    # Validate all existing staging before using it; never silently mix two model variants.
    Write-Host '===== REUSE EXISTING HUIHUI RAM STAGING ====='
    if (-not (Test-Path 'R:\')) { throw 'R: is absent. Use the ordinary launcher first.' }
    $Listener = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue
    if ($Listener) { throw 'Port 8080 has a listener. Stop the existing server before changing RAM.' }
    $Vol = Get-Volume -DriveLetter R -ErrorAction Stop
    if ($Vol.FileSystem -ne 'NTFS') { throw 'R: is not NTFS.' }
    foreach ($P in @($RamModel,$RamPack,$RamMtp,$RamProfile)) {
        if (-not (Test-Path -LiteralPath $P)) { throw "Missing RAM staging: $P" }
    }
    foreach ($N in $Names) {
        $P = Join-Path $RamModel $N
        if (-not (Test-Path -LiteralPath $P -PathType Leaf)) { throw "Missing staged GGUF: $P" }
    }
    # Shard 2 is physical on R:, not a symlink to E:.
    $P2 = Join-Path $RamModel $Names[1]
    $I2 = Get-Item -LiteralPath $P2 -Force
    if ($I2.LinkType) { throw "Shard2 on R: is a link, not physical PLE: $P2" }
    if ($I2.Length -ne $SourceShards[1].Length) { throw 'Staged PLE size differs from Huihui source.' }

    # The previous launcher gave the first shard a symbolic link. Check it points to Huihui,
    # then replace ONLY this tiny ~10 MB metadata shard with an actual file on R:.
    $P1 = Join-Path $RamModel $Names[0]
    $I1 = Get-Item -LiteralPath $P1 -Force
    if ($I1.LinkType) {
        $TargetText = @($I1.Target) -join ' '
        if (-not $TargetText.Contains($SourceShards[0].FullName)) {
            throw "Shard1 symlink does not point to the Huihui source: $TargetText"
        }
        Write-Host "Replacing only 10 MB shard1 symlink with a PHYSICAL GGUF: $P1"
        Remove-Item -LiteralPath $P1 -Force
        Copy-Item -LiteralPath $SourceShards[0].FullName -Destination $P1 -Force
    }
    $MetaE = Get-Item -LiteralPath $SourceShards[0].FullName
    $MetaR = Get-Item -LiteralPath $P1
    if (-not [string]::Equals($MetaE.Name, $MetaR.Name, [StringComparison]::OrdinalIgnoreCase) -or
        [int64]$MetaE.Length -ne [int64]$MetaR.Length) {
        throw 'Metadata shard name/size mismatch between E: and R:.'
    }
    Write-Host "Metadata shard name/size matches Huihui source: $($MetaR.Name), $($MetaR.Length) bytes"

    # PowerShell variables are CASE-INSENSITIVE: $i and $I are the SAME variable.
    # Keep the numeric index and the FileInfo object in distinct, descriptive variables.
    foreach ($ShardIndex in @(2, 3)) {
        $LinkPath = Join-Path $RamModel $Names[$ShardIndex]
        $ShardLink = Get-Item -LiteralPath $LinkPath -Force
        $ExpectedTarget = [string]($SourceShards[$ShardIndex].FullName)
        $LinkTargets = @($ShardLink.Target)
        $LinkIsCorrect = $false

        if ($ShardLink.LinkType -eq 'SymbolicLink') {
            foreach ($CandidateTarget in $LinkTargets) {
                if ([string]::Equals(
                        [string]$CandidateTarget,
                        $ExpectedTarget,
                        [System.StringComparison]::OrdinalIgnoreCase
                )) {
                    $LinkIsCorrect = $true
                    break
                }
            }
        }

        if (-not $LinkIsCorrect) {
            $TargetDescription = $LinkTargets -join ', '
            throw "Shard $($ShardIndex + 1) must be a Huihui symbolic link: $LinkPath -> $TargetDescription; expected $ExpectedTarget"
        }
        Write-Host "Huihui shard $($ShardIndex + 1) symlink verified."
    }
    $PleE = Get-Item -LiteralPath $SourceShards[1].FullName
    $PleR = Get-Item -LiteralPath $P2
    if (-not [string]::Equals($PleE.Name, $PleR.Name, [StringComparison]::OrdinalIgnoreCase) -or
        [int64]$PleE.Length -ne [int64]$PleR.Length) {
        throw 'Staged PLE does not match Huihui source by name/size. Use normal launcher to replace it.'
    }
    Write-Host "PLE name/size matches Huihui source: $($PleR.Name), $($PleR.Length) bytes"

    $IndexESrc = Get-Item -LiteralPath (Join-Path $PackSrc 'index.txt')
    $IndexRDest = Get-Item -LiteralPath (Join-Path $RamPack 'index.txt')
    if (-not [string]::Equals($IndexESrc.Name, $IndexRDest.Name, [StringComparison]::OrdinalIgnoreCase) -or
        [int64]$IndexESrc.Length -ne [int64]$IndexRDest.Length) {
        throw 'RAM native pack index does not match Huihui pack by name/size.'
    }
    Write-Host 'RAM pack index matches Huihui source.'

}

$NativeFirst = if ($UseSourceNative) { $SourceShards[0].FullName } else { Join-Path $RamModel $Names[0] }
Write-Host "Native first shard: $NativeFirst"
Write-Host "Source mode: $(if ($UseSourceNative) {'E: DIRECT (diagnostic: PLE may be read from SSD)'} else {'R: PHYSICAL GGUF HEADER'})"

$EngineArgs = [System.Collections.Generic.List[string]]::new()

@(
    "--pack", $RamPack,
    "--native", $NativeFirst,
    "--expert-profile", $RamProfile,
    "--expert-cache", "auto",
    "--prefill", "auto"
) | ForEach-Object { $EngineArgs.Add([string]$_) }

if ($ExplicitNativeDense) {
    # Optional controlled A/B diagnostic. Not enabled by default: installed engine
    # builds may not support this flag. Check --help before changing the generated config.
    $HelpOutput = (& $Engine --help 2>&1 | Out-String)
    if ($HelpOutput -notmatch '--native-dense-gguf') {
        throw 'This strata.exe does not advertise --native-dense-gguf; unchanged. Do NOT force the flag.'
    }
    Write-Host "Explicit native dense GGUF: $NativeFirst"
    $EngineArgs.Add('--native-dense-gguf')
    $EngineArgs.Add($NativeFirst)
}

if ($NoPrefillBorrow) {
    $EngineArgs.Add("--no-prefill-borrow")
}

@(
    "--spec", "4",
    "--spec-min-p", "0.9",
    "--suffix-draft", "0",
    "--mtp", $RamMtp,
    "--max-context", "262144",
    "--kv", "int8",
    "--kv-resident", "32768",
    "--resident-budget-gib", "80",
    "--pcie-frac", "0.26",
    "--adapt-every", "0",
    "--adapt-swaps", "0",
    "--prompt-cache", "0"
) | ForEach-Object { $EngineArgs.Add([string]$_) }

# Настройки выборки токенов относятся к серверу, а не к аргументам strata.exe.
# Значения ниже применяются, если в сохранённом JSON параметры ещё не заданы.
# Явные значения пользователя имеют приоритет, включая 0 у repeat_stop_tokens.
$SamplingDefaults = [ordered]@{
    temperature = 1.0
    top_p = 0.95
    top_k = 20
    min_p = 0.0
    repetition_penalty = 1.05
    penalty_last_n = 256
    frequency_penalty = 0.0
    presence_penalty = 0.0
}

$Config = [ordered]@{
    exe = $Engine
    args = @($EngineArgs)
    cwd = $Root
    tokenizer = "$RamPack\tokenizer"
    model_name = "huihui-qwen3.8-flash-next-abliterated-ud-q4_k_xl"
    reasoning_budget_tokens = 10240
    log = $Log
    lib_dirs = @($RuntimeDllDirs)
    autotune = $true
    host = "0.0.0.0"
    port = 8080
    gpu = 0
    gpus_asked = $true
    repeat_stop_tokens = 64
    sampling = $SamplingDefaults
}

# User configuration stays byte-for-byte unchanged. Only the transient
# server copy gets paths to the freshly staged runtime on R:.
$RuntimeConfig = New-StrataModelRuntimeConfig -RootConfig $Cfg `
    -PersonalConfig (Join-Path $Root 'PERSONAL_START_E_ai_Strata-Q4-Fork\strata-huihui-ud-q4_k_xl-RAM.json') `
    -Defaults $Config -RuntimeFlags @{
        '--pack'=$RamPack
        '--native'=$NativeFirst
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
Write-Host "API:    http://127.0.0.1:8080/v1 (bind 0.0.0.0)"
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
if ($ReuseStaging) {
    $Listener = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue
    if ($Listener) { throw 'Port 8080 has a listener. Stop the existing server before diagnostics.' }
}


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
    Write-Host "HUIHUI Q4_K_XL READY"
    Write-Host "http://127.0.0.1:8080/v1"
    Write-Host "========================================"
    Write-Host ""
    $ModelsResponse | ConvertTo-Json -Depth 10
}
else {
    Write-Host "HUIHUI Q4_K_XL NOT READY"
    Write-Host "========================================"
    if (Test-Path -LiteralPath $Log) {
        Write-Host ""
        Get-Content -LiteralPath $Log -Tail 150
    }
    exit 1
}

Write-Host ""
Write-Host "R: free = $([math]::Round((Get-PSDrive R).Free/1GB,2)) GiB"
