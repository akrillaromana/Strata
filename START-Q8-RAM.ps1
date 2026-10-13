#requires -Version 7.0
# Удобный вход из корня форка; исходный профиль хранится вместе с остальными.
[CmdletBinding()]
param(
    [string]$ModelsDirectory,
    [string]$PackSource,
    [string]$MtpSource = 'E:\ai\Strata-data\mtp\rt',
    [switch]$PreparePack,
    [switch]$AllowBf16Conversion,
    [switch]$Detached,
    [switch]$Foreground,
    [switch]$IgnoreAutotune
)
$ErrorActionPreference = 'Stop'
$Launcher = Join-Path $PSScriptRoot 'PERSONAL_START_E_ai_Strata-Q4-Fork\START-Q8-RAM.ps1'
if (-not (Test-Path -LiteralPath $Launcher -PathType Leaf)) {
    throw "Не найден Q8_0 запускатель: $Launcher"
}
# Защита от неполной распаковки: корневой вход и личный сценарий должны
# понимать один набор ключей, прежде чем начнётся проверка модели или R:.
$LauncherCommand = Get-Command -Name $Launcher -CommandType ExternalScript -ErrorAction Stop
foreach ($ParameterName in @('PreparePack', 'AllowBf16Conversion', 'ModelsDirectory',
                             'PackSource', 'MtpSource', 'Detached', 'Foreground', 'IgnoreAutotune')) {
    if (-not $LauncherCommand.Parameters.ContainsKey($ParameterName)) {
        throw "Смешаны версии Q8-запускателей: внутренний файл не понимает -${ParameterName}: $Launcher. Полностью обновите комплект итерации 048 и выполните tools\TEST-MODEL-LAUNCHERS.ps1."
    }
}
Write-Host 'Q8_0: запускатели итерации 048, поддержка -PreparePack и -AllowBf16Conversion проверена.'
$Params = @{
    MtpSource=$MtpSource
    PreparePack=$PreparePack
    AllowBf16Conversion=$AllowBf16Conversion
    Detached=$Detached
    Foreground=$Foreground
    IgnoreAutotune=$IgnoreAutotune
}
if ($PSBoundParameters.ContainsKey('ModelsDirectory')) { $Params.ModelsDirectory = $ModelsDirectory }
if ($PSBoundParameters.ContainsKey('PackSource')) { $Params.PackSource = $PackSource }
try {
    & $Launcher @Params
    if (-not $?) { throw 'Внутренний запускатель Q8_0 завершился с ошибкой без исключения.' }
} catch {
    $Dir = Join-Path $PSScriptRoot 'logs\q8'
    New-Item -Path $Dir -ItemType Directory -Force | Out-Null
    $Report = Join-Path $Dir 'Q8_FAILURE_LAST.txt'
    $Details = @(
        ('Время: {0}' -f (Get-Date -Format 'o')),
        ('Запускатель: {0}' -f $Launcher),
        ('Ошибка: {0}' -f $_.Exception.Message),
        ('Позиция: {0}' -f $_.InvocationInfo.PositionMessage),
        ('Стек: {0}' -f $_.ScriptStackTrace),
        ('Последняя контрольная точка: {0}' -f (Join-Path $Dir 'Q8_START_LAST.txt'))
    )
    [IO.File]::WriteAllLines($Report, $Details, [Text.UTF8Encoding]::new($false))
    Write-Host ('Q8_0: ошибка запуска, подробности: {0}' -f $Report) -ForegroundColor Red
    throw
}