#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position=0)][string]$ModelId,
    [switch]$NoPrepare,
    [switch]$Detached,
    [switch]$Foreground
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if ($Detached -and $Foreground) { throw 'Нельзя одновременно -Detached и -Foreground.' }
$Root=$PSScriptRoot
$CatalogPath=Join-Path $Root 'data\personal_models.json'
$Python=$null
. (Join-Path $Root 'STRATA-MODEL-LAUNCH-COMMON.ps1')
$Python=Resolve-StrataModelPython -Root $Root
Ensure-StrataServerPythonDependencies -Root $Root -Python $Python
$Catalog=Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 64
$Model=@($Catalog.models | Where-Object { $_.id -eq $ModelId -or @($_.aliases) -contains $ModelId })
if ($Model.Count -ne 1) {
    $Ids=($Catalog.models | ForEach-Object { $_.id }) -join ', '
    throw "Неизвестный ModelId '$ModelId'. Доступны: $Ids"
}
$M=$Model[0]
$ConfigPath=Join-Path $Root ([string]$M.config)
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "Нет config: $ConfigPath" }
$Dir=[string]$M.directory
$ResolvedFiles=@($M.files | ForEach-Object { [string]$_ })
$GlobResolved=$false
$Missing=@()
foreach ($Name in $ResolvedFiles) {
    $P=Join-Path $Dir $Name
    if (-not (Test-Path -LiteralPath $P -PathType Leaf)) { $Missing += $Name }
}
# Some future/downloaded variants do not have a stable publisher filename yet.
# If exactly one completed file matches model_glob, use it without changing the catalog/config on disk.
if ($Missing.Count -gt 0 -and $ResolvedFiles.Count -eq 1 -and $M.PSObject.Properties.Name -contains 'model_glob' -and $M.model_glob) {
    $Matches=@(Get-ChildItem -LiteralPath $Dir -File -Filter ([string]$M.model_glob) -ErrorAction SilentlyContinue |
        Where-Object { -not $_.Name.EndsWith('.part',[StringComparison]::OrdinalIgnoreCase) -and -not $_.Name.StartsWith('downloading_',[StringComparison]::OrdinalIgnoreCase) })
    if ($Matches.Count -eq 1) {
        $ResolvedFiles=@($Matches[0].Name)
        $Missing=@()
        $GlobResolved=$true
        Write-Host "Resolved future model filename by model_glob: $($Matches[0].Name)" -ForegroundColor Cyan
    } elseif ($Matches.Count -gt 1) {
        throw "model_glob '$($M.model_glob)' неоднозначен: найдено $($Matches.Count) завершённых GGUF. Уточните catalog entry."
    }
}
if ($Missing.Count) {
    $Parts=@()
    if (Test-Path -LiteralPath $Dir -PathType Container) {
        $Parts=@(Get-ChildItem -LiteralPath $Dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*.part' -or $_.Name -like 'downloading_*' } | Select-Object -ExpandProperty Name)
    }
    Write-Host "Модель $ModelId ещё не готова: отсутствуют финальные GGUF:" -ForegroundColor Yellow
    $Missing | ForEach-Object { Write-Host "  $_" }
    if ($Parts.Count) {
        Write-Host 'Файлы, которые сейчас скачиваются:' -ForegroundColor Yellow
        $Parts | ForEach-Object { Write-Host "  $_" }
    }
    throw 'Дождитесь завершения скачивания. Конфиг уже готов и менять его после докачки не потребуется.'
}

# Header-only architecture validation before pack/build/start.
& $Python (Join-Path $Root 'tools\personal_model_preflight.py') --model $ModelId
if ($LASTEXITCODE -ne 0) { throw "Preflight модели $ModelId не пройден." }

$Cfg=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable -Depth 64
$Arch=[string]$M.arch
$First=Join-Path $Dir ([string]$ResolvedFiles[0])
$Pack=[string]$M.pack
# Keep the checked-in config immutable. For a future model whose exact final filename was
# learned via model_glob, make a per-run JSON copy and replace only --native in that copy.
$EffectiveConfigPath=$ConfigPath
if ($GlobResolved) {
    $RuntimeConfigDir=Join-Path $Root 'logs\personal\runtime-configs'
    New-Item -ItemType Directory -Path $RuntimeConfigDir -Force | Out-Null
    $RuntimeCfg=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable -Depth 64
    $NativeIndex=[Array]::IndexOf([object[]]$RuntimeCfg.args,'--native')
    if ($NativeIndex -lt 0 -or $NativeIndex + 1 -ge $RuntimeCfg.args.Count) { throw "В config $ConfigPath нет корректного --native." }
    $RuntimeCfg.args[$NativeIndex+1]=$First
    $EffectiveConfigPath=Join-Path $RuntimeConfigDir ("{0}-{1}.json" -f $ModelId,(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    $RuntimeCfg | ConvertTo-Json -Depth 64 | Set-Content -LiteralPath $EffectiveConfigPath -Encoding UTF8
    Write-Host "Runtime config (catalog config unchanged): $EffectiveConfigPath" -ForegroundColor DarkCyan
}
if ($Arch -eq 'qwen4exp') {
    $Engine=[string]$Cfg.exe
    if (-not (Test-Path -LiteralPath $Engine -PathType Leaf)) {
        if ($Engine -like '*engine-q6*') { throw 'Q6 engine отсутствует. Запустите .\BUILD-Q6-ENGINE.bat.' }
        throw "Engine отсутствует: $Engine"
    }
    $Tok=Join-Path $Pack 'tokenizer\vocab.json'
    if (-not (Test-Path -LiteralPath $Tok -PathType Leaf)) {
        if ($NoPrepare) { throw "Pack не подготовлен: $Pack" }
        Write-Host "Подготовка native pack: $Pack" -ForegroundColor Cyan
        & $Python (Join-Path $Root 'tools\ensure_gguf_py.py') --install-if-missing
        if ($LASTEXITCODE -ne 0) { throw 'gguf-py dependency prepare failed.' }
        if (Test-Path -LiteralPath $Pack) { throw "Неполный pack уже существует: $Pack. Автоматически не перезаписываю." }
        $Staging="$Pack.building-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path (Split-Path -Parent $Pack) -Force | Out-Null
        $Args=@((Join-Path $Root 'tools\iq_pack.py'),'--gguf',$First,'--out',$Staging)
        if ([bool]$M.pack_compat_bf16) { $Args += '--compat-bf16' }
        & $Python @Args
        if ($LASTEXITCODE -ne 0) { throw 'iq_pack.py failed.' }
        Move-Item -LiteralPath $Staging -Destination $Pack
    }
    $Mtp='E:\ai\Strata-data\mtp\rt'
    if (-not (Test-Path -LiteralPath (Join-Path $Mtp 'experts.bin') -PathType Leaf)) {
        throw "Общий Flash-Next MTP runtime отсутствует: $Mtp. Сначала подготовьте MTP обычным SETUP/существующим профилем."
    }
} elseif ($Arch -eq 'qwen35moe') {
    $Engine=[string]$Cfg.exe
    if (-not (Test-Path -LiteralPath $Engine -PathType Leaf)) {
        throw 'Qwen3.6 engine отсутствует. Сначала запустите .\BUILD-Q36-ENGINE.bat.'
    }
    $Tok=Join-Path $Pack 'tokenizer\vocab.json'
    if (-not (Test-Path -LiteralPath $Tok -PathType Leaf)) {
        if ($NoPrepare) { throw "Tokenizer pack не подготовлен: $Pack" }
        Write-Host "Извлечение tokenizer Qwen3.6 -> $Pack" -ForegroundColor Cyan
        & $Python (Join-Path $Root 'tools\ensure_gguf_py.py') --install-if-missing
        if ($LASTEXITCODE -ne 0) { throw 'gguf-py dependency prepare failed.' }
        New-Item -ItemType Directory -Path $Pack -Force | Out-Null
        & $Python (Join-Path $Root 'tools\strata_tokenizer.py') --gguf $First --out $Pack
        if ($LASTEXITCODE -ne 0) { throw 'strata_tokenizer.py failed.' }
    }
} else {
    throw "Неподдерживаемая Strata architecture: $Arch"
}
$RuntimeLogDir=Join-Path $Root 'logs\personal'
New-Item -ItemType Directory -Path $RuntimeLogDir -Force | Out-Null
$null=@(Initialize-StrataModelDlls -Root $Root -Engine $Engine -LogDirectory $RuntimeLogDir)

Assert-StrataModelServerStopped -Port ([int]$Cfg.port)
Assert-StrataModelEngineStopped -Root $Root
$Server=Join-Path $Root 'serve\server.py'
$RunArgs=@($Server,'--config',$EffectiveConfigPath)
Write-Host "Model:    $ModelId" -ForegroundColor Green
Write-Host "Config:   $EffectiveConfigPath"
Write-Host "Arch:     $Arch"
Write-Host "Parallel: $($Cfg.parallel)"
if ($Arch -eq 'qwen4exp') { Write-Host 'Defaults: pcie-frac=0.09, MTP/spec-min-p=0.9' }
else { Write-Host 'Qwen3.6: embedded MTP drafts=2 + batch-MTP; pcie/spec-min-p do not apply to qwen35moe.' }
if ($Detached) {
    Start-Process -FilePath $Python -ArgumentList $RunArgs -WorkingDirectory $Root
    Write-Host 'Server started detached.'
} else {
    & $Python @RunArgs
    exit $LASTEXITCODE
}
