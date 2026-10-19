#requires -Version 7.0
$ErrorActionPreference='Stop'
$Root='E:\ai\Strata-Q4-Fork'
$Cat=Get-Content -LiteralPath (Join-Path $Root 'data\personal_models.json') -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 64
foreach($m in $Cat.models){
  $missing=@()
  foreach($n in @($m.files)){
    if(-not (Test-Path -LiteralPath (Join-Path ([string]$m.directory) ([string]$n)) -PathType Leaf)){ $missing += [string]$n }
  }
  $resolved=$null
  if($missing.Count -gt 0 -and @($m.files).Count -eq 1 -and $m.PSObject.Properties.Name -contains 'model_glob' -and $m.model_glob -and (Test-Path -LiteralPath ([string]$m.directory) -PathType Container)){
    $matches=@(Get-ChildItem -LiteralPath ([string]$m.directory) -File -Filter ([string]$m.model_glob) -ErrorAction SilentlyContinue |
      Where-Object { -not $_.Name.EndsWith('.part',[StringComparison]::OrdinalIgnoreCase) -and -not $_.Name.StartsWith('downloading_',[StringComparison]::OrdinalIgnoreCase) })
    if($matches.Count -eq 1){ $missing=@(); $resolved=$matches[0].Name }
  }
  $state=if($missing.Count){'PENDING'}else{'READY'}
  $suffix=if($resolved){" [glob -> $resolved]"}else{''}
  '{0,-8} {1,-38} {2,-12} {3}{4}' -f $state,$m.id,$m.quantization,$m.title,$suffix
}
Write-Host ''
Write-Host 'Unsupported directories found in E:\ai\models:'
foreach($u in $Cat.unsupported_detected){ '  {0} - {1}' -f $u.directory,$u.reason }
