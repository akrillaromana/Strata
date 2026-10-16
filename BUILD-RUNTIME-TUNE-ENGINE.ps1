#requires -Version 7.0
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Build = Join-Path $Root 'BUILD_AND_START_IQ3S.ps1'
if (-not (Test-Path -LiteralPath $Build -PathType Leaf)) { throw "Не найден: $Build" }

Write-Host '=== STRATA LIVE RUNTIME TUNE ENGINE ===' -ForegroundColor Cyan
Write-Host 'Собирается обычный движок БЕЗ parity gating.'
Write-Host 'Это нужно один раз после итерации 056, чтобы работающий engine понимал live TUNE + per-request pcie_frac/spec_min_p.'
& $Build -BuildOnly
if (-not $?) { throw 'Сборка/установка текущего strata.exe завершилась ошибкой.' }

$Engine = Join-Path $Root 'engine\strata.exe'
if (-not (Test-Path -LiteralPath $Engine -PathType Leaf)) { throw "После сборки отсутствует $Engine" }
Write-Host '[OK] engine\strata.exe обновлён. После запуска модели INFO должен содержать request_tune=2/live_tune=1.' -ForegroundColor Green
Write-Host 'Parity CPU/CUDA этим скриптом НЕ проверяется и не блокирует runtime tuning.'
