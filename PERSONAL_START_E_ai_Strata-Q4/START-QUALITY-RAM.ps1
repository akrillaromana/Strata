param(
    [switch]$Foreground,
    [switch]$NoPrefillBorrow
)

$ErrorActionPreference = "Stop"

$Main = Join-Path $PSScriptRoot "START-Q4-RAM.ps1"

if (-not (Test-Path -LiteralPath $Main)) {
    throw "Не найден основной launcher: $Main"
}

$Forward = @()

if ($Foreground) {
    $Forward += "-Foreground"
}

if ($NoPrefillBorrow) {
    $Forward += "-NoPrefillBorrow"
}

& pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $Main @Forward
exit $LASTEXITCODE
