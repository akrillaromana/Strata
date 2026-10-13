$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Root   = "E:\ai\Strata-Q4-Fork"
$Data   = "E:\ai\Strata-data"
$Models = "$Data\models\IQ3_S"

$Items = @(
    "$Root\.venv\Scripts\python.exe",
    "$Root\serve\server.py",
    "$Root\engine\strata.exe",
    "$Root\data\expert-profile.bin",
    "$Data\packs\iq3_s",
    "$Data\packs\iq3_s\tokenizer\vocab.json",
    "$Data\mtp\rt",
    "$Models\Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf",
    "$Models\Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00002-of-00002.gguf",
    "C:\Program Files\AIM Toolkit\aim_ll.exe"
)

$Bad = $false
foreach ($P in $Items) {
    $Ok = Test-Path -LiteralPath $P
    Write-Host ("{0,-6} {1}" -f $(if ($Ok) {"OK"} else {"MISS"}), $P)
    if (-not $Ok) { $Bad = $true }
}

Write-Host ""
$ServerPath = "$Root\serve\server.py"
if (Test-Path -LiteralPath $ServerPath) {
    $ServerText = Get-Content -LiteralPath $ServerPath -Raw
    Write-Host "server reasoning_budget_tokens: $($ServerText.Contains('reasoning_budget_tokens'))"
    Write-Host "server REASONING_WRAP_UP:       $($ServerText.Contains('REASONING_WRAP_UP'))"
}

foreach ($Name in @(
    "Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf",
    "Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00002-of-00002.gguf"
)) {
    $P = Join-Path $Models $Name
    if (Test-Path -LiteralPath $P -PathType Leaf) {
        $I = Get-Item -LiteralPath $P
        Write-Host ("{0}: {1:N2} GiB" -f $I.Name, ($I.Length/1GB))
    }
}

Write-Host ""
if ($Bad) {
    Write-Host "IQ3_S prerequisites are INCOMPLETE. Nothing was changed."
    exit 1
}
Write-Host "IQ3_S prerequisites look complete."
Write-Host "Use: START-HERE IQ3_S.bat"
