#requires -Version 7.0
# Регресс-проверка единого запускателя START-CATALOG-MODEL.ps1 и каталога.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Launcher = Join-Path $Root 'START-CATALOG-MODEL.ps1'
$Bat = Join-Path $Root 'START-CATALOG-MODEL.bat'
$Catalog = Join-Path $Root 'configs\MODEL-CATALOG.json'
$fail = 0

foreach ($p in @($Launcher, $Bat, $Catalog)) {
    if (-not (Test-Path -LiteralPath $p)) { Write-Host "FAIL missing: $p" -ForegroundColor Red; $fail++ }
}

$tokens = $null; $errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($Launcher, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count) { Write-Host "FAIL parse: $($errors[0].Message)" -ForegroundColor Red; $fail++ } else { Write-Host 'OK parse launcher' }

$src = Get-Content -LiteralPath $Launcher -Raw
foreach ($needle in @('configs\MODEL-CATALOG.json', 'ram-state.json', 'TargetGiBOverride', 'gpu_on_demand',
                      'reasoning_budget_tokens', 'Read-Letter', 'по умолчанию для этой модели',
                      '@($BuilderArgs + ''--compat-bf16'')', 'Чанк префилла', 'parallel/--batch',
                      'Test-StrataRamVirtualDevice', 'request_log', 'Логгер запросов',
                      'ple_shard.py', 'COPY PLE',
                      '--control-vector-scaled', '--cvec-mode', '--cvec-dir', 'STRATA_HC_Q8',
                      'experimental_speed_projection', 'STRATA_ROUTE_PRIOR', 'STRATA_KVA',
                      'qwen-nvfp4-gptq-uncensored.gguf', 'ResolveLinkTarget', '$vol.Size -ge $DefaultNeed')) {
    if ($src -notlike ('*' + $needle + '*')) { Write-Host "FAIL source lacks: $needle" -ForegroundColor Red; $fail++ }
}

foreach ($vec in @('data\uncensor\qwen-nvfp4-gptq-uncensored.gguf', 'data\uncensor\qwen-nvfp4-gptq-uncensored.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $vec) -PathType Leaf)) { Write-Host "FAIL missing: $vec" -ForegroundColor Red; $fail++ }
}

$server = Get-Content -LiteralPath (Join-Path $Root 'serve\server.py') -Raw
if ($server -notlike '*log_incoming_request*') { Write-Host 'FAIL server lacks: log_incoming_request' -ForegroundColor Red; $fail++ }

$cat = Get-Content -LiteralPath $Catalog -Raw -Encoding UTF8 | ConvertFrom-Json
$ready = @($cat.models | Where-Object { $_.architecture -eq 'qwen4exp' })
if ($ready.Count -lt 4) { Write-Host "FAIL catalog ready=$($ready.Count)" -ForegroundColor Red; $fail++ } else { Write-Host "OK catalog ready=$($ready.Count)" }
foreach ($m in $ready) {
    if (-not (Test-Path -LiteralPath $m.first_shard)) { Write-Host "FAIL shard missing: $($m.id)" -ForegroundColor Red; $fail++ }
}

if ($fail) { Write-Host "FAILED: $fail" -ForegroundColor Red; exit 1 }
Write-Host 'ALL OK'
