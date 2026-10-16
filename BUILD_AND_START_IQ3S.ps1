#requires -version 5.1
[CmdletBinding()]
param([switch]$BuildOnly, [switch]$Foreground, [switch]$ParityTest)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Root = 'E:\ai\Strata-Q4-Fork'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not [string]::Equals([IO.Path]::GetFullPath($Here).TrimEnd('\'), [IO.Path]::GetFullPath($Root).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
    throw "Распакуйте содержимое архива непосредственно в $Root. Сейчас: $Here"
}
$Transcript = Join-Path $Root 'BUILD_AND_START_IQ3S.log'
Start-Transcript -Path $Transcript -Append | Out-Null
try {
    Write-Host '=== ПРОВЕРКА СРЕДЫ ==='
    foreach ($name in @('cmake.exe','nvidia-smi.exe','nvcc.exe')) {
        if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "Не найдена команда $name" }
    }
    & nvcc.exe --version
    $architecture = (& nvidia-smi.exe --query-gpu=compute_cap --format=csv,noheader,nounits | Select-Object -First 1).Trim()
    if ($architecture -notmatch '^\d+\.\d+$') { throw "Неизвестная архитектура GPU: $architecture" }
    $cudaArch = $architecture.Replace('.','')
    Write-Host "CUDA архитектура: sm_$cudaArch"
    $python = Join-Path $Root '.venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $python)) {
        $pythonCommand = Get-Command python.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $pythonCommand) { throw 'Python не найден в PATH' }
        $python = $pythonCommand.Source
    }
    & $python -c 'import sys; assert sys.version_info >= (3,10); print(sys.version)'
    if ($LASTEXITCODE -ne 0) { throw 'Нужен Python 3.10+' }

    Write-Host '=== ИНИЦИАЛИЗАЦИЯ MSVC (без интеграции CUDA в Visual Studio) ==='
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path -LiteralPath $vswhere)) { throw "Не найден vswhere.exe: $vswhere" }
    $vsRoot = (& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
    if (-not $vsRoot) { throw 'Не установлены средства компиляции MSVC x64' }
    $devCmd = Join-Path $vsRoot 'Common7\Tools\VsDevCmd.bat'
    if (-not (Test-Path -LiteralPath $devCmd)) { throw "Отсутствует $devCmd" }
    # Вложенные кавычки через cmd /s /c ломают пути в C:\Program Files.
    # Вызываем отдельный bat из корня проекта (путь без пробелов), а не VsDevCmd напрямую.
    $bridge = Join-Path $Root '_strata_msvc_environment.cmd'
    $bridgeLines = @(
        '@echo off'
        ('call "' + $devCmd + '" -arch=amd64 -host_arch=amd64 1>nul')
        'if errorlevel 1 exit /b 1'
        'set'
    )
    try {
        [IO.File]::WriteAllLines($bridge, $bridgeLines, [Text.Encoding]::ASCII)
        $envLines = & $env:ComSpec /d /c $bridge
        $bridgeExit = $LASTEXITCODE
    }
    finally {
        Remove-Item -LiteralPath $bridge -Force -ErrorAction SilentlyContinue
    }
    if ($bridgeExit -ne 0) { throw 'Не удалось активировать среду Visual Studio; проверьте установленный MSVC и Windows SDK' }
    foreach ($line in $envLines) {
        if ($line -match '^([^=][^=]*)=(.*)$') {
            [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
        }
    }
    if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) { throw 'MSVC cl.exe не найден после VsDevCmd' }

    $ninja = Get-Command ninja.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $ninja) {
        # И для системного Python, и для .venv python.exe лежит рядом с ninja.exe
        # (в .venv оба находятся в каталоге Scripts).
        $pythonScripts = Join-Path (Split-Path -Parent $python) 'ninja.exe'
        if (-not (Test-Path -LiteralPath $pythonScripts)) {
            Write-Host 'Ninja отсутствует: устанавливаю через Python pip...'
            & $python -m pip install ninja
            if ($LASTEXITCODE -ne 0) { throw 'Не удалось установить Ninja' }
        }
        $ninjaPath = $pythonScripts
    } else { $ninjaPath = $ninja.Source }
    if (-not (Test-Path -LiteralPath $ninjaPath)) { throw "Не найден Ninja: $ninjaPath" }
    & $ninjaPath --version
    if ($LASTEXITCODE -ne 0) { throw 'Не запускается Ninja' }

    $nvccCommand = Get-Command nvcc.exe -CommandType Application | Select-Object -First 1
    $cudaRoot = Split-Path -Parent (Split-Path -Parent $nvccCommand.Source)
    if (-not (Test-Path -LiteralPath (Join-Path $cudaRoot 'include\cuda.h'))) { throw "Не найдены заголовки CUDA в $cudaRoot" }
    $env:CUDA_PATH = $cudaRoot
    Write-Host "CUDA Toolkit: $cudaRoot"
    Write-Host '=== НАСТРОЙКА CMAKE / NINJA ==='
    # У Ninja и генератора Visual Studio разные внутренние структуры CMake: отдельный каталог обязателен.
    $build = Join-Path $Root 'build-iq3s-ninja-release'
    $buildTests = if ($ParityTest) { 'ON' } else { 'OFF' }
    & cmake.exe -S $Root -B $build -G Ninja `
        "-DCMAKE_MAKE_PROGRAM=$ninjaPath" `
        '-DCMAKE_BUILD_TYPE=Release' `
        '-DCMAKE_C_COMPILER=cl.exe' `
        '-DCMAKE_CXX_COMPILER=cl.exe' `
        "-DCMAKE_CUDA_COMPILER=$(Join-Path $cudaRoot 'bin\nvcc.exe')" `
        "-DCUDAToolkit_ROOT=$cudaRoot" `
        '-DSTRATA_ENABLE_CUDA=ON' `
        "-DCMAKE_CUDA_ARCHITECTURES=$cudaArch" `
        "-DSTRATA_BUILD_TESTS=$buildTests"
    if ($LASTEXITCODE -ne 0) { throw 'Настройка CMake/Ninja завершилась ошибкой' }
    Write-Host '=== СБОРКА ДВИЖКА ==='
    & cmake.exe --build $build --target strata --parallel 8
    if ($LASTEXITCODE -ne 0) { throw 'Компиляция Strata завершилась ошибкой' }
    if ($ParityTest) {
        Write-Host '=== ПРЯМАЯ ПРОВЕРКА CPU <-> CUDA Q8_0 EXPERT PARITY ==='
        & cmake.exe --build $build --target native_expert_parity --parallel 8
        if ($LASTEXITCODE -ne 0) { throw 'Не удалось собрать native_expert_parity' }
        $ParityExe = Join-Path $build 'native_expert_parity.exe'
        if (-not (Test-Path -LiteralPath $ParityExe -PathType Leaf)) {
            $ParityMatches = @(Get-ChildItem $build -Filter native_expert_parity.exe -Recurse -File)
            if ($ParityMatches.Count -ne 1) { throw "Не удалось однозначно найти native_expert_parity.exe: $($ParityMatches.Count)" }
            $ParityExe = $ParityMatches[0].FullName
        }
        & $ParityExe --cuda-placement-parity-q8
        if ($LASTEXITCODE -ne 0) {
            throw 'CPU/CUDA Q8_0 parity не доказан: новый strata.exe НЕ устанавливается в engine.'
        }
        Write-Host '[OK] CPU/CUDA Q8_0 expert output совпал побитово на синтетическом тесте.' -ForegroundColor Green
    }
    $binary = Join-Path $build 'strata.exe'
    if (-not (Test-Path -LiteralPath $binary)) {
        $matchesFound = @(Get-ChildItem $build -Filter strata.exe -Recurse -File)
        if ($matchesFound.Count -ne 1) { throw "Не удалось однозначно найти strata.exe: $($matchesFound.Count)" }
        $binary = $matchesFound[0].FullName
    }
    $engine = Join-Path $Root 'engine'
    New-Item -ItemType Directory -Path $engine -Force | Out-Null
    # Сохраняем именно рабочий ранее исполняемый файл перед изменением.
    # Если новая CUDA-сборка потребует доработки, пользователь сможет вернуть
    # последнюю проверенную версию, не компилируя её повторно.
    $engineTarget = Join-Path $engine 'strata.exe'
    if (Test-Path -LiteralPath $engineTarget -PathType Leaf) {
        $backupDir = Join-Path $engine 'backups'
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        $backup = Join-Path $backupDir ('strata-before-038-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.exe')
        Copy-Item -LiteralPath $engineTarget -Destination $backup -ErrorAction Stop
        Write-Host "Резервная копия рабочего strata.exe: $backup"
    }
    Copy-Item -LiteralPath $binary -Destination $engineTarget -Force
    Write-Host "Движок готов: $engine\strata.exe"
    # Собранный exe может ссылаться на CUDA/MSVC DLL, которых нет в PATH
    # обычного PowerShell. Проверяем его загрузку без открытия GGUF.
    $runtimeHelper = Join-Path $Root 'STRATA-WINDOWS-RUNTIME.ps1'
    if (-not (Test-Path -LiteralPath $runtimeHelper -PathType Leaf)) {
        throw "Не найден сценарий проверки DLL: $runtimeHelper"
    }
    . $runtimeHelper
    Initialize-StrataWindowsRuntime -Engine (Join-Path $engine 'strata.exe') -Root $Root -LogDir (Join-Path $Root 'logs\iq3s') -RepairMissingCublas
    if ($BuildOnly) { Write-Host 'Сборка закончена; запуск пропущен'; return }
    $profiles = Join-Path $Root 'PERSONAL_START_E_ai_Strata-Q4-Fork'
    foreach ($file in @('START-IQ3S-RAM.ps1','START-HERE IQ3_S.bat','CHECK-IQ3S-RCO.ps1','strata-iq3_s-RAM.json','strata-iq3_s.json')) {
        $source = Join-Path $profiles $file
        if (-not (Test-Path -LiteralPath $source)) { throw "Отсутствует профиль: $source" }
        Copy-Item -LiteralPath $source -Destination (Join-Path $Root $file) -Force
    }
    Write-Host '=== ИЗОЛИРОВАННАЯ СРЕДА PYTHON ==='
    # Не изменяем системный Python: предыдущий запуск заменил NumPy в общей
    # установке и привёл к несовместимости с другим приложением.
    $venv = Join-Path $Root '.venv'
    $venvPython = Join-Path $venv 'Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $venvPython -PathType Leaf)) {
        Write-Host "Создаю локальное окружение: $venv"
        & $python -m venv $venv
        if ($LASTEXITCODE -ne 0) { throw "Не удалось создать Python окружение: $venv" }
    }
    & $venvPython -c 'import sys; assert sys.prefix != sys.base_prefix; assert sys.version_info >= (3,10); print(sys.executable)'
    if ($LASTEXITCODE -ne 0) { throw 'Локальное окружение Python повреждено или не поддерживается' }
    Write-Host '=== УСТАНОВКА ЗАВИСИМОСТЕЙ В .venv ==='
    & $venvPython -m pip install --disable-pip-version-check --retries 3 --timeout 60 -r (Join-Path $Root 'requirements.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Не удалось установить зависимости Python в .venv' }
    Write-Host '=== ЗАПУСК IQ3_S ==='
    $launch = Join-Path $Root 'START-IQ3S-RAM.ps1'
    if ($Foreground) { & $launch -Foreground } else { & $launch }
    if (-not $?) {
        Write-Host "При неудаче запуска изучите отдельные журналы сервера в $Root\logs\iq3s"
        throw 'Запускающий сценарий завершился с ошибкой'
    }
}
catch {
    Write-Host "ОШИБКА: $($_.Exception.Message)" -ForegroundColor Red
    throw
}
finally { Stop-Transcript | Out-Null }
