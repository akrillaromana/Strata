#requires -Version 7.0
<#
Сравнение скорости: выполнять отдельно для старой и новой сборок с одинаковой
моделью, настройками и запросом. Не переключает PLE, RAM и параметры движка.
Результаты сервера берутся из поля timings, а не вычисляются из времени HTTP.
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 20)][int]$Runs = 3,
    [ValidateRange(32, 2048)][int]$MaxTokens = 256
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Root = 'E:\ai\Strata-Q4-Fork'
$Cfg = Join-Path $Root 'strata-iq3_s-RAM.json'
$Logs = Join-Path $Root 'logs\iq3s'
if (-not (Test-Path -LiteralPath $Cfg -PathType Leaf)) {
    throw "Конфигурация IQ3_S не найдена: $Cfg"
}
$Config = Get-Content -LiteralPath $Cfg -Raw | ConvertFrom-Json
$Headers = @{ 'Content-Type' = 'application/json' }
if ($Config.PSObject.Properties.Name -contains 'api_key' -and $Config.api_key) {
    $Headers['Authorization'] = "Bearer $($Config.api_key)"
}
$Base = 'http://127.0.0.1:8080'
$Model = [string]$Config.model_name
if ([string]::IsNullOrWhiteSpace($Model)) { throw 'model_name отсутствует в конфигурации' }
try {
    $Models = Invoke-RestMethod -Uri "$Base/v1/models" -Headers $Headers -TimeoutSec 15
} catch { throw "Сервер не готов на $Base : $($_.Exception.Message)" }
if (@($Models.data | Where-Object { $_.id -eq $Model }).Count -eq 0) {
    throw "Сервер не сообщает о загруженной модели $Model"
}
New-Item -ItemType Directory -Path $Logs -Force | Out-Null
$ReportPath = Join-Path $Logs 'BENCHMARK_IQ3S_LAST.txt'
$Stats = [System.Collections.Generic.List[object]]::new()
$Lines = [System.Collections.Generic.List[string]]::new()
$Lines.Add("Date: $(Get-Date -Format o)")
$Lines.Add("Model: $Model")
$Lines.Add("Runs: $Runs, max tokens: $MaxTokens")
$Lines.Add('Показатели из серверного поля timings; это не сравнение со старой версией.')
Write-Host "Измерение ${Model}: $Runs запросов" -ForegroundColor Cyan
for ($i = 1; $i -le $Runs; $i++) {
    $Text = @"
Напиши на русском связный технический обзор оптимизации загрузки и выполнения больших языковых моделей.
Рассмотри передачу весов между оперативной и видеопамятью, кэш экспертов, задержки PCIe,
префилл длинного контекста и спекулятивное декодирование. Приводи полезные объяснения причин и следствий.
Тестовая последовательность: $i. Не повторяй текст предыдущего абзаца.
"@
    $Body = @{
        model = $Model
        messages = @(@{ role = 'user'; content = $Text })
        max_tokens = $MaxTokens
        temperature = 0
        stream = $false
        reasoning_budget_tokens = 0
        chat_template_kwargs = @{ enable_thinking = $false }
    } | ConvertTo-Json -Depth 8 -Compress
    $Response = Invoke-RestMethod -Uri "$Base/v1/chat/completions" -Headers $Headers `
        -Method Post -Body ([Text.Encoding]::UTF8.GetBytes($Body)) -TimeoutSec 600
    if (-not $Response.timings) { throw "Запрос ${i}: сервер не вернул timings; результаты нельзя считать" }
    $T = $Response.timings
    $Pre = [double]$T.prompt_per_second
    $Dec = [double]$T.predicted_per_second
    if ($Pre -le 0 -or $Dec -le 0) { throw "Запрос ${i}: нулевые либо отсутствующие скорости" }
    $Stats.Add([pscustomobject]@{ Prefill = $Pre; Decode = $Dec; Tokens = [int]$T.predicted_n })
    $Line = ('{0}/{1}: prefilling {2:N1} tok/s, decoding {3:N1} tok/s; output {4} tokens' -f `
            $i, $Runs, $Pre, $Dec, $T.predicted_n)
    $Lines.Add($Line)
    Write-Host $Line
}
$AvgPre = ($Stats | Measure-Object Prefill -Average).Average
$AvgDec = ($Stats | Measure-Object Decode -Average).Average
$Lines.Add(('AVERAGE: prefill {0:N1} tok/s; decode {1:N1} tok/s' -f $AvgPre, $AvgDec))
$Lines.Add('Сравнивать следует с такими же запросами старой сборки после прогрева модели.')
[IO.File]::WriteAllLines($ReportPath, $Lines, [Text.UTF8Encoding]::new($false))
Write-Host $Lines[$Lines.Count - 2]
Write-Host "Результат: $ReportPath"
