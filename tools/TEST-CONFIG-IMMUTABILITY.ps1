#requires -Version 7.0
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'STRATA-MODEL-LAUNCH-COMMON.ps1')
$Work = Join-Path ([IO.Path]::GetTempPath()) ("strata-config-test-$([guid]::NewGuid().ToString('N'))")
New-Item -ItemType Directory -Path $Work -Force | Out-Null
try {
    $RootJson = Join-Path $Work 'root.json'
    $PersonalJson = Join-Path $Work 'personal.json'
    $Text = '{"exe":"C:\\user\\custom.exe","args":["--pack","C:\\old-pack","--native","C:\\old.gguf","--mtp","C:\\old-mtp","--pcie-frac","0.67","--spec-min-p","0.83","--spec","5","--expert-profile","C:\\old-profile","--max-context","12288"],"model_name":"test-model","sampling":{"temperature":0.38},"reasoning_budget_tokens":777,"api_key":"test-secret","autotune":false,"host":"127.0.0.1","port":8181}'
    [IO.File]::WriteAllText($RootJson, $Text, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($PersonalJson, '{"args":["--pcie-frac","0.11"]}', [Text.UTF8Encoding]::new($false))
    $Defaults = [ordered]@{
        exe='C:\runtime\strata.exe'; cwd='C:\runtime'; tokenizer='R:\pack\tokenizer'
        args=@('--pack','R:\pack','--native','R:\model.gguf','--spec-min-p','0.5')
        model_name='test-model'; log='C:\runtime\engine.log'; lib_dirs=@('C:\cuda')
        autotune=$true; host='0.0.0.0'; port=8080
    }
    $Bindings = @{'--pack'='R:\runtime-pack'; '--native'='R:\actual.gguf'; '--expert-profile'='R:\profile.bin'; '--mtp'='R:\mtp'}
    $RootIdentity = Get-Item -LiteralPath $RootJson | Select-Object Name, Length
    $PersonalIdentity = Get-Item -LiteralPath $PersonalJson | Select-Object Name, Length
    $Runtime = New-StrataModelRuntimeConfig -RootConfig $RootJson -PersonalConfig $PersonalJson `
        -Defaults $Defaults -RuntimeFlags $Bindings -LogDirectory $Work -RunId 'test'
    $Actual = Get-Content -LiteralPath $Runtime -Raw | ConvertFrom-Json -AsHashtable
    $ArgsList = @($Actual['args'])
    function Assert-Arg([string]$Flag, [string]$Expected) {
        $Index = [array]::IndexOf($ArgsList, $Flag)
        if ($Index -lt 0 -or $ArgsList[$Index + 1] -cne $Expected) { throw "Неверный аргумент $Flag" }
    }
    Assert-Arg '--pcie-frac' '0.67'
    Assert-Arg '--spec-min-p' '0.83'
    Assert-Arg '--spec' '5'
    Assert-Arg '--max-context' '12288'
    Assert-Arg '--pack' 'R:\runtime-pack'
    Assert-Arg '--native' 'R:\actual.gguf'
    Assert-Arg '--expert-profile' 'R:\profile.bin'
    Assert-Arg '--mtp' 'R:\mtp'
    if ($Actual['host'] -cne '127.0.0.1' -or [int]$Actual['port'] -ne 8181) {
        throw 'host/port пользователя были перезаписаны при старте.'
    }
    if ($Actual['sampling']['temperature'] -ne 0.38 -or $Actual['api_key'] -ne 'test-secret' -or
        $Actual['reasoning_budget_tokens'] -ne 777 -or $Actual['autotune'] -ne $false) {
        throw 'Настройки пользователя или запрет автокалибровки были потеряны.'
    }
    $RootAfter = Get-Item -LiteralPath $RootJson
    $PersonalAfter = Get-Item -LiteralPath $PersonalJson
    if ($RootAfter.Name -cne $RootIdentity.Name -or [int64]$RootAfter.Length -ne [int64]$RootIdentity.Length -or
        $PersonalAfter.Name -cne $PersonalIdentity.Name -or [int64]$PersonalAfter.Length -ne [int64]$PersonalIdentity.Length) {
        throw 'Исходный JSON был изменён при запуске!'
    }
    $Second = New-StrataModelRuntimeConfig -RootConfig (Join-Path $Work 'missing.json') `
        -PersonalConfig $PersonalJson -Defaults $Defaults -RuntimeFlags $Bindings `
        -LogDirectory $Work -RunId 'fallback' -IgnoreAutotune
    $Fallback = Get-Content -LiteralPath $Second -Raw | ConvertFrom-Json -AsHashtable
    if ($Fallback['autotune'] -ne $false) { throw '-IgnoreAutotune не сработал' }
    $FallbackArgs = @($Fallback['args'])
    if ($FallbackArgs -notcontains '0.11') { throw 'Не выбран fallback PERSONAL_START' }
    $PersonalAfterFallback = Get-Item -LiteralPath $PersonalJson
    if ($PersonalAfterFallback.Name -cne $PersonalIdentity.Name -or
        [int64]$PersonalAfterFallback.Length -ne [int64]$PersonalIdentity.Length) {
        throw 'Резервный JSON изменён.'
    }
    $BadConfig = Join-Path $Work 'invalid.json'
    [IO.File]::WriteAllText($BadConfig, '{invalid', [Text.Encoding]::UTF8)
    $Rejected = $false
    try {
        $null = New-StrataModelRuntimeConfig -RootConfig $BadConfig -PersonalConfig $PersonalJson `
            -Defaults $Defaults -RuntimeFlags $Bindings -LogDirectory $Work -RunId 'bad'
    } catch { $Rejected = $true }
    if (-not $Rejected) { throw 'Некорректный пользовательский JSON был проигнорирован.' }
    Write-Host '[OK] Настройки пользователя, args, sampling и api_key сохранены.'
    Write-Host '[OK] Изменены только временные пути к модели, MTP, PLE и служебные пути.'
    Write-Host '[OK] Файлы в корне и PERSONAL_START сохранили имя и точный размер.'
    Write-Host '[OK] Работают fallback, -IgnoreAutotune и защита повреждённого JSON.'
} finally {
    if (Test-Path -LiteralPath $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
}
