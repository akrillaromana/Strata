#requires -Version 7.0
[CmdletBinding()]
param([ValidateRange(1,65535)][int]$Port = 8080)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Api = "http://127.0.0.1:$Port"
$Headers = @{ 'Content-Type' = 'application/json; charset=utf-8' }

# Use the normal Q8 profile's key when one is configured; otherwise localhost needs no Authorization header.
$CfgPath = Join-Path $Root 'strata-unsloth-q8_0.json'
if (Test-Path -LiteralPath $CfgPath -PathType Leaf) {
    try {
        $Cfg = Get-Content -LiteralPath $CfgPath -Raw -Encoding utf8 | ConvertFrom-Json -ErrorAction Stop
        if ($Cfg.PSObject.Properties['api_key'] -and $Cfg.api_key) { $Headers.Authorization = "Bearer $($Cfg.api_key)" }
    } catch { Write-Warning "Не удалось прочитать api_key из ${CfgPath}: $($_.Exception.Message)" }
}

$Settings = Invoke-RestMethod -Uri "$Api/settings" -Headers $Headers -TimeoutSec 15
if ($Settings.runtime_tune_supported -ne $true) {
    throw 'Работающий strata.exe не объявил request_tune=2/live_tune=1. Сначала BUILD-RUNTIME-TUNE-ENGINE.ps1, затем перезапустите модель.'
}
$Models = Invoke-RestMethod -Uri "$Api/v1/models" -Headers $Headers -TimeoutSec 15
$Model = @($Models.data)[0].id
if (-not $Model) { throw 'На сервере нет загруженной модели.' }

function Set-LiveTune([double]$Pcie) {
    $Payload = @{ set = @{ pcie_frac = $Pcie } } | ConvertTo-Json -Depth 5 -Compress
    $Ack = Invoke-RestMethod -Uri "$Api/runtime-tune" -Method Post -Headers $Headers `
        -Body ([Text.Encoding]::UTF8.GetBytes($Payload)) -TimeoutSec 30
    $Actual = [double]$Ack.pcie_frac
    if ([Math]::Abs($Actual - $Pcie) -gt 0.000001) { throw "TUNE: запрошено PCIe=$Pcie, движок применил $Actual." }
    Write-Host ('[OK] live setter: PCIe={0:0.00}; scheduler={1}/256' -f $Actual, [int]$Ack.pcie_num) -ForegroundColor Green
}

function Invoke-Probe([double]$ExpectedPcie, [string]$Tag) {
    $Body = @{
        model = $Model
        messages = @(@{ role='user'; content="Runtime PCIe probe $Tag. Дай ровно 48 коротких слов, пронумерованных от 1 до 48." })
        stream = $false
        temperature = 0
        max_tokens = 96
        reasoning_budget_tokens = 0
        chat_template_kwargs = @{ enable_thinking = $false }
    } | ConvertTo-Json -Depth 12 -Compress
    $Answer = Invoke-RestMethod -Uri "$Api/v1/chat/completions" -Method Post -Headers $Headers `
        -Body ([Text.Encoding]::UTF8.GetBytes($Body)) -TimeoutSec 600
    if ($Answer.strata_tune_applied -ne $true -or -not $Answer.strata_tune) {
        throw "PCIe=$ExpectedPcie не подтверждён DONE движка."
    }
    $Actual = [double]$Answer.strata_tune.pcie_frac
    if ([Math]::Abs($Actual - $ExpectedPcie) -gt 0.000001) { throw "Ожидалось PCIe=$ExpectedPcie, DONE подтвердил $Actual." }
    $Speed = if ($Answer.timings -and $Answer.timings.predicted_per_second) { [double]$Answer.timings.predicted_per_second } else { 0.0 }
    $Off = if ($Answer.timings -and $null -ne $Answer.timings.pcie_offloaded_entries) { [int64]$Answer.timings.pcie_offloaded_entries } else { -1 }
    Write-Host ('[OK] request: PCIe={0:0.00}; decode={1:0.0} tok/s; PCIe offload entries={2}' -f $Actual, $Speed, $Off) -ForegroundColor Green
    return @{ pcie=$Actual; speed=$Speed; offload=$Off }
}

$OriginalPcie = if ($Settings.runtime_tune_current -and $null -ne $Settings.runtime_tune_current.pcie_frac) {
    [double]$Settings.runtime_tune_current.pcie_frac
} elseif ($Settings.model_tune -and $null -ne $Settings.model_tune.pcie_frac) {
    [double]$Settings.model_tune.pcie_frac
} else { 0.0 }

try {
    Set-LiveTune 0.0
    $AtZero = Invoke-Probe 0.0 'ZERO'
    Set-LiveTune 1.0
    $AtOne = Invoke-Probe 1.0 'ONE'

    if ($AtZero.offload -ge 0 -and $AtZero.offload -ne 0) {
        throw "PCIe=0 должен дать 0 offload entries, получено $($AtZero.offload). Runtime setter не управляет scheduler."
    }
    if ($AtZero.offload -ge 0 -and $AtOne.offload -ge 0 -and $AtOne.offload -le $AtZero.offload) {
        throw "PCIe=1 не увеличил число PCIe offload entries: 0.0=$($AtZero.offload), 1.0=$($AtOne.offload)."
    }
    Write-Host ('[PASS] Реальный expert scheduler изменён без рестарта: offload {0} -> {1}.' -f $AtZero.offload, $AtOne.offload) -ForegroundColor Green
} finally {
    try {
        Set-LiveTune $OriginalPcie
        Write-Host ('[RESTORE] Возвращён исходный runtime PCIe={0:0.00}. JSON не менялся.' -f $OriginalPcie) -ForegroundColor Cyan
    } catch {
        Write-Warning "Не удалось вернуть исходный runtime PCIe=${OriginalPcie}: $($_.Exception.Message)"
    }
}
