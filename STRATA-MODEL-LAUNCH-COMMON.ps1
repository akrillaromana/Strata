#requires -Version 7.0
# Общие проверки Windows для личных запускателей Strata.
# Этот файл только объявляет функции и не изменяет систему при подключении.
Set-StrictMode -Version Latest

function Resolve-StrataModelPython {
    param([Parameter(Mandatory)][string]$Root)
    $Candidates = [System.Collections.Generic.List[string]]::new()
    $Candidates.Add((Join-Path $Root '.venv\Scripts\python.exe'))
    foreach ($Name in @('python.exe', 'python3.exe')) {
        $Found = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $Found -and -not $Candidates.Contains($Found.Source)) {
            $Candidates.Add($Found.Source)
        }
    }
    foreach ($Candidate in $Candidates) {
        if (-not (Test-Path -LiteralPath $Candidate -PathType Leaf)) { continue }
        try {
            $Version = @(& $Candidate -c 'import sys; print(sys.version_info.major, sys.version_info.minor)' 2>$null)
            if ($LASTEXITCODE -ne 0 -or $Version.Count -eq 0) { continue }
            $Parts = ([string]$Version[-1]).Trim().Split(' ')
            if ($Parts.Count -ne 2 -or [int]$Parts[0] -ne 3 -or [int]$Parts[1] -lt 10) { continue }
            Write-Host ('Python: {0} ({1}.{2})' -f $Candidate, $Parts[0], $Parts[1])
            return $Candidate
        } catch {
            Write-Warning "Проверка Python не удалась: $Candidate"
        }
    }
    throw "Python 3.10+ не найден. Проверены .venv и системный PATH в $Root."
}

function Initialize-StrataModelDlls {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Engine,
        [Parameter(Mandatory)][string]$LogDirectory
    )
    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    $Helper = Join-Path $Root 'STRATA-WINDOWS-RUNTIME.ps1'
    if (-not (Test-Path -LiteralPath $Helper -PathType Leaf)) {
        throw "Не найден общий проверяющий модуль CUDA/MSVC: $Helper"
    }
    . $Helper
    Initialize-StrataWindowsRuntime -Engine $Engine -Root $Root -LogDir $LogDirectory -RepairMissingCublas
    return @(Get-StrataRuntimeDirectories -Engine $Engine -Root $Root)
}

function Assert-StrataModelServerStopped {
    param([ValidateRange(1,65535)][int]$Port = 8080)
    $Listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -ne $Listener) {
        throw "Порт $Port занят процессом $($Listener.OwningProcess). Остановите действующую модель Ctrl+C перед переключением; никаких процессов автоматически не завершаю."
    }
}

function Assert-StrataModelEngineStopped {
    param([Parameter(Mandatory)][string]$Root)
    $Processes = @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop |
        Where-Object {
            $_.ProcessId -ne $PID -and $_.CommandLine -and
            ($_.Name -in @('strata.exe','python.exe','python3.exe')) -and
            ($_.CommandLine.Contains("$Root\serve\server.py") -or
             $_.CommandLine.Contains("$Root\engine\strata.exe"))
        })
    if ($Processes.Count -gt 0) {
        throw ('Выполняются процессы Strata PID {0}. Остановите модель Ctrl+C до работы с RAM-диском; принудительное завершение не выполняю.' -f
            (($Processes | ForEach-Object { $_.ProcessId }) -join ', '))
    }
}

function Get-StrataDirectoryBytes {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return [int64](Get-Item -LiteralPath $Path).Length
    }
    $Sum = Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction Stop |
        Measure-Object -Property Length -Sum
    if ($null -eq $Sum.Sum) { return [int64]0 }
    return [int64]$Sum.Sum
}

