#requires -Version 7.0
[CmdletBinding()]
param([switch]$SkipGpuTests)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = 'E:\ai\Strata-Q4-Fork'
$Build = Join-Path $Root 'build-q6k-ninja-release'
$EngineDir = Join-Path $Root 'engine-q6'
$EngineTarget = Join-Path $EngineDir 'strata.exe'
$LogDir = Join-Path $Root 'logs\q6'
$Log = Join-Path $LogDir 'Q6_BUILD_LAST.txt'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path $Log -Force | Out-Null
try {
    Write-Host '=== STRATA Q6_K ENGINE BUILD ===' -ForegroundColor Cyan
    foreach ($Name in @('cmake.exe','ctest.exe','nvcc.exe','nvidia-smi.exe')) {
        if (-not (Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue)) {
            throw "Не найдена команда: $Name"
        }
    }
    $Cap = (& nvidia-smi.exe --query-gpu=compute_cap --format=csv,noheader,nounits | Select-Object -First 1).Trim()
    if ($Cap -notmatch '^\d+\.\d+$') { throw "Не удалось определить compute capability: $Cap" }
    $CudaArch = $Cap.Replace('.','')
    Write-Host "GPU architecture: sm_$CudaArch"

    $VsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path -LiteralPath $VsWhere -PathType Leaf)) { throw "Не найден vswhere.exe: $VsWhere" }
    $VsRoot = (& $VsWhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
    if (-not $VsRoot) { throw 'MSVC Build Tools x64 не найдены.' }
    $DevCmd = Join-Path $VsRoot 'Common7\Tools\VsDevCmd.bat'
    if (-not (Test-Path -LiteralPath $DevCmd -PathType Leaf)) { throw "Не найден $DevCmd" }
    $Bridge = Join-Path $Root '_strata_q6_msvc_environment.cmd'
    try {
        [IO.File]::WriteAllLines($Bridge, @('@echo off', ('call "' + $DevCmd + '" -arch=amd64 -host_arch=amd64 1>nul'), 'if errorlevel 1 exit /b 1', 'set'), [Text.Encoding]::ASCII)
        $EnvLines = & $env:ComSpec /d /c $Bridge
        $BridgeExit = $LASTEXITCODE
    } finally { Remove-Item -LiteralPath $Bridge -Force -ErrorAction SilentlyContinue }
    if ($BridgeExit -ne 0) { throw 'Не удалось активировать MSVC.' }
    foreach ($Line in $EnvLines) {
        if ($Line -match '^([^=][^=]*)=(.*)$') { [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process') }
    }
    if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) { throw 'cl.exe не найден после VsDevCmd.' }

    $Ninja = Get-Command ninja.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $Ninja) {
        foreach ($Candidate in @((Join-Path $Root '.venv\Scripts\ninja.exe'),'C:\Users\Keter\AppData\Local\Programs\Python\Python312\Scripts\ninja.exe')) {
            if (Test-Path -LiteralPath $Candidate -PathType Leaf) { $Ninja=[pscustomobject]@{Source=$Candidate}; break }
        }
    }
    if (-not $Ninja) { throw 'ninja.exe не найден. Установите Ninja либо используйте тот же Ninja, которым собирался основной движок.' }
    $Nvcc = (Get-Command nvcc.exe -CommandType Application | Select-Object -First 1).Source
    $CudaRoot = Split-Path -Parent (Split-Path -Parent $Nvcc)
    $env:CUDA_PATH = $CudaRoot

    Write-Host '=== CMAKE Q6_K: Q6 experts + K-quant prompt MMQ ===' -ForegroundColor Cyan
    & cmake.exe -S $Root -B $Build -G Ninja `
        "-DCMAKE_MAKE_PROGRAM=$($Ninja.Source)" `
        '-DCMAKE_BUILD_TYPE=Release' `
        '-DCMAKE_C_COMPILER=cl.exe' `
        '-DCMAKE_CXX_COMPILER=cl.exe' `
        "-DCMAKE_CUDA_COMPILER=$Nvcc" `
        "-DCUDAToolkit_ROOT=$CudaRoot" `
        '-DSTRATA_ENABLE_CUDA=ON' `
        "-DCMAKE_CUDA_ARCHITECTURES=$CudaArch" `
        '-DSTRATA_MMQ_KQUANTS=ON' `
        '-DSTRATA_Q6K_EXPERTS=ON' `
        '-DSTRATA_BUILD_TESTS=ON'
    if ($LASTEXITCODE -ne 0) { throw 'CMake конфигурация Q6_K завершилась ошибкой.' }

    $Targets = @('strata','prefill_mmq_kquant_test','native_grouped_parity','native_expert_parity','ple_reader_test','ple_q8_row_test')
    foreach ($Target in $Targets) {
        Write-Host ("Сборка Q6 target: {0}" -f $Target) -ForegroundColor DarkCyan
        & cmake.exe --build $Build --target $Target --parallel 8
        if ($LASTEXITCODE -ne 0) { throw ("Компиляция Q6_K target {0} завершилась ошибкой." -f $Target) }
    }

    if (-not $SkipGpuTests) {
        Write-Host '=== Q6_K CUDA TESTS ===' -ForegroundColor Cyan
        & ctest.exe --test-dir $Build -R '^(prefill_mmq_kquant_test|native_grouped_parity|native_expert_parity_q6_K_q8_0|ple_reader_selftest|ple_q8_row_test)$' --output-on-failure
        if ($LASTEXITCODE -ne 0) { throw 'Q6_K CUDA/PLE тесты не прошли; engine-q6 не обновлён.' }
    } else {
        Write-Warning 'GPU tests skipped by explicit -SkipGpuTests; engine will still be installed as unverified.'
    }

    $Binary = Join-Path $Build 'strata.exe'
    if (-not (Test-Path -LiteralPath $Binary -PathType Leaf)) {
        $Found = @(Get-ChildItem -LiteralPath $Build -Filter 'strata.exe' -Recurse -File)
        if ($Found.Count -ne 1) { throw "Не удалось однозначно найти strata.exe после Q6-сборки: $($Found.Count)" }
        $Binary = $Found[0].FullName
    }
    New-Item -ItemType Directory -Path $EngineDir -Force | Out-Null
    if (Test-Path -LiteralPath $EngineTarget -PathType Leaf) {
        $Old = Get-Item -LiteralPath $EngineTarget
        $BackupDir = Join-Path $EngineDir 'backups'
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
        $Backup = Join-Path $BackupDir ('strata-q6-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.exe')
        Copy-Item -LiteralPath $Old.FullName -Destination $Backup -ErrorAction Stop
        Write-Host "Предыдущий Q6 engine сохранён: $Backup"
    }
    Copy-Item -LiteralPath $Binary -Destination $EngineTarget -Force -ErrorAction Stop
    $Built = Get-Item -LiteralPath $EngineTarget
    Write-Host ("Q6 engine installed: {0} ({1} bytes)" -f $Built.FullName, $Built.Length) -ForegroundColor Green

    . (Join-Path $Root 'STRATA-WINDOWS-RUNTIME.ps1')
    Initialize-StrataWindowsRuntime -Engine $EngineTarget -Root $Root -LogDir $LogDir -RepairMissingCublas
    & $EngineTarget --help *> $null
    if ($LASTEXITCODE -ne 0) { throw "Новый Q6 strata.exe не проходит --help: code $LASTEXITCODE" }
    Write-Host 'Q6_K engine build completed.' -ForegroundColor Green
}
finally { Stop-Transcript | Out-Null }
