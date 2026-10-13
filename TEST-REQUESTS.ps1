#requires -Version 7.0
<#
Повторная диагностика зависания OpenAI API после нескольких сообщений.
Не меняет ни конфигурацию, ни RAM-диск, ни веса, не перезапускает двигатель.
#>
[CmdletBinding()]
param(
    [ValidateRange(2,30)][int]$Requests = 6,
    [ValidateRange(16,1024)][int]$MaxTokens = 96,
    [ValidateRange(15,900)][int]$TimeoutSeconds = 180,
    [ValidateRange(1,65535)][int]$Port = 8080,
    [string]$ApiKey = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Base = "http://127.0.0.1:$Port"
$Headers = @{}
if ($ApiKey) { $Headers['Authorization'] = "Bearer $ApiKey" }
$Dir = Join-Path $Root 'logs\request-tests'
New-Item -ItemType Directory -Path $Dir -Force | Out-Null
$Report = Join-Path $Dir 'REQUEST_TEST_LAST.json'
$Runs = [System.Collections.Generic.List[object]]::new()
$Status = 'completed'
$ErrorText = $null
$Model = $null
$Conversation = [System.Collections.Generic.List[object]]::new()
try {
    $Models = Invoke-RestMethod -Uri "$Base/v1/models" -Headers $Headers -TimeoutSec 15
    $Active = @($Models.data | Where-Object {
        $StatusProperty = $_.PSObject.Properties['status']
        $null -eq $StatusProperty -or $null -eq $StatusProperty.Value -or
            $StatusProperty.Value.value -eq 'loaded'
    })
    if ($Active.Count -ne 1) { throw "Ожидается одна загруженная модель, найдено: $($Active.Count)" }
    $Model = [string]$Active[0].id
    Write-Host "Модель: $Model, тестов: $Requests; API: $Base" -ForegroundColor Cyan
    for ($Number=1; $Number -le $Requests; $Number++) {
        $Check = Get-Date
        $Text = "Проверка Strata номер $Number. Ответь одной короткой фразой на русском."
        # One growing conversation: reproduces hangs after several turns, not
        # only the easier case of independent one-message requests.
        $Conversation.Add(@{role='user';content=$Text})
        $Body = @{
            model = $Model
            messages = @($Conversation.ToArray())
            stream = $false
            max_tokens = $MaxTokens
            temperature = 0
            reasoning_budget_tokens = 0
            chat_template_kwargs = @{ enable_thinking = $false }
        } | ConvertTo-Json -Depth 8 -Compress
        try {
            $Answer = Invoke-RestMethod -Uri "$Base/v1/chat/completions" -Method Post `
                -Body ([Text.Encoding]::UTF8.GetBytes($Body)) -ContentType 'application/json; charset=utf-8' `
                -Headers $Headers -TimeoutSec $TimeoutSeconds
            $Sec = [math]::Round(((Get-Date)-$Check).TotalSeconds, 2)
            $Message = [string]$Answer.choices[0].message.content
            $Usage = $Answer.usage
            if (-not $Message.Trim()) { throw "Пустой ответ на запрос $Number" }
            $Conversation.Add(@{role='assistant';content=$Message})
            $Runs.Add([pscustomobject]@{request=$Number;ok=$true;seconds=$Sec;
                input_tokens=$Usage.prompt_tokens;output_tokens=$Usage.completion_tokens;
                response_chars=$Message.Length})
            Write-Host ('{0}/{1}: OK {2:N2} с, {3} выходных токенов' -f $Number,$Requests,$Sec,$Usage.completion_tokens)
        } catch {
            $Status = 'failed'
            $ErrorText = "Запрос ${Number}: $($_.Exception.Message)"
            $Runs.Add([pscustomobject]@{request=$Number;ok=$false;error=$ErrorText;
                seconds=[math]::Round(((Get-Date)-$Check).TotalSeconds,2)})
            Write-Warning $ErrorText
            foreach ($Endpoint in @('/health','/status','/v1/status')) {
                try {
                    $Diagnostic = Invoke-RestMethod -Uri "$Base$Endpoint" -Headers $Headers -TimeoutSec 5
                    $Runs.Add([pscustomobject]@{diagnostic=$Endpoint;result=$Diagnostic})
                } catch {
                    $Runs.Add([pscustomobject]@{diagnostic=$Endpoint;error=$_.Exception.Message})
                }
            }
            break
        }
    }
} catch {
    $Status='failed'
    $ErrorText = $_.Exception.Message
} finally {
    $Record = [ordered]@{
        date=(Get-Date -Format 'o');model=$Model;api=$Base;status=$Status;
        requests=$Requests;max_tokens=$MaxTokens;growing_conversation=$true;
        error=$ErrorText;measurements=@($Runs.ToArray())
    }
    [IO.File]::WriteAllText($Report,(ConvertTo-Json -InputObject $Record -Depth 12),[Text.UTF8Encoding]::new($false))
    Write-Host "Диагностика: $Report"
}
if ($Status -ne 'completed') { throw "Последовательность запросов завершилась ошибкой: $ErrorText" }
Write-Host "OK: ${Requests} последовательных запросов приняты и завершены." -ForegroundColor Green
