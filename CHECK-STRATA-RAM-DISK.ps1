#requires -Version 7.0
<#
Диагностика устройств AIM и томов Windows Storage без создания/удаления
дисков, назначения букв или очистки каких-либо данных.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Root = 'E:\ai\Strata-Q4-Fork'
$AimLl = 'C:\Program Files\AIM Toolkit\aim_ll.exe'
$Directory = Join-Path $Root 'logs\ram-disk'
New-Item -ItemType Directory -Path $Directory -Force | Out-Null
$Report = Join-Path $Directory 'RAM_DIAGNOSTICS_LAST.txt'
$Lines = [System.Collections.Generic.List[string]]::new()
$Lines.Add('Проверка RAM-диска Strata; изменения не вносятся.')
$Lines.Add((Get-Date).ToString('o'))
$Lines.Add('R:\ доступен: ' + (Test-Path -LiteralPath 'R:\'))
$Lines.Add('===== AIM DEVICES =====')
if (Test-Path -LiteralPath $AimLl -PathType Leaf) {
    try {
        foreach ($Line in @(& $AimLl -l 2>&1)) { $Lines.Add([string]$Line) }
        $Lines.Add("AIM exit code: $LASTEXITCODE")
    } catch { $Lines.Add('AIM error: ' + $_.Exception.Message) }
} else { $Lines.Add('AIM not found: ' + $AimLl) }
$Lines.Add('===== STORAGE VOLUMES =====')
try {
    $Volumes = @(Get-Volume -ErrorAction Stop)
    foreach ($Volume in $Volumes) {
        $Lines.Add(('Letter={0}; Label={1}; FS={2}; SizeGiB={3:N2}; Health={4}; UniqueId={5}' -f
            $Volume.DriveLetter, $Volume.FileSystemLabel, $Volume.FileSystem,
            ($Volume.Size / 1GB), $Volume.HealthStatus, $Volume.UniqueId))
        if ($Volume.FileSystemLabel -in @('STRATA_PLE','RamDisk')) {
            try {
                foreach ($P in @(Get-Partition -Volume $Volume -ErrorAction Stop)) {
                    $Lines.Add(('  Partition disk={0} part={1} letter={2}; access={3}' -f
                        $P.DiskNumber, $P.PartitionNumber, $P.DriveLetter, ($P.AccessPaths -join ',')))
                }
            } catch { $Lines.Add('  Get-Partition: ' + $_.Exception.Message) }
        }
    }
} catch { $Lines.Add('Get-Volume: ' + $_.Exception.Message) }
$Lines.Add('===== STORAGE DISKS =====')
try {
    foreach ($Disk in @(Get-Disk -ErrorAction Stop)) {
        $Lines.Add(('Disk={0}; FriendlyName={1}; Bus={2}; SizeGiB={3:N2}; Offline={4}; ReadOnly={5}' -f
            $Disk.Number, $Disk.FriendlyName, $Disk.BusType, ($Disk.Size / 1GB),
            $Disk.IsOffline, $Disk.IsReadOnly))
    }
} catch { $Lines.Add('Get-Disk: ' + $_.Exception.Message) }
$Lines.Add('===== MOUNTVOL =====')
try { foreach ($Line in @(& mountvol.exe 2>&1)) { $Lines.Add([string]$Line) } }
catch { $Lines.Add('mountvol: ' + $_.Exception.Message) }
[IO.File]::WriteAllLines($Report, $Lines, [Text.UTF8Encoding]::new($false))
foreach ($Line in $Lines) { Write-Host $Line }
Write-Host "Отчёт сохранён: $Report"
