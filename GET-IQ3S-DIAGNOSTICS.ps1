# Strata Fork / IQ3_S: read-only diagnostics after a failed start.
# Does not rebuild the engine, change model files or clear the R: RAM disk.
# PowerShell 7 / Windows 10.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = 'E:\ai\Strata-Q4-Fork'
$LogDir = Join-Path $Root 'logs\iq3s'
$Result = Join-Path $LogDir 'DIAGNOSTICS_LAST.txt'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$TranscriptStarted = $false
try {
    Start-Transcript -LiteralPath $Result -Force | Out-Null
    $TranscriptStarted = $true
    Write-Host '=== STRATA IQ3_S DIAGNOSTICS ==='
    Write-Host "Date: $(Get-Date -Format o)"
    Write-Host "Root: $Root"

    Write-Host "`n=== WINDOWS CUDA/MSVC DLL LOADER PREFLIGHT ==="
    $Engine = Join-Path $Root 'engine\strata.exe'
    $Helper = Join-Path $Root 'STRATA-WINDOWS-RUNTIME.ps1'
    $LoaderOk = $false
    if (Test-Path -LiteralPath $Helper -PathType Leaf) {
        try {
            . $Helper
            Initialize-StrataWindowsRuntime -Engine $Engine -Root $Root -LogDir $LogDir
            $LoaderOk = $true
        }
        catch {
            Write-Host "Ошибка загрузчика движка: $($_.Exception.Message)"
        }
    }
    else { Write-Host "Отсутствует файл: $Helper" }
    $DependencyReport = Join-Path $LogDir 'DLL_DIAGNOSTICS_LAST.txt'
    if (Test-Path -LiteralPath $DependencyReport -PathType Leaf) {
        if ($LoaderOk) {
            Write-Host "`n=== ПРЕЖНИЙ ОТЧЁТ О DLL (СЕЙЧАС --help УСПЕШЕН) ==="
        }
        else { Write-Host "`n=== PE DEPENDENCY REPORT ===" }
        Get-Content -LiteralPath $DependencyReport -Tail 200
    }

    foreach ($Pattern in @('console-*.log', 'engine-previous-R-*.stderr.log', 'engine-*.stderr.log',
                           'server-*.stderr.log', 'server-*.stdout.log')) {
        Write-Host "`n=== MOST RECENT: $Pattern ==="
        $File = Get-ChildItem -LiteralPath $LogDir -File -Filter $Pattern -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($null -eq $File) {
            Write-Host 'No corresponding log files yet.'
            continue
        }
        Write-Host "File: $($File.FullName) ($($File.Length) bytes)"
        Get-Content -LiteralPath $File.FullName -Tail 200 -ErrorAction Stop
    }

    $LegacyLog = 'R:\strata-iq3s-runtime\strata-iq3_s.log'
    if (Test-Path -LiteralPath $LegacyLog -PathType Leaf) {
        Write-Host "`n=== PREVIOUS ENGINE LOG ON RAM DISK ==="
        Write-Host "File: $LegacyLog"
        Get-Content -LiteralPath $LegacyLog -Tail 200
    }

    Write-Host "`n=== RAM ==="
    try {
        $Mem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        Write-Host ("Available: {0:N2} GiB / Total: {1:N2} GiB" -f `
            ($Mem.FreePhysicalMemory * 1KB / 1GB), ($Mem.TotalVisibleMemorySize * 1KB / 1GB))
    }
    catch { Write-Host "RAM check failed: $($_.Exception.Message)" }

    Write-Host "`n=== GPU ==="
    if (Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue) {
        & nvidia-smi.exe --query-gpu=index,name,memory.total,memory.used,memory.free --format=csv,noheader
    }
    else { Write-Host 'nvidia-smi not found' }

    Write-Host "`n=== WINDOWS APPLICATION ERRORS FOR STRATA.EXE (LAST 6 HOURS) ==="
    try {
        $Events = @(Get-WinEvent -FilterHashtable @{
            LogName = 'Application'
            Id = @(1000, 1001)
            StartTime = (Get-Date).AddHours(-6)
        } -MaxEvents 200 -ErrorAction Stop | Where-Object {
            $_.Message -match '(?i)strata\.exe'
        } | Select-Object -First 5)
        if ($Events.Count -eq 0) { Write-Host 'No matching Windows events' }
        foreach ($Event in $Events) {
            Write-Host "Event $($Event.Id), $($Event.TimeCreated)"
            Write-Host $Event.Message
        }
    }
    catch { Write-Host "Windows events unavailable: $($_.Exception.Message)" }
}
finally {
    if ($TranscriptStarted) { Stop-Transcript | Out-Null }
}
Write-Host "Diagnostics saved: $Result"