function New-StrataModelRuntimeConfig {
    <#
    User-owned JSON (root has priority; PERSONAL_START is the fallback) is READ ONLY.
    Runtime-specific file paths are replaced in a separate logs/.../runtime-*.json.
    Explicit user arguments, sampling, reasoning, etc. are never reset to hard-coded
    launcher defaults.  Saved model autotune is applied later by serve/server.py.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RootConfig,
        [Parameter(Mandatory)][string]$PersonalConfig,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Defaults,
        [Parameter(Mandatory)][System.Collections.IDictionary]$RuntimeFlags,
        [Parameter(Mandatory)][string]$LogDirectory,
        [Parameter(Mandatory)][string]$RunId,
        [switch]$IgnoreAutotune,
        [System.Collections.IDictionary]$ExplicitFlags
    )
    $SourcePath = $null
    if (Test-Path -LiteralPath $RootConfig -PathType Leaf) {
        $SourcePath = $RootConfig
    } elseif (Test-Path -LiteralPath $PersonalConfig -PathType Leaf) {
        $SourcePath = $PersonalConfig
    }
    $Config = [ordered]@{}
    foreach ($Key in $Defaults.Keys) { $Config[[string]$Key] = $Defaults[$Key] }
    if ($SourcePath) {
        $Before = [IO.File]::ReadAllText($SourcePath, [Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($Before)) { throw "Пустой пользовательский JSON: $SourcePath" }
        try { $User = ConvertFrom-Json -InputObject $Before -AsHashtable -ErrorAction Stop }
        catch { throw "Ошибка пользовательского JSON $SourcePath : $($_.Exception.Message)" }
        if ($User -isnot [System.Collections.IDictionary]) {
            throw "Ожидается объект JSON в $SourcePath"
        }
        foreach ($Key in $User.Keys) { $Config[[string]$Key] = $User[$Key] }
    }
    if (-not $Config.Contains('args') -or $Config['args'] -isnot [array]) {
        throw "args должны быть JSON-массивом в $SourcePath"
    }
    $ArgsList = [System.Collections.Generic.List[string]]::new()
    foreach ($Arg in $Config['args']) {
        if ($Arg -isnot [string]) { throw "Все аргументы движка должны быть строками: $SourcePath" }
        $ArgsList.Add([string]$Arg)
    }
    $Required = @{}
    foreach ($Key in $RuntimeFlags.Keys) { $Required[[string]$Key] = [string]$RuntimeFlags[$Key] }
    if ($null -ne $ExplicitFlags) {
        foreach ($Key in $ExplicitFlags.Keys) { $Required[[string]$Key] = [string]$ExplicitFlags[$Key] }
    }
    # Modify ONLY arguments that point to a staged runtime file. Keep user
    # settings including --spec, --spec-min-p, --pcie-frac and extra flags.
    $Seen = @{}
    for ($Index = 0; $Index -lt $ArgsList.Count; $Index++) {
        $Flag = $ArgsList[$Index]
        if (-not $Required.ContainsKey($Flag)) { continue }
        if (($Index + 1) -ge $ArgsList.Count -or $ArgsList[$Index + 1].StartsWith('--')) {
            throw "После $Flag отсутствует значение в $SourcePath"
        }
        $ArgsList[$Index + 1] = $Required[$Flag]
        $Seen[$Flag] = $true
        $Index++
    }
    foreach ($Flag in $Required.Keys) {
        if (-not $Seen.ContainsKey($Flag)) {
            $ArgsList.Add([string]$Flag)
            $ArgsList.Add([string]$Required[$Flag])
        }
    }
    $Config['args'] = @($ArgsList.ToArray())
    # Only generated/runtime fields are forced; source files stay byte-identical.
    foreach ($Key in @('exe','cwd','tokenizer','log','lib_dirs','model_name')) {
        $Config[$Key] = $Defaults[$Key]
    }
    # Host/port are user preferences too: do not silently reset them to the
    # launcher defaults when the user selected another bind address/port.
    if (-not $Config.Contains('host')) { $Config['host'] = $Defaults['host'] }
    if (-not $Config.Contains('port')) { $Config['port'] = $Defaults['port'] }
    if ($IgnoreAutotune) { $Config['autotune'] = $false }
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    $RuntimePath = Join-Path $LogDirectory ("runtime-$RunId-$([guid]::NewGuid().ToString('N').Substring(0,8)).json")
    $Json = ($Config | ConvertTo-Json -Depth 64) + [Environment]::NewLine
    $null = ConvertFrom-Json -InputObject $Json -AsHashtable -ErrorAction Stop
    [IO.File]::WriteAllText($RuntimePath, $Json, [Text.UTF8Encoding]::new($false))
    Write-Host ('Исходный JSON (только чтение): {0}' -f $(if ($SourcePath) { $SourcePath } else { 'шаблон встроенного профиля' }))
    Write-Host "Временный JSON сервера: $RuntimePath"
    if ($IgnoreAutotune) { Write-Host 'Автокалибровка отключена для этого запуска (исходный JSON не менялся).' }
    return $RuntimePath
}

