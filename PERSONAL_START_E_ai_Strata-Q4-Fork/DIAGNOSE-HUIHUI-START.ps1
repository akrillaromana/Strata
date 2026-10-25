param(
    [switch]$IncludeSourceTest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = if (Test-Path -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'serve\server.py')) { (Split-Path $PSScriptRoot -Parent) } else { 'E:\ai\Strata-Q4-Fork' }
$Launcher = Join-Path $Root 'START-HUIHUI-Q4-RAM.ps1'
$Engine = Join-Path $Root 'engine\strata.exe'
$Pwsh = (Get-Command pwsh.exe -ErrorAction Stop).Source
$OutputLog = 'R:\strata-q4-runtime\strata-huihui-ud-q4_k_xl.log'
$Diagnostics = 'E:\ai\Strata-data\diagnostics'

$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = [Security.Principal.WindowsPrincipal]::new($Identity)
if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run as administrator; use DIAGNOSE-HUIHUI-START.cmd.'
}
foreach ($P in @($Launcher, $Engine)) {
    if (-not (Test-Path -LiteralPath $P -PathType Leaf)) {
        throw "Required file not found: $P"
    }
}
# Refuse expensive RAM work if the patched launcher's PowerShell syntax is invalid.
$ParseTokens = $null
$ParseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $Launcher, [ref]$ParseTokens, [ref]$ParseErrors
)
if ($ParseErrors.Count -gt 0) {
    $Messages = @($ParseErrors | ForEach-Object { $_.ToString() }) -join '; '
    throw "Huihui launcher PowerShell parser errors: $Messages"
}
Write-Host 'PowerShell 7 syntax preflight: OK.'

if (Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue) {
    throw 'Port 8080 already has a listener. Stop the current Strata server before testing.'
}

New-Item -ItemType Directory -Path $Diagnostics -Force | Out-Null
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Results = [System.Collections.Generic.List[string]]::new()
$Cases = [System.Collections.Generic.List[object]]::new()
$Cases.Add([pscustomobject]@{
    Name = 'A: physical first GGUF shard; normal native dense autodetection'
    Args = @('-ResumeRam')
})

# --native-dense-gguf may be absent on old engines; detect it BEFORE staging 46 GiB.
$SupportsExplicit = $false
try {
    $HelpText = (& $Engine --help 2>&1 | Out-String)
    $SupportsExplicit = [bool]($HelpText -match '--native-dense-gguf')
} catch {
    Write-Host "WARNING: cannot read --help: $_"
}
if ($SupportsExplicit) {
    $Cases.Add([pscustomobject]@{
        Name = 'B: physical first GGUF shard; explicit --native-dense-gguf'
        Args = @('-ResumeRam', '-ExplicitNativeDense')
    })
    if ($IncludeSourceTest) {
        $Cases.Add([pscustomobject]@{
            Name = 'C: original source first shard on E:; explicit native dense (SSD diagnostic only)'
            Args = @('-ResumeRam', '-UseSourceNative', '-ExplicitNativeDense')
        })
    }
} else {
    $Results.Add('This engine does not advertise --native-dense-gguf. B/C not applicable.')
}

Write-Host ''
Write-Host '============================================================'
Write-Host ' HUIHUI Q4 LOAD DIAGNOSTICS'
Write-Host '============================================================'
Write-Host 'Configured host: 0.0.0.0  port: 8080'
Write-Host "Explicit --native-dense-gguf supported: $SupportsExplicit"
Write-Host 'First test will COPY the 46 GiB PLE only if no complete RAM staging exists.'
Write-Host 'Later tests reuse the SAME staging, validated by exact filename and byte size.'
Write-Host 'All tests use the Huihui pack. No engine binaries or GGUF files are modified.'
Write-Host ''

$Success = $false
$SucceededIn = ''
$CaseNumber = 0
foreach ($Case in $Cases) {
    $CaseNumber++
    Write-Host ''
    Write-Host ('=' * 64)
    Write-Host "ATTEMPT $CaseNumber/$($Cases.Count): $($Case.Name)"
    Write-Host ('=' * 64)
    Write-Host ''
    # An error in the PowerShell launcher can happen BEFORE the native engine is started.
    # In that case don't save a stale engine log from a prior attempt as if it were new.
    if (Test-Path -LiteralPath $OutputLog -PathType Leaf) {
        Remove-Item -LiteralPath $OutputLog -Force -ErrorAction Stop
    }
    $Argv = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$Launcher) + @($Case.Args)
    & $Pwsh @Argv
    $RC = $LASTEXITCODE
    if ($null -eq $RC) { $RC = 1 }

    $Results.Add("$($Case.Name): exit=$RC")
    $Snapshot = Join-Path $Diagnostics ("huihui-$Stamp-attempt-$CaseNumber.log")
    if (Test-Path -LiteralPath $OutputLog) {
        Copy-Item -LiteralPath $OutputLog -Destination $Snapshot -Force
        Write-Host "Native engine log saved: $Snapshot"
    } else {
        Write-Host 'Native engine log not present at expected RAM path.'
    }
    if ($RC -eq 0) {
        $Success = $true
        $SucceededIn = $Case.Name
        break
    }
    # The previous attempt must be fully gone before the next one.
    if (Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue) {
        throw 'Port 8080 still listens after a failed attempt; refusing another launch.'
    }
}

$Summary = Join-Path $Diagnostics ("huihui-$Stamp-summary.txt")
$SummaryLines = @(
    'Huihui Q4 startup diagnostic (engine 0.1.39)',
    "when=$Stamp",
    'mode=0.0.0.0:8080',
    "explicit_dense_supported=$SupportsExplicit"
) + @($Results)
[System.IO.File]::WriteAllLines($Summary, [string[]]$SummaryLines)
Write-Host ''
Write-Host '============================================================'
Write-Host "RESULT: $(if ($Success) {'READY'} else {'ALL TESTS FAILED'})"
if ($Success) { Write-Host "Working configuration: $SucceededIn" }
Write-Host "Saved summary: $Summary"
Write-Host "Engine logs directory: $Diagnostics"
Write-Host '============================================================'
Write-Host ''
if ($Success) {
    Write-Host 'Strata is running on http://127.0.0.1:8080/v1'
    exit 0
}
Write-Host 'Do not rebuild the pack again: all tested launches used the already verified Huihui pack.'
Write-Host 'Please provide the saved summary and newest attempt log to identify the engine loader failure.'
exit 1
