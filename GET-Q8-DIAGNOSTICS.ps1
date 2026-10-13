#requires -Version 7.0
<#
Безопасная диагностика Q8_0. Только читает состояние Windows, файлов и API.
Не копирует GGUF, не форматирует и не отключает RAM-диск, не останавливает процессы.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Root = $PSScriptRoot
$LogDir = Join-Path $Root 'logs\q8'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$Report = Join-Path $LogDir 'Q8_DIAGNOSTICS_LAST.txt'
$Lines = [System.Collections.Generic.List[string]]::new()

function Write-Q8Diagnostic {
    param([AllowEmptyString()][string]$Message)
    Write-Host $Message
    $Lines.Add($Message)
}
function Write-Q8DiagnosticFile {
    param([string]$Path, [int]$MaxLines = 80)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Q8Diagnostic ('Нет файла: {0}' -f $Path)
        return
    }
    Write-Q8Diagnostic ('Файл: {0} ({1} байт)' -f $Path, (Get-Item -LiteralPath $Path).Length)
    foreach ($Line in @(Get-Content -LiteralPath $Path -Tail $MaxLines -ErrorAction Stop)) {
        Write-Q8Diagnostic ([string]$Line)
    }
}

try {
    Write-Q8Diagnostic '=== ДИАГНОСТИКА STRATA Q8_0 / ИТЕРАЦИЯ 046 ==='
    Write-Q8Diagnostic ('Время: {0}' -f (Get-Date -Format 'o'))
    Write-Q8Diagnostic ('Проект: {0}' -f $Root)
    Write-Q8Diagnostic ''

    Write-Q8Diagnostic '=== СОСТОЯНИЕ RAM-ДИСКА ==='
    if (Test-Path -LiteralPath 'R:\') {
        try {
            $Volume = Get-Volume -DriveLetter R -ErrorAction Stop
            Write-Q8Diagnostic ('Том R: ФС={0}, метка={1}, размер={2:N2} ГиБ' -f
                $Volume.FileSystem, $Volume.FileSystemLabel, ($Volume.Size / 1GB))
            $Drive = Get-PSDrive -Name R -ErrorAction Stop
            Write-Q8Diagnostic ('Свободно R: {0:N2} ГиБ' -f ($Drive.Free / 1GB))
        } catch {
            Write-Q8Diagnostic ('Не удалось прочитать параметры R: {0}' -f $_.Exception.Message)
        }
        foreach ($Known in @('R:\iq3s-model', 'R:\strata-iq3s-runtime',
                              'R:\q4-model', 'R:\strata-q4-runtime',
                              'R:\q8-model', 'R:\strata-runtime-q8')) {
            Write-Q8Diagnostic ('{0} : {1}' -f $Known, $(if (Test-Path -LiteralPath $Known) { 'существует' } else { 'нет' }))
        }
    } else {
        Write-Q8Diagnostic 'R: недоступен.'
    }
    Write-Q8Diagnostic ''

    Write-Q8Diagnostic '=== ПРОЦЕССЫ STRATA ==='
    try {
        $Processes = @(Get-CimInstance Win32_Process -ErrorAction Stop |
            Where-Object {
                $_.Name -in @('strata.exe','python.exe','python3.exe') -and $_.CommandLine -and
                ($_.CommandLine.Contains('Strata-Q4-Fork\engine\strata.exe') -or
                 $_.CommandLine.Contains('Strata-Q4-Fork\serve\server.py'))
            })
        if ($Processes.Count -eq 0) { Write-Q8Diagnostic 'Процессы движка/сервера форка не обнаружены.' }
        foreach ($Process in $Processes) {
            Write-Q8Diagnostic ('PID={0}, имя={1}' -f $Process.ProcessId, $Process.Name)
        }
    } catch {
        Write-Q8Diagnostic ('Сведения о процессах недоступны: {0}' -f $_.Exception.Message)
    }
    Write-Q8Diagnostic ''

    Write-Q8Diagnostic '=== КОНТРОЛЬНЫЕ ТОЧКИ ==='
    Write-Q8DiagnosticFile -Path (Join-Path $LogDir 'Q8_START_LAST.txt') -MaxLines 100
    Write-Q8DiagnosticFile -Path (Join-Path $LogDir 'Q8_FAILURE_LAST.txt') -MaxLines 70
    Write-Q8Diagnostic ''

    Write-Q8Diagnostic '=== ПОСЛЕДНИЕ ЖУРНАЛЫ ДВИЖКА И СЕРВЕРА ==='
    foreach ($Mask in @('engine-*.stderr.log', 'server-*.stderr.log', 'server-*.stdout.log')) {
        $File = Get-ChildItem -LiteralPath $LogDir -Filter $Mask -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($null -eq $File) { Write-Q8Diagnostic ('Нет журналов по шаблону {0}' -f $Mask) }
        else { Write-Q8DiagnosticFile -Path $File.FullName -MaxLines 45 }
    }
    Write-Q8Diagnostic ''

    Write-Q8Diagnostic '=== API ==='
    try {
        $Response = Invoke-RestMethod -Uri 'http://127.0.0.1:8080/v1/models' -TimeoutSec 4 -ErrorAction Stop
        foreach ($Model in @($Response.data)) {
            Write-Q8Diagnostic ('Загруженная модель: {0}' -f $Model.id)
        }
    } catch {
        Write-Q8Diagnostic ('API не ответил: {0}' -f $_.Exception.Message)
    }
} finally {
    [IO.File]::WriteAllLines($Report, $Lines, [Text.UTF8Encoding]::new($false))
    Write-Host ('Отчёт сохранён: {0}' -f $Report) -ForegroundColor Green
}