function Ensure-StrataModelRamDisk {
    <#
    Проверяет существующий R:, восстанавливает только однозначно найденный
    NTFS-том STRATA_PLE без буквы и создаёт новый AIM AWE-диск лишь тогда,
    когда подходящего тома не обнаружено. Никогда не форматирует существующий
    том, не удаляет устройства, не освобождает занятые буквы и не очищает файлы.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AimLl,
        [Parameter(Mandatory)][string]$Root,
        [string]$DriveLetter = 'R',
        [string]$VolumeLabel = 'STRATA_PLE',
        [long]$MinimumBytes = 60GB
    )
    $Mount = ('{0}:\' -f $DriveLetter)
    $LogDirectory = Join-Path $Root 'logs\ram-disk'
    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    $Report = Join-Path $LogDirectory 'RAM_DISK_LAST.txt'

    function Assert-StrataRamVolume {
        param($Volume, [string]$Location, [long]$Limit, [string]$Label)
        if ($null -eq $Volume) { throw "Windows не видит том $Location." }
        if ($Volume.FileSystem -ne 'NTFS' -or [long]$Volume.Size -lt $Limit) {
            throw ('Отказ работать с {0}: ФС={1}, метка={2}, размер={3:N2} ГиБ; ожидаются NTFS и не меньше {4:N2} ГиБ. Форматирование запрещено.' -f
                $Location, $Volume.FileSystem, $Volume.FileSystemLabel, ($Volume.Size / 1GB), ($Limit / 1GB))
        }
        if ($Volume.FileSystemLabel -eq $Label) { return }
        # AWE/ImDisk can return a blank FileSystemLabel in Get-Volume even when
        # the volume is mounted and usable. Use recognizable files or a verified
        # virtual-disk identity instead of requiring metadata that Windows may
        # temporarily omit. Never trust an unknown disk just because it is 64 GiB.
        $ReportedLabel = [string]$Volume.FileSystemLabel
        if ($Location -eq 'R:\' -and ($ReportedLabel -eq 'RamDisk' -or
                [string]::IsNullOrWhiteSpace($ReportedLabel))) {
            $KnownArtifacts = @(
                'q8-model\Qwen3.8-Flash-Next-Q8_0-00002-of-00006.gguf',
                'strata-runtime-q8\pack\index.txt',
                'iq3s-model\Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00002-of-00002.gguf',
                'strata-iq3s-runtime\pack\index.txt',
                'strata-q4-runtime\pack\index.txt',
                'q6-model\Qwen3.8-Flash-Next-Q6_K-00003-of-00005.gguf',
                'strata-runtime-q6\pack\index.txt'
            )
            foreach ($Relative in $KnownArtifacts) {
                if (Test-Path -LiteralPath (Join-Path $Location $Relative) -PathType Leaf) {
                    Write-Host 'Существующий R: принят по подтверждённым файлам Strata; метка тома не изменялась.'
                    return
                }
            }
            # Empty RAM disks after a reboot have no previous files. On those
            # machines require an identifiable AIM/ImDisk virtual device.
            try {
                $Partition = Get-Partition -DriveLetter R -ErrorAction Stop
                $Disk = Get-Disk -Number $Partition.DiskNumber -ErrorAction Stop
                if ($Disk.FriendlyName -match '(?i)Arsenal|Image Mounter|ImDisk|RAM Disk') {
                    Write-Host 'R: принят: Windows определила устройство как виртуальный RAM-диск.'
                    return
                }
            } catch { }
            throw 'R: не подтверждён как том Strata: отсутствуют ожидаемые файлы и Windows не распознаёт RAM-диск. Метка может быть пустой. Форматирование запрещено.'
        }
        throw ('Отказ работать с {0}: метка {1}; допустимы {2} или ранее использованный Strata RamDisk. Диск не форматировался.' -f
            $Location, $Volume.FileSystemLabel, $Label)
    }

    if (Test-Path -LiteralPath $Mount) {
        $Existing = Get-Volume -DriveLetter $DriveLetter -ErrorAction Stop
        Assert-StrataRamVolume -Volume $Existing -Location $Mount -Limit $MinimumBytes -Label $VolumeLabel
        Write-Host "RAM-диск $Mount уже доступен; существующие данные сохранены."
        return
    }

    $ExistingByLetter = Get-Volume -DriveLetter $DriveLetter -ErrorAction SilentlyContinue
    if ($null -ne $ExistingByLetter) {
        throw "Том $DriveLetter существует в Windows, но $Mount недоступен. Автоматически создавать/форматировать другое устройство нельзя."
    }

    $Matching = @(Get-Volume -FileSystemLabel $VolumeLabel -ErrorAction SilentlyContinue |
        Where-Object { $_.FileSystem -eq 'NTFS' -and [long]$_.Size -ge $MinimumBytes })
    if ($Matching.Count -gt 1) {
        throw "Найдены несколько томов $VolumeLabel. Автоматическое назначение буквы R запрещено; требуется диагностика."
    }
    if ($Matching.Count -eq 1) {
        $Volume = $Matching[0]
        if ($Volume.DriveLetter -and [string]$Volume.DriveLetter -ne $DriveLetter) {
            throw "RAM-диск $VolumeLabel уже имеет букву $($Volume.DriveLetter):. Не переназначаю её автоматически."
        }
        $Parts = @(Get-Partition -Volume $Volume -ErrorAction SilentlyContinue)
        if ($Parts.Count -ne 1) {
            throw "Найден том $VolumeLabel без буквы, но не удалось однозначно определить раздел для безопасного назначения R:."
        }
        Write-Host "Восстанавливаю букву R: существующему тому $VolumeLabel без форматирования."
        Add-PartitionAccessPath -InputObject $Parts[0] -AccessPath 'R:' -ErrorAction Stop
        Start-Sleep -Seconds 2
        if (-not (Test-Path -LiteralPath $Mount)) {
            throw "Буква R: не появилась после назначения существующему тому; создавать другой диск нельзя."
        }
        $Restored = Get-Volume -DriveLetter $DriveLetter -ErrorAction Stop
        Assert-StrataRamVolume -Volume $Restored -Location $Mount -Limit $MinimumBytes -Label $VolumeLabel
        return
    }

    if (-not (Test-Path -LiteralPath $AimLl -PathType Leaf)) {
        throw "AIM Toolkit не установлен: $AimLl"
    }

    # Список устройств сохраняется до попытки создания: если устройство AWE
    # оказалось бесхозным, пользователь увидит его номер без риска потери RAM.
    $Before = @(& $AimLl -l 2>&1)
    $BeforeText = ($Before | Out-String)
    [IO.File]::WriteAllText($Report, ("Перед созданием R: `r`n" + $BeforeText),
        [Text.UTF8Encoding]::new($false))
    Write-Host "R: отсутствует и том $VolumeLabel не найден. Создаю 64 ГиБ AIM AWE."
    $CreateOutput = @(& $AimLl -a -t file -o awe -s 64G -m 'R:' -p '/fs:ntfs /q /y /v:STRATA_PLE' 2>&1)
    $CreateExit = $LASTEXITCODE
    $CreationText = $CreateOutput | Out-String
    Add-Content -LiteralPath $Report -Value ("Создание R: (код $CreateExit):`r`n" + $CreationText) -Encoding utf8
    foreach ($Line in $CreateOutput) { Write-Host $Line }

    if ($CreateExit -ne 0) {
        # После отказа AIM новый повторный attach запрещён; важен номер уже
        # существующего устройства и состояние Windows Storage.
        $After = @(& $AimLl -l 2>&1)
        Add-Content -LiteralPath $Report -Value ("AIM после отказа:`r`n" + ($After | Out-String)) -Encoding utf8
        throw "AIM Toolkit вернул код $CreateExit. Возможен ранее зарегистрированный диск без буквы. Ничего не удалено; отчёт: $Report. Пришлите его для безопасного восстановления."
    }
    for ($Attempt = 0; $Attempt -lt 30 -and -not (Test-Path -LiteralPath $Mount); $Attempt++) {
        Start-Sleep -Seconds 1
    }
    if (-not (Test-Path -LiteralPath $Mount)) {
        throw "AIM создал устройство, но R: не появился. Не повторяйте создание; отчёт: $Report"
    }
    $Created = Get-Volume -DriveLetter $DriveLetter -ErrorAction Stop
    Assert-StrataRamVolume -Volume $Created -Location $Mount -Limit $MinimumBytes -Label $VolumeLabel
}
