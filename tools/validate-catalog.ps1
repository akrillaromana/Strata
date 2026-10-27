#requires -Version 7.0
# Валидатор каталога моделей: за один прогон проверяет ВСЁ, что нужно для запуска каждой
# ready-модели configs\MODEL-CATALOG.json: все сегменты GGUF, mmproj, native-pack
# (index.txt + native_experts.txt + tokenizer\chat_template.jinja), движок, сервер,
# iq_pack, MTP-runtime, expert-profile, AIM RAM-диск. Ничего не создаёт и не меняет.
# Запуск из папки установки: .\tools\validate-catalog.ps1  (или -Root <папка установки>).
[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$CatalogPath
)
$ErrorActionPreference = 'Stop'
if (-not $CatalogPath) { $CatalogPath = Join-Path $Root 'configs\MODEL-CATALOG.json' }
$Catalog = Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable

$problems = [System.Collections.Generic.List[string]]::new()
$report = [System.Collections.Generic.List[object]]::new()

foreach ($req in @('engine\strata.exe','engine\strata-vision.exe','serve\server.py','tools\iq_pack.py','data\expert-profile.bin','STRATA-MODEL-LAUNCH-COMMON.ps1','STRATA-WINDOWS-RUNTIME.ps1')) {
    $p = Join-Path $Root $req
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { $problems.Add("INFRA missing: $p") }
}
$mtp = [string]$Catalog.defaults.mtp_runtime
if (-not (Test-Path -LiteralPath $mtp -PathType Container)) { $problems.Add("INFRA missing MTP runtime: $mtp") }
if (-not (Test-Path -LiteralPath 'C:\Program Files\AIM Toolkit\aim_ll.exe' -PathType Leaf)) { $problems.Add('INFRA missing aim_ll.exe (RAM-диск недоступен без него)') }

foreach ($m in $Catalog.models) {
    $id = [string]$m.id
    $ready = ($m.architecture -eq 'qwen4exp')
    $first = [string]$m.first_shard
    $leaf = Split-Path -Leaf $first
    $dir = Split-Path -Parent $first
    $shardSizes = @()
    if ($leaf -match '^(.*-)(\d{5})-of-(\d{5})(\.gguf)$') {
        $total = [int]$Matches[3]
        for ($n = 1; $n -le $total; $n++) {
            $p = Join-Path $dir ('{0}{1:d5}-of-{2:d5}{3}' -f $Matches[1], $n, $total, $Matches[4])
            if (Test-Path -LiteralPath $p -PathType Leaf) { $shardSizes += (Get-Item -LiteralPath $p).Length }
            else { $problems.Add("$id shard $n/$total missing: $p") }
        }
    } else {
        if (Test-Path -LiteralPath $first -PathType Leaf) { $shardSizes += (Get-Item -LiteralPath $first).Length }
        else { $problems.Add("$id first shard missing: $first") }
    }
    $mmState = 'none'
    if ($m.ContainsKey('mmproj')) {
        $mmState = if (Test-Path -LiteralPath $m.mmproj -PathType Leaf) { 'ok' } else { 'MISSING' }
        if ($mmState -eq 'MISSING') { $problems.Add("$id mmproj missing: $($m.mmproj)") }
    }
    $packState = 'n/a'
    if ($m.ContainsKey('pack')) {
        $pack = [string]$m.pack
        $have = @()
        foreach ($f in @('index.txt','native_experts.txt','tokenizer\chat_template.jinja')) {
            if (-not (Test-Path -LiteralPath (Join-Path $pack $f) -PathType Leaf)) { $have += $f }
        }
        $packState = if ($have.Count) { 'INCOMPLETE(' + ($have -join ',') + ')' } else { 'ok' }
        if ($have.Count) { $problems.Add("$id pack incomplete: $pack missing " + ($have -join ', ')) }
    }
    $report.Add([pscustomobject]@{
        id = $id; ready = $ready; shards = $shardSizes.Count
        totalGiB = [math]::Round(((($shardSizes | Measure-Object -Sum).Sum) / 1GB), 1)
        mmproj = $mmState; pack = $packState
    })
}

$report | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
if ($problems.Count) {
    Write-Host "PROBLEMS ($($problems.Count)):" -ForegroundColor Red
    foreach ($p in $problems) { Write-Host "  $p" -ForegroundColor Red }
    exit 1
}
Write-Host 'ALL OK' -ForegroundColor Green
exit 0
