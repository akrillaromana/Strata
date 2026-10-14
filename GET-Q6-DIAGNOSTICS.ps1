#requires -Version 7.0
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
$Root=$PSScriptRoot; $LogDir=Join-Path $Root 'logs\q6'; New-Item -ItemType Directory -Path $LogDir -Force|Out-Null
$Report=Join-Path $LogDir 'Q6_DIAGNOSTICS_LAST.txt'; $Lines=[System.Collections.Generic.List[string]]::new()
function Out-Line([string]$Text){Write-Host $Text;$Lines.Add($Text)}
function Out-Tail([string]$Path,[int]$Count=70){
 if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){Out-Line "Нет файла: $Path";return}
 $I=Get-Item -LiteralPath $Path;Out-Line ("Файл: {0} ({1} байт)" -f $I.FullName,$I.Length)
 foreach($L in @(Get-Content -LiteralPath $Path -Tail $Count -ErrorAction Stop)){Out-Line ([string]$L)}
}
try{
 Out-Line '=== STRATA Q6_K DIAGNOSTICS / ITERATION 051 ===';Out-Line (Get-Date -Format o);Out-Line ''
 Out-Line '=== Q6 ENGINE ===';$Exe=Join-Path $Root 'engine-q6\strata.exe'
 if(Test-Path -LiteralPath $Exe -PathType Leaf){$I=Get-Item $Exe;Out-Line ("{0} ({1} байт)" -f $I.FullName,$I.Length)}else{Out-Line 'engine-q6\strata.exe отсутствует.'}
 Out-Line '=== RAM DISK ==='
 if(Test-Path -LiteralPath 'R:\'){
  try{$V=Get-Volume -DriveLetter R -ErrorAction Stop;$D=Get-PSDrive R -ErrorAction Stop;Out-Line ('R: FS={0}; label={1}; size={2:N2} GiB; free={3:N2} GiB' -f $V.FileSystem,$V.FileSystemLabel,($V.Size/1GB),($D.Free/1GB))}catch{Out-Line $_.Exception.Message}
  foreach($P in @('R:\q6-model','R:\strata-runtime-q6')){Out-Line ("$P : "+$(if(Test-Path -LiteralPath $P){'существует'}else{'нет'}))}
 }else{Out-Line 'R: недоступен.'}
 Out-Line '=== PROCESSES ==='
 try{$Ps=@(Get-CimInstance Win32_Process|Where-Object{$_.CommandLine -and ($_.CommandLine.Contains('engine-q6\strata.exe') -or $_.CommandLine.Contains('Strata-Q4-Fork\serve\server.py'))});if($Ps.Count-eq 0){Out-Line 'Процессы Q6/server не обнаружены.'};foreach($P in $Ps){Out-Line("PID={0} {1}" -f $P.ProcessId,$P.Name)}}catch{Out-Line $_.Exception.Message}
 Out-Line '=== API ==='
 try{$R=Invoke-RestMethod 'http://127.0.0.1:8080/v1/models' -TimeoutSec 4;foreach($M in @($R.data)){Out-Line("model={0}" -f $M.id)}}catch{Out-Line("API: {0}" -f $_.Exception.Message)}
 Out-Line '=== CHECKPOINT ===';Out-Tail (Join-Path $LogDir 'Q6_START_LAST.txt') 120
 Out-Line '=== LAST LOGS ==='
 foreach($Mask in @('engine-*.stderr.log','server-*.stderr.log','server-*.stdout.log','Q6_BUILD_LAST.txt')){$F=Get-ChildItem -LiteralPath $LogDir -Filter $Mask -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 1;if($F){Out-Tail $F.FullName 60}else{Out-Line("Нет $Mask")}}
}finally{[IO.File]::WriteAllLines($Report,$Lines,[Text.UTF8Encoding]::new($false));Write-Host "Отчёт: $Report" -ForegroundColor Green}
