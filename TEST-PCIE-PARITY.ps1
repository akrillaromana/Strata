#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$Api = 'http://127.0.0.1:8080',
    [double[]]$Pcie = @(0.0, 0.09, 0.2, 0.26, 0.5, 1.0),
    [int]$MaxTokens = 256,
    [string]$Prompt = 'Вычисли 37*43, затем кратко объясни ход вычисления. Ответ должен быть детерминированным.'
)
$ErrorActionPreference = 'Stop'
$Invariant = [Globalization.CultureInfo]::InvariantCulture
$Models = Invoke-RestMethod -Uri "$Api/v1/models" -TimeoutSec 30
$Model = [string]$Models.data[0].id
if ([string]::IsNullOrWhiteSpace($Model)) { throw 'Сервер не вернул model id.' }
Write-Host "Модель: $Model" -ForegroundColor Cyan
Write-Host ('PCIe: ' + (($Pcie | ForEach-Object { $_.ToString('0.00',$Invariant) }) -join ', '))
$Results = [System.Collections.Generic.List[object]]::new()
foreach ($F in $Pcie) {
    $Body = @{
        model = $Model
        messages = @(@{role='user'; content=$Prompt})
        stream = $false
        temperature = 0
        max_tokens = $MaxTokens
        reasoning_budget_tokens = 0
        chat_template_kwargs = @{ enable_thinking = $false }
        strata_tune = @{ pcie_frac = [double]$F }
    }
    $Json = $Body | ConvertTo-Json -Depth 12 -Compress
    $A = Invoke-RestMethod -Uri "$Api/v1/chat/completions" -Method Post `
        -Body ([Text.Encoding]::UTF8.GetBytes($Json)) -ContentType 'application/json; charset=utf-8' -TimeoutSec 600
    $Text = [string]$A.choices[0].message.content
    $Speed = if ($A.timings) { [double]$A.timings.predicted_per_second } else { 0.0 }
    $Results.Add([pscustomobject]@{pcie_frac=[double]$F; text=$Text; speed=$Speed})
    Write-Host ('pcie={0}: {1:0.0} ток/с, {2} символов' -f $F, $Speed, $Text.Length)
}
$Base = $Results[0].text
$Same = $true
foreach ($R in $Results) {
    $Equal = [string]::Equals($Base, $R.text, [StringComparison]::Ordinal)
    if (-not $Equal) { $Same = $false }
    Write-Host ('  pcie={0}: {1}' -f $R.pcie_frac, $(if ($Equal) {'IDENTICAL'} else {'DIFFERENT'})) `
        -ForegroundColor $(if ($Equal) {'Green'} else {'Red'})
}
$Dir = Join-Path $PSScriptRoot 'logs\parity'
New-Item -ItemType Directory -Path $Dir -Force | Out-Null
$Out = Join-Path $Dir 'PCIE_PARITY_LAST.json'
@{model=$Model; prompt=$Prompt; identical=$Same; results=@($Results)} | ConvertTo-Json -Depth 8 | `
    Set-Content -LiteralPath $Out -Encoding utf8
Write-Host "Отчёт: $Out"
if (-not $Same) { throw 'PCIE PARITY FAIL: temperature=0 дал разные ответы при разных pcie_frac.' }
Write-Host 'PCIE PARITY PASS: ответы идентичны.' -ForegroundColor Green
