# Strata Fork / IQ3_S — неразрушающая проверка готовности и реальной генерации.
# Windows 10, PowerShell 7. Профиль модели, RAM-диск и сервер не изменяются.
param(
    [ValidateRange(10, 600)]
    [int]$GenerationTimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = 'E:\ai\Strata-Q4-Fork'
$ConfigPath = Join-Path $Root 'strata-iq3_s-RAM.json'
$LogDir = Join-Path $Root 'logs\iq3s'
$ReportPath = Join-Path $LogDir 'VERIFY_IQ3S_API_LAST.txt'
$BaseUri = 'http://127.0.0.1:8080'

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$Utf8 = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($ReportPath,
    "Strata IQ3_S — проверка API`r`nДата: $(Get-Date -Format o)`r`nАдрес: $BaseUri`r`n", $Utf8)

function Write-Result([string]$Message) {
    Write-Host $Message
    [System.IO.File]::AppendAllText($ReportPath, $Message + [Environment]::NewLine, $Utf8)
}

try {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Не найдена созданная запуском конфигурация: $ConfigPath. Сначала запустите START-IQ3S-RAM.ps1."
    }
    $Config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    $ModelNameProperty = $Config.PSObject.Properties['model_name']
    if ($null -eq $ModelNameProperty -or [string]::IsNullOrWhiteSpace([string]$ModelNameProperty.Value)) {
        throw 'В конфигурации IQ3_S отсутствует model_name.'
    }
    $ExpectedModel = [string]$ModelNameProperty.Value

    # Ключ читается только из локальной конфигурации; не печатается и не сохраняется в отчёт.
    $Headers = @{ Accept = 'application/json' }
    $KeyProperty = $Config.PSObject.Properties['api_key']
    $HasKey = $null -ne $KeyProperty -and -not [string]::IsNullOrWhiteSpace([string]$KeyProperty.Value)
    if ($HasKey) {
        $Headers['Authorization'] = 'Bearer ' + [string]$KeyProperty.Value
    }
    $HostProperty = $Config.PSObject.Properties['host']
    if ($null -ne $HostProperty -and [string]$HostProperty.Value -eq '0.0.0.0' -and -not $HasKey) {
        Write-Result '[ПРЕДУПРЕЖДЕНИЕ] Сервер слушает локальную сеть без ключа API. Ограничьте доступ межсетевым экраном либо задайте api_key.'
    }

    Write-Result '[1/3] Проверка /health ...'
    $Health = Invoke-RestMethod -Method Get -Uri "$BaseUri/health" -Headers $Headers -TimeoutSec 10
    if ($Health.status -ne 'ok' -or $Health.loaded -ne $true) {
        throw "Сервер отвечает, но модель не загружена (status=$($Health.status), loaded=$($Health.loaded))."
    }
    Write-Result "[OK] Здоровье сервера: status=$($Health.status), loaded=$($Health.loaded), context=$($Health.max_context)"

    Write-Result '[2/3] Проверка /v1/models ...'
    $Models = Invoke-RestMethod -Method Get -Uri "$BaseUri/v1/models" -Headers $Headers -TimeoutSec 10
    $Ids = @($Models.data | ForEach-Object { $_.id })
    if ($ExpectedModel -notin $Ids) {
        throw "На порту 8080 работает не тот профиль. Ожидалась модель '$ExpectedModel', доступны: $($Ids -join ', ')."
    }
    Write-Result "[OK] Обнаружена нужная модель: $ExpectedModel"

    Write-Result '[3/3] Короткая фактическая генерация /v1/chat/completions ...'
    $Request = @{
        model = $ExpectedModel
        messages = @(
            @{ role = 'user'; content = 'Ответь ровно одним словом: ГОТОВО' }
        )
        stream = $false
        max_tokens = 128
        temperature = 0
        chat_template_kwargs = @{ enable_thinking = $false }
        reasoning_budget_tokens = 0
    }
    $Payload = $Request | ConvertTo-Json -Depth 10 -Compress
    $Answer = Invoke-RestMethod -Method Post -Uri "$BaseUri/v1/chat/completions" `
        -Headers $Headers -ContentType 'application/json; charset=utf-8' `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($Payload)) -TimeoutSec $GenerationTimeoutSeconds

    $Choices = @($Answer.choices)
    if ($Choices.Count -eq 0 -or $null -eq $Choices[0] -or $null -eq $Choices[0].message) {
        throw 'Сервер ответил, но в ответе отсутствует choices[0].message.'
    }
    $Text = [string]$Choices[0].message.content
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Ответ модели пуст. Причина завершения: $($Choices[0].finish_reason)."
    }
    Write-Result "[OK] Ответ модели: $Text"
    Write-Result "Причина завершения: $($Choices[0].finish_reason)"
    if ($null -ne $Answer.usage) {
        Write-Result "Использование токенов: вход=$($Answer.usage.prompt_tokens), выход=$($Answer.usage.completion_tokens)"
    }
    Write-Result 'РЕЗУЛЬТАТ: УСПЕХ — API принимает запросы и возвращает сгенерированный текст.'
}
catch {
    Write-Result "РЕЗУЛЬТАТ: ОШИБКА — $($_.Exception.Message)"
    Write-Result 'Сервер и модель не остановлены, конфигурация не изменена.'
    throw
}
finally {
    Write-Host "Проверка сохранена: $ReportPath"
}
