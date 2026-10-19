#requires -Version 7.0
[CmdletBinding()]
param([switch]$Clean)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$Root='E:\ai\Strata-Q4-Fork'
$Src=Join-Path $Root 'vendor\strata-q36-0.1.45'
$Build=Join-Path $Root 'build-q36-sm86'
$EngineDir=Join-Path $Root 'engine-q36'
$EngineTarget=Join-Path $EngineDir 'strata-q36.exe'
$LogDir=Join-Path $Root 'logs\q36'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path (Join-Path $LogDir 'Q36_BUILD_LAST.txt') -Force | Out-Null
try {
    foreach($Name in @('cmake.exe','nvcc.exe','nvidia-smi.exe')){
        if(-not (Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue)){ throw "Не найдена команда: $Name" }
    }
    $Cap=(& nvidia-smi.exe --query-gpu=compute_cap --format=csv,noheader,nounits | Select-Object -First 1).Trim()
    if($Cap -notmatch '^\d+\.\d+$'){ throw "Не удалось определить compute capability: $Cap" }
    $CudaArch=$Cap.Replace('.','')
    $VsWhere="${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if(-not (Test-Path -LiteralPath $VsWhere)){ throw "Не найден vswhere.exe: $VsWhere" }
    $VsRoot=(& $VsWhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
    if(-not $VsRoot){ throw 'MSVC Build Tools x64 не найдены.' }
    $DevCmd=Join-Path $VsRoot 'Common7\Tools\VsDevCmd.bat'
    $Bridge=Join-Path $Root '_strata_q36_msvc_environment.cmd'
    try {
        [IO.File]::WriteAllLines($Bridge,@('@echo off',('call "'+$DevCmd+'" -arch=amd64 -host_arch=amd64 1>nul'),'if errorlevel 1 exit /b 1','set'),[Text.Encoding]::ASCII)
        $EnvLines=& $env:ComSpec /d /c $Bridge; $BridgeExit=$LASTEXITCODE
    } finally { Remove-Item -LiteralPath $Bridge -Force -ErrorAction SilentlyContinue }
    if($BridgeExit -ne 0){ throw 'Не удалось активировать MSVC.' }
    foreach($Line in $EnvLines){ if($Line -match '^([^=][^=]*)=(.*)$'){ [Environment]::SetEnvironmentVariable($Matches[1],$Matches[2],'Process') } }
    if(-not (Get-Command cl.exe -ErrorAction SilentlyContinue)){ throw 'cl.exe не найден после VsDevCmd.' }
    $Ninja=Get-Command ninja.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if(-not $Ninja){ foreach($Candidate in @((Join-Path $Root '.venv\Scripts\ninja.exe'),'C:\Users\Keter\AppData\Local\Programs\Python\Python312\Scripts\ninja.exe')){ if(Test-Path -LiteralPath $Candidate){$Ninja=[pscustomobject]@{Source=$Candidate};break} } }
    if(-not $Ninja){ throw 'ninja.exe не найден.' }
    $Nvcc=(Get-Command nvcc.exe -CommandType Application | Select-Object -First 1).Source
    $CudaRoot=Split-Path -Parent (Split-Path -Parent $Nvcc); $env:CUDA_PATH=$CudaRoot
    if($Clean -and (Test-Path -LiteralPath $Build)){ Remove-Item -LiteralPath $Build -Recurse -Force }
    Write-Host "=== QWEN3.6-35B-A3B ENGINE / sm_$CudaArch ===" -ForegroundColor Cyan
    & cmake.exe -S $Src -B $Build -G Ninja `
        "-DCMAKE_MAKE_PROGRAM=$($Ninja.Source)" '-DCMAKE_BUILD_TYPE=Release' '-DCMAKE_C_COMPILER=cl.exe' '-DCMAKE_CXX_COMPILER=cl.exe' `
        "-DCMAKE_CUDA_COMPILER=$Nvcc" "-DCUDAToolkit_ROOT=$CudaRoot" '-DSTRATA_ENABLE_CUDA=ON' "-DCMAKE_CUDA_ARCHITECTURES=$CudaArch" `
        '-DSTRATA_MMQ_KQUANTS=ON' '-DSTRATA_Q6K_EXPERTS=ON' '-DSTRATA_BUILD_TESTS=OFF'
    if($LASTEXITCODE -ne 0){ throw 'Q36 CMake configure failed.' }
    & cmake.exe --build $Build --target strata-q36 --parallel 18
    if($LASTEXITCODE -ne 0){ throw 'Q36 compilation failed.' }
    $Binary=Join-Path $Build 'strata-q36.exe'
    if(-not (Test-Path -LiteralPath $Binary)){ $Found=@(Get-ChildItem -LiteralPath $Build -Filter 'strata-q36.exe' -Recurse -File); if($Found.Count -ne 1){throw "Не найден strata-q36.exe: $($Found.Count)"}; $Binary=$Found[0].FullName }
    New-Item -ItemType Directory -Path $EngineDir -Force | Out-Null
    if(Test-Path -LiteralPath $EngineTarget){ $BackupDir=Join-Path $EngineDir 'backups'; New-Item -ItemType Directory -Path $BackupDir -Force|Out-Null; Copy-Item $EngineTarget (Join-Path $BackupDir ('strata-q36-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'.exe')) }
    Copy-Item -LiteralPath $Binary -Destination $EngineTarget -Force
    . (Join-Path $Root 'STRATA-WINDOWS-RUNTIME.ps1')
    Initialize-StrataWindowsRuntime -Engine $EngineTarget -Root $Root -LogDir $LogDir -RepairMissingCublas
    & $EngineTarget --help *> $null
    if($LASTEXITCODE -ne 0){ throw "strata-q36.exe --help failed: $LASTEXITCODE" }
    Write-Host "Q36 engine installed: $EngineTarget" -ForegroundColor Green
} finally { Stop-Transcript | Out-Null }
