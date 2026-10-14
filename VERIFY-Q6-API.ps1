[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [string]$ExpectedModel = 'qwen3.8-flash-next-unsloth-q6_k'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Root = 'E:\ai\Strata-Q4-Fork'
$LogDir = Join-Path $Root 'logs\q6'
$Log = Join-Path $LogDir 'VERIFY_Q6_LAST.txt'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$lines = [System.Collections.Generic.List[string]]::new()
function Note([string]$Text) { $lines.Add($Text); Write-Host $Text }
try {
    Note '=== STRATA Q6_K API VERIFY ==='
    $health = Invoke-RestMethod -Uri "$BaseUrl/health" -TimeoutSec 20
    Note ("health: status={0}; loaded={1}; context={2}" -f $health.status,$health.loaded,$health.context)
    if ($health.loaded -ne $true) { throw 'Сервер отвечает, но модель не отмечена как loaded.' }

    $models = Invoke-RestMethod -Uri "$BaseUrl/v1/models" -TimeoutSec 20
    $ids = @($models.data | ForEach-Object { [string]$_.id })
    if ($ids -notcontains $ExpectedModel) {
        throw ("Ожидалась модель {0}; сервер сообщает: {1}" -f $ExpectedModel,($ids -join ', '))
    }
    Note ("model: {0}" -f $ExpectedModel)

    $body = @{
        model = $ExpectedModel
        messages = @(@{ role='user'; content='Ответь ровно одним словом: ГОТОВО' })
        max_tokens = 64
        temperature = 0
        stream = $false
        reasoning_budget_tokens = 0
        chat_template_kwargs = @{ enable_thinking = $false }
    } | ConvertTo-Json -Depth 8 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($body)
    $answer = Invoke-RestMethod -Method Post -Uri "$BaseUrl/v1/chat/completions" -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 180
    $text = [string]$answer.choices[0].message.content
    if ([string]::IsNullOrWhiteSpace($text)) { throw 'Модель вернула пустой ответ.' }
    Note ("answer: {0}" -f $text.Trim())
    Note 'RESULT: OK'
} catch {
    Note ("RESULT: FAIL: {0}" -f $_.Exception.Message)
    $lines | Set-Content -LiteralPath $Log -Encoding UTF8
    throw
}
$lines | Set-Content -LiteralPath $Log -Encoding UTF8
Write-Host ("Отчёт: {0}" -f $Log) -ForegroundColor DarkGray
