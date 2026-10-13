#requires -Version 7.0
[CmdletBinding()]
param([switch]$Detached, [switch]$Foreground, [switch]$NoPrefillBorrow)
$ErrorActionPreference = 'Stop'
$Launcher = Join-Path $PSScriptRoot 'PERSONAL_START_E_ai_Strata-Q4-Fork\START-Q4-RAM.ps1'
if (-not (Test-Path -LiteralPath $Launcher -PathType Leaf)) { throw "Не найден запускатель Q4: $Launcher" }
& $Launcher -Detached:$Detached -Foreground:$Foreground -NoPrefillBorrow:$NoPrefillBorrow