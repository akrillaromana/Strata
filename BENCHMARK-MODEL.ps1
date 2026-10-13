#requires -Version 7.0
<# Бенчмарк активной модели. Использует реальные timings от сервера. Не меняет конфиг. #>
[CmdletBinding()]
param(
    [ValidateRange(1,20)][int]$Runs=3,
    [ValidateRange(32,2048)][int]$MaxTokens=192,
    [ValidateRange(1,65535)][int]$Port=8080,
    [string]$ApiKey=''
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
$Base="http://127.0.0.1:$Port"
$Headers=@{}
if($ApiKey){$Headers['Authorization']="Bearer $ApiKey"}
$Models=Invoke-RestMethod -Uri "$Base/v1/models" -Headers $Headers -TimeoutSec 15
$Loaded=@($Models.data | Where-Object {
    $StatusProperty = $_.PSObject.Properties['status']
    $null -eq $StatusProperty -or $null -eq $StatusProperty.Value -or
        $StatusProperty.Value.value -eq 'loaded'
})
if($Loaded.Count -ne 1){throw "Нужна одна загруженная модель, найдено: $($Loaded.Count)"}
$Model=[string]$Loaded[0].id
$Dir=Join-Path $Root 'logs\benchmark'
New-Item -ItemType Directory -Path $Dir -Force | Out-Null
$Rows=[System.Collections.Generic.List[object]]::new()
Write-Host "=== STRATA BENCHMARK: $Model ===" -ForegroundColor Cyan
for($i=1;$i -le $Runs;$i++){
    $Prompt=@"
Опиши технически подробно управление VRAM, кэширование экспертов, спекулятивное декодирование и стоимость
передачи данных по PCIe при локальном запуске языковой модели. Номер независимого замера: $i.
"@
    $Body=@{model=$Model;messages=@(@{role='user';content=$Prompt});
        max_tokens=$MaxTokens;stream=$false;temperature=0;reasoning_budget_tokens=0;
        chat_template_kwargs=@{enable_thinking=$false}} | ConvertTo-Json -Depth 8 -Compress
    $Answer=Invoke-RestMethod -Uri "$Base/v1/chat/completions" -Method Post -Headers $Headers `
        -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($Body)) -TimeoutSec 600
    if(-not $Answer.timings){throw "Замер $i: сервер не вернул timings"}
    $Pre=[double]$Answer.timings.prompt_per_second
    $Dec=[double]$Answer.timings.predicted_per_second
    if($Pre -le 0 -or $Dec -le 0){throw "Замер $i: неверные значения prefill/decode"}
    $Rows.Add([pscustomobject]@{number=$i;prefill_tok_s=$Pre;decode_tok_s=$Dec;
        output_tokens=[int]$Answer.timings.predicted_n})
    Write-Host ('{0}/{1}: prefill {2:N1} ток/с | decode {3:N1} ток/с' -f $i,$Runs,$Pre,$Dec)
}
$MeanPrefill=($Rows | Measure-Object prefill_tok_s -Average).Average
$MeanDecode=($Rows | Measure-Object decode_tok_s -Average).Average
$Result=[ordered]@{at=(Get-Date -Format o);model=$Model;runs=$Runs;max_tokens=$MaxTokens;
    average_prefill_tok_s=$MeanPrefill;average_decode_tok_s=$MeanDecode;results=@($Rows.ToArray())}
$Output=Join-Path $Dir 'BENCHMARK_MODEL_LAST.json'
[IO.File]::WriteAllText($Output,(ConvertTo-Json -InputObject $Result -Depth 10),[Text.UTF8Encoding]::new($false))
Write-Host ('СРЕДНЯЯ: prefill {0:N1} ток/с | decode {1:N1} ток/с' -f $MeanPrefill,$MeanDecode)
Write-Host "Отчёт: $Output"
