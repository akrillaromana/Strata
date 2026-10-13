# Strata Fork — поиск DLL при запуске локально собранного CUDA-движка.
# PowerShell 7; не требует переустановки CUDA/MSVC и не копирует DLL.
# Функции вызываются из START-IQ3S-RAM.ps1 и GET-IQ3S-DIAGNOSTICS.ps1.

function Find-StrataRuntimeDirectory {
    param([string]$Directory, [System.Collections.Generic.List[string]]$Directories)
    if ([string]::IsNullOrWhiteSpace($Directory)) { return }
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { return }
    $Full = [IO.Path]::GetFullPath($Directory).TrimEnd('\')
    foreach ($Known in $Directories) {
        if ([string]::Equals($Known, $Full, [StringComparison]::OrdinalIgnoreCase)) { return }
    }
    $Directories.Add($Full)
}

function Get-StrataRuntimeDirectories {
    param([Parameter(Mandatory)][string]$Engine, [Parameter(Mandatory)][string]$Root)
    $Directories = [System.Collections.Generic.List[string]]::new()
    Find-StrataRuntimeDirectory -Directory (Split-Path -Parent $Engine) -Directories $Directories

    # NVIDIA publishes the CUDA 13.3 cuBLAS binary also as an official Python
    # wheel. If a wheel was installed for this fork, keep its DLLs completely
    # separate from system Python and CUDA. Prefer this pinned runtime to an
    # unrelated, potentially newer cuBLAS on the global PATH.
    $LocalBlas = Join-Path $Root '.strata-runtime\cublas-13.3.0.5'
    foreach ($Folder in @(
        (Join-Path $LocalBlas 'nvidia\cu13\bin'),
        (Join-Path $LocalBlas 'nvidia\cublas\bin')
    )) {
        if (Test-Path -LiteralPath (Join-Path $Folder 'cublas64_13.dll') -PathType Leaf) {
            Find-StrataRuntimeDirectory -Directory $Folder -Directories $Directories
        }
    }

    # Статическая линковка ggml включена в CMake, однако другие модули
    # могут создавать свои DLL. Подхватываем только каталог сборки этого форка.
    $Build = Join-Path $Root 'build-iq3s-ninja-release'
    foreach ($Folder in @($Build, (Join-Path $Build 'bin'), (Join-Path $Root 'bin'))) {
        if (Test-Path -LiteralPath $Folder -PathType Container) {
            if (@(Get-ChildItem -LiteralPath $Folder -Filter '*.dll' -File -ErrorAction SilentlyContinue).Count -gt 0) {
                Find-StrataRuntimeDirectory -Directory $Folder -Directories $Directories
            }
        }
    }

    # Первым используем ТОТ CUDA Toolkit, с которым собирался exe:
    # CMakeCache хранит путь, в отличие от текущего PATH пользователя.
    $Toolkits = [System.Collections.Generic.List[string]]::new()
    $Cache = Join-Path $Build 'CMakeCache.txt'
    if (Test-Path -LiteralPath $Cache -PathType Leaf) {
        foreach ($Line in (Get-Content -LiteralPath $Cache -ErrorAction Stop)) {
            if ($Line -match '^CUDAToolkit_ROOT:[^=]*=(.+)$') {
                Find-StrataRuntimeDirectory -Directory $Matches[1].Trim() -Directories $Toolkits
            }
            elseif ($Line -match '^CMAKE_CUDA_COMPILER:[^=]*=(.+)$') {
                $CompilerPath = $Matches[1].Trim()
                if (Test-Path -LiteralPath $CompilerPath -PathType Leaf) {
                    $ToolkitRoot = Split-Path -Parent (Split-Path -Parent $CompilerPath)
                    Find-StrataRuntimeDirectory -Directory $ToolkitRoot -Directories $Toolkits
                }
            }
        }
    }
    if ($env:CUDA_PATH) {
        Find-StrataRuntimeDirectory -Directory $env:CUDA_PATH -Directories $Toolkits
    }
    $Nvcc = Get-Command -Name 'nvcc.exe' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -ne $Nvcc -and (Test-Path -LiteralPath $Nvcc.Source -PathType Leaf)) {
        $NvccRoot = Split-Path -Parent (Split-Path -Parent $Nvcc.Source)
        Find-StrataRuntimeDirectory -Directory $NvccRoot -Directories $Toolkits
    }
    foreach ($Toolkit in $Toolkits) {
        Find-StrataRuntimeDirectory -Directory (Join-Path $Toolkit 'bin') -Directories $Directories
        Find-StrataRuntimeDirectory -Directory (Join-Path $Toolkit 'bin\x64') -Directories $Directories
        Find-StrataRuntimeDirectory -Directory (Join-Path $Toolkit 'cublas\bin') -Directories $Directories
        # CUDA installers can place optional components in nested directories.
        # Restrict this fallback scan to known CUDA toolkits, not whole drives.
        $OtherBlasDlls = @(Get-ChildItem -LiteralPath $Toolkit -Filter 'cublas64_13.dll' `
            -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 5)
        foreach ($BlasDll in $OtherBlasDlls) {
            Find-StrataRuntimeDirectory -Directory $BlasDll.DirectoryName -Directories $Directories
        }
    }

    # Some installed NVIDIA wheels use nvidia/cu13/bin while older wheel
    # layouts use nvidia/cublas/bin. Search only known Python installations,
    # never recursively walk unrelated user drives or the model repository.
    $PythonExe = Get-Command -Name 'python.exe' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -ne $PythonExe) {
        $PythonRoot = Split-Path -Parent $PythonExe.Source
        $SitePackages = Join-Path $PythonRoot 'Lib\site-packages'
        foreach ($Folder in @(
            (Join-Path $SitePackages 'nvidia\cu13\bin'),
            (Join-Path $SitePackages 'nvidia\cublas\bin')
        )) {
            if (Test-Path -LiteralPath (Join-Path $Folder 'cublas64_13.dll') -PathType Leaf) {
                Find-StrataRuntimeDirectory -Directory $Folder -Directories $Directories
            }
        }
    }

    # Если Visual C++ Runtime отсутствует в System32, предпочитаем
    # подписанный комплект той же установленной Visual Studio Build Tools.
    $Vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path -LiteralPath $Vswhere -PathType Leaf) {
        $VsRoot = & $Vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath |
            Select-Object -First 1
        if ($VsRoot) {
            $Redist = Join-Path $VsRoot 'VC\Redist\MSVC'
            if (Test-Path -LiteralPath $Redist -PathType Container) {
                $Versions = Get-ChildItem -LiteralPath $Redist -Directory -ErrorAction SilentlyContinue |
                    Sort-Object Name -Descending
                foreach ($Version in $Versions) {
                    $Crt = Join-Path $Version.FullName 'x64\Microsoft.VC143.CRT'
                    if (Test-Path -LiteralPath $Crt -PathType Container) {
                        Find-StrataRuntimeDirectory -Directory $Crt -Directories $Directories
                        break
                    }
                }
            }
        }
    }
    return $Directories.ToArray()
}

function Install-StrataLocalCublas {
    param([Parameter(Mandatory)][string]$Root)

    $Requirements = Join-Path $Root 'requirements-iq3s-cublas.txt'
    if (-not (Test-Path -LiteralPath $Requirements -PathType Leaf)) {
        throw "Не найден файл с фиксированной версией и SHA256 cuBLAS: $Requirements"
    }
    $PrivateRoot = Join-Path $Root '.strata-runtime'
    $Destination = Join-Path $PrivateRoot 'cublas-13.3.0.5'
    if (Test-Path -LiteralPath $Destination) {
        throw "Локальный пакет cuBLAS уже существует, но cublas64_13.dll в нём не найден: $Destination. Папка не удаляется автоматически."
    }
    $Python = Join-Path $Root '.venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) {
        $PythonCommand = Get-Command -Name 'python.exe' -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -eq $PythonCommand) { throw 'Не найден Python для получения официального пакета NVIDIA cuBLAS.' }
        $Python = $PythonCommand.Source
    }

    $Drive = [IO.Path]::GetPathRoot($Root).TrimEnd('\').TrimEnd(':')
    $Free = (Get-PSDrive -Name $Drive -ErrorAction Stop).Free
    if ($Free -lt 3GB) {
        throw ('Для локальной установки cuBLAS требуется запас от 3 ГиБ на {0}. Свободно {1:N2} ГиБ.' -f $Root, ($Free / 1GB))
    }

    New-Item -ItemType Directory -Path $PrivateRoot -Force | Out-Null
    $Staging = Join-Path $PrivateRoot ('cublas-install-' + [guid]::NewGuid().ToString('N'))
    Write-Host '=== ВОССТАНОВЛЕНИЕ ОФИЦИАЛЬНОЙ NVIDIA cuBLAS 13.3 ==='
    Write-Host 'Отсутствует cublas64_13.dll. Получаю официальный пакет NVIDIA (~388 МБ загрузки).'
    Write-Host "Установка только в $Destination; системные CUDA и Python не изменяются."
    Write-Host 'Контроль SHA256 wheel обязателен; при несовпадении установка прерывается.'
    try {
        # --require-hashes protects against an unverified substituted wheel;
        # --target and --no-deps prevent mutation of other applications.
        & $Python -m pip install --disable-pip-version-check --no-cache-dir --no-deps `
            --only-binary=:all: --require-hashes `
            --index-url https://pypi.org/simple `
            --target $Staging -r $Requirements
        if ($LASTEXITCODE -ne 0) {
            throw "Не удалось получить проверенный пакет cuBLAS. Код pip: $LASTEXITCODE"
        }
        $DllCandidates = @(Get-ChildItem -LiteralPath $Staging -Filter 'cublas64_13.dll' -File -Recurse -ErrorAction Stop)
        if ($DllCandidates.Count -ne 1 -or $DllCandidates[0].Length -lt 1MB) {
            throw "Ожидалась одна полноценная cublas64_13.dll в пакете NVIDIA; найдено $($DllCandidates.Count)."
        }
        if (Test-Path -LiteralPath $Destination) { throw "Каталог уже существует: $Destination" }
        Move-Item -LiteralPath $Staging -Destination $Destination -ErrorAction Stop
        Write-Host "Локальный NVIDIA cuBLAS 13.3 установлен: $Destination"
    }
    finally {
        # Only a staging directory created by THIS invocation is disposable.
        # Persistent model, GGUF, RAM disk, and CUDA installations are untouched.
        if (Test-Path -LiteralPath $Staging -PathType Container) {
            Remove-Item -LiteralPath $Staging -Recurse -Force
        }
    }
}

function Set-StrataRuntimeProcessPath {
    param([string[]]$Directories)
    $RemainingPaths = [System.Collections.Generic.List[string]]::new()
    foreach ($Entry in ($env:PATH -split ';')) {
        if ([string]::IsNullOrWhiteSpace($Entry)) { continue }
        $Normal = $Entry.Trim(' ', '"').TrimEnd('\')
        $Preferred = $false
        foreach ($Dir in $Directories) {
            if ([string]::Equals($Normal, $Dir, [StringComparison]::OrdinalIgnoreCase)) {
                $Preferred = $true
                break
            }
        }
        if (-not $Preferred) { $RemainingPaths.Add($Entry) }
    }
    $env:PATH = ((@($Directories) + @($RemainingPaths.ToArray())) -join ';')
}

function Write-StrataDependencyReport {
    param([Parameter(Mandatory)][string]$Engine, [Parameter(Mandatory)][string]$LogDir)
    $Report = Join-Path $LogDir 'DLL_DIAGNOSTICS_LAST.txt'
    $Lines = [System.Collections.Generic.List[string]]::new()
    $Lines.Add("Дата: $(Get-Date -Format o)")
    $Lines.Add("Движок: $Engine")
    $Lines.Add('Диагностика таблицы импортов PE (не учитывает все библиотеки, загружаемые позднее через LoadLibrary).')

    $Dumpbin = Get-Command -Name 'dumpbin.exe' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $DumpbinPath = if ($null -ne $Dumpbin) { $Dumpbin.Source } else { $null }
    if (-not $DumpbinPath) {
        $Vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
        if (Test-Path -LiteralPath $Vswhere -PathType Leaf) {
            $VsRoot = & $Vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath |
                Select-Object -First 1
            if ($VsRoot) {
                $BinRoot = Join-Path $VsRoot 'VC\Tools\MSVC'
                if (Test-Path -LiteralPath $BinRoot -PathType Container) {
                    $Candidates = @(Get-ChildItem -LiteralPath $BinRoot -Directory -ErrorAction SilentlyContinue |
                        Sort-Object Name -Descending)
                    foreach ($Candidate in $Candidates) {
                        $Path = Join-Path $Candidate.FullName 'bin\Hostx64\x64\dumpbin.exe'
                        if (Test-Path -LiteralPath $Path -PathType Leaf) { $DumpbinPath = $Path; break }
                    }
                }
            }
        }
    }
    if (-not $DumpbinPath) {
        $Lines.Add('dumpbin.exe отсутствует: перечисление импортируемых DLL недоступно.')
        $Lines | Set-Content -LiteralPath $Report -Encoding UTF8
        return $Report
    }
    $Lines.Add("dumpbin: $DumpbinPath")
    $SearchDirs = [System.Collections.Generic.List[string]]::new()
    Find-StrataRuntimeDirectory -Directory (Split-Path -Parent $Engine) -Directories $SearchDirs
    Find-StrataRuntimeDirectory -Directory "$env:WINDIR\System32" -Directories $SearchDirs
    Find-StrataRuntimeDirectory -Directory $env:WINDIR -Directories $SearchDirs
    foreach ($Item in ($env:PATH -split ';')) {
        Find-StrataRuntimeDirectory -Directory $Item.Trim(' ', '"') -Directories $SearchDirs
    }

    $Queue = [System.Collections.Generic.Queue[string]]::new()
    $Queue.Enqueue($Engine)
    $Seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $Missing = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $Scanned = 0
    while ($Queue.Count -gt 0 -and $Scanned -lt 80) {
        $Current = $Queue.Dequeue()
        if (-not $Seen.Add($Current)) { continue }
        $Scanned++
        $Lines.Add('')
        $Lines.Add("Импорты: $Current")
        try {
            $Output = @(& $DumpbinPath /nologo /dependents $Current 2>&1)
            if ($LASTEXITCODE -ne 0) {
                $Lines.Add("dumpbin возвратил код $LASTEXITCODE")
                continue
            }
        }
        catch {
            $Lines.Add("dumpbin: $($_.Exception.Message)")
            continue
        }
        foreach ($Row in $Output) {
            $Name = ([string]$Row).Trim()
            if ($Name -notmatch '^[A-Za-z0-9_.+-]+\.dll$') { continue }
            if ($Name -match '^(api-ms-win-|ext-ms-win-)') {
                $Lines.Add("  API set: $Name")
                continue
            }
            $Found = $null
            foreach ($Dir in $SearchDirs) {
                $Candidate = Join-Path $Dir $Name
                if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
                    $Found = $Candidate
                    break
                }
            }
            if ($Found) {
                $Lines.Add("  OK: $Name -> $Found")
                if (-not $Found.StartsWith("$env:WINDIR\", [StringComparison]::OrdinalIgnoreCase)) {
                    $Queue.Enqueue($Found)
                }
            }
            else {
                $Lines.Add("  ОТСУТСТВУЕТ: $Name")
                [void]$Missing.Add($Name)
            }
        }
    }
    if ($Queue.Count -gt 0) { $Lines.Add('Проверка ограничена первыми 80 зависимыми файлами.') }
    $Lines.Add('')
    if ($Missing.Count -gt 0) {
        $Lines.Add('Неразрешённые библиотеки: ' + (($Missing | Sort-Object) -join ', '))
    }
    else {
        $Lines.Add('Не найдены отсутствующие статические импорты. Возможны отсутствующие DLL, загружаемые динамически.')
    }
    $Lines | Set-Content -LiteralPath $Report -Encoding UTF8
    return $Report
}

function Initialize-StrataWindowsRuntime {
    param(
        [Parameter(Mandatory)][string]$Engine,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$LogDir,
        [switch]$RepairMissingCublas
    )
    if (-not (Test-Path -LiteralPath $Engine -PathType Leaf)) {
        throw "Исполняемый файл не найден: $Engine"
    }
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    $Dirs = @(Get-StrataRuntimeDirectories -Engine $Engine -Root $Root)
    # Правильная версия CUDA должна предшествовать старым путям из PATH;
    # это изменяет только окружение текущего процесса.
    Set-StrataRuntimeProcessPath -Directories $Dirs
    Write-Host '===== ПРОВЕРКА БИБЛИОТЕК WINDOWS/CUDA ====='
    foreach ($Dir in $Dirs) { Write-Host "Каталог DLL: $Dir" }

    # Diagnose FIRST and repair only the specific missing official cuBLAS.
    # GET-IQ3S-DIAGNOSTICS.ps1 intentionally calls this WITHOUT the switch.
    if ($RepairMissingCublas) {
        $AvailableBlas = $false
        foreach ($Dir in $Dirs) {
            if (Test-Path -LiteralPath (Join-Path $Dir 'cublas64_13.dll') -PathType Leaf) {
                $AvailableBlas = $true
                break
            }
        }
        if (-not $AvailableBlas) {
            $PreReport = Write-StrataDependencyReport -Engine $Engine -LogDir $LogDir
            if (Select-String -LiteralPath $PreReport -Pattern 'ОТСУТСТВУЕТ: cublas64_13.dll' -Quiet) {
                Install-StrataLocalCublas -Root $Root
                $Dirs = @(Get-StrataRuntimeDirectories -Engine $Engine -Root $Root)
                Set-StrataRuntimeProcessPath -Directories $Dirs
                Write-Host 'Каталоги DLL после восстановления cuBLAS:'
                foreach ($Dir in $Dirs) { Write-Host "Каталог DLL: $Dir" }
            }
        }
    }

    # --help возвращает 0 ДО загрузки GGUF и создания контекста GPU,
    # но лишь ПОСЛЕ успешной работы загрузчика PE и его DLL.
    $Stdout = Join-Path $LogDir 'ENGINE_LOADER_HELP.stdout.log'
    $Stderr = Join-Path $LogDir 'ENGINE_LOADER_HELP.stderr.log'
    try {
        $Process = Start-Process -FilePath $Engine -ArgumentList @('--help') -WorkingDirectory $Root `
            -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr -PassThru -ErrorAction Stop
        if (-not $Process.WaitForExit(15000)) {
            # При отсутствии DLL Windows может показать модальное окно вместо
            # немедленного завершения процесса. Бесконечно его не ждём.
            Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
            throw 'strata.exe --help не завершился за 15 секунд (возможен системный диалог о DLL)'
        }
        $Process.Refresh()
        $Code = [int64]$Process.ExitCode -band [int64]4294967295
    }
    catch {
        $Report = Write-StrataDependencyReport -Engine $Engine -LogDir $LogDir
        throw "Не удалось проверить запуск strata.exe: $($_.Exception.Message). Проверка DLL: $Report"
    }
    if ($Code -ne 0) {
        $Report = Write-StrataDependencyReport -Engine $Engine -LogDir $LogDir
        Write-Host "Проверка зависимостей сохранена: $Report"
        if (Test-Path -LiteralPath $Report -PathType Leaf) {
            Get-Content -LiteralPath $Report -Tail 25
        }
        if (Test-Path -LiteralPath $Stderr -PathType Leaf) {
            Get-Content -LiteralPath $Stderr -Tail 15
        }
        if ($Code -eq 3221225781) {
            throw "strata.exe не загружается: Windows 0xC0000135 (отсутствующая DLL). См. $Report"
        }
        throw ('strata.exe --help завершился с кодом 0x{0:X8}. См. {1}' -f $Code, $Report)
    }
    Write-Host 'Проверка strata.exe --help: OK (код 0).'
}
