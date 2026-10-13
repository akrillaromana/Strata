#requires -Version 7.0
<#
Проверка синтаксиса и конфликтов имён функций калибровщика.
Никаких запросов к модели, изменений профиля или установки зависимостей.
Выполняется встроенным разборщиком PowerShell на Windows пользователя.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Root = Split-Path -Parent $PSScriptRoot
$Script = Join-Path $Root 'TUNE-MODEL.ps1'
if (-not (Test-Path -LiteralPath $Script -PathType Leaf)) {
    throw "Калибровщик не найден: $Script"
}

$Tokens = $null
$ParseErrors = $null
$Tree = [System.Management.Automation.Language.Parser]::ParseFile(
    $Script, [ref]$Tokens, [ref]$ParseErrors)
if ($ParseErrors.Count -gt 0) {
    foreach ($Item in $ParseErrors) {
        Write-Host "Ошибка $($Item.Extent.StartLineNumber): $($Item.Message)" -ForegroundColor Red
    }
    throw 'Калибровщик содержит синтаксические ошибки PowerShell.'
}

$Functions = @($Tree.FindAll({
    param($Ast)
    $Ast -is [System.Management.Automation.Language.FunctionDefinitionAst]
}, $true))
$Names = @($Functions | ForEach-Object { $_.Name })
$Expected = @('Get-Profile', 'Invoke-TuningSample', 'Measure-TuningCandidates',
              'Get-TuningMedian', 'Get-TuningScore')
foreach ($Name in $Expected) {
    if ($Names -cnotcontains $Name) {
        throw "Не найдена обязательная функция: $Name"
    }
}
foreach ($Name in $Names) {
    $Alias = Get-Alias -Name $Name -ErrorAction SilentlyContinue
    if ($null -ne $Alias) {
        throw "Имя функции '$Name' совпадает с псевдонимом '$($Alias.Definition)'."
    }
}

Write-Host "[OK] Синтаксис PowerShell и имена $($Names.Count) функций проверены." -ForegroundColor Green
Write-Host '[OK] Проверка не запускала модель и не изменяла настройки.' -ForegroundColor Green