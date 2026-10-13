#requires -Version 7.0
<#
Совместимый ярлык к универсальному калибровщику: прежняя команда TUNE-IQ3S.ps1 сохранена.
Никакие файлы модели и временные данные RAM-диска не меняются.
Для любого другого профиля запускайте TUNE-MODEL.ps1 (с выбором модели).
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [ValidateRange(2,5)][int]$Rounds = 3,
    [ValidateRange(96,512)][int]$MaxTokens = 192,
    [ValidateRange(0.01,0.20)][double]$MinGain = 0.03
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Iq3s = Join-Path $Root 'strata-iq3_s-RAM.json'
if (-not (Test-Path -LiteralPath $Iq3s -PathType Leaf)) {
    throw 'Профиль IQ3_S пока не создан: запустите START-IQ3S-RAM.ps1.'
}
& (Join-Path $Root 'TUNE-MODEL.ps1') -ConfigPath $Iq3s -Apply:$Apply `
    -Rounds $Rounds -MaxTokens $MaxTokens -MinGain $MinGain
