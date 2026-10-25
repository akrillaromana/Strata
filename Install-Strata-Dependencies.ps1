#requires -Version 5.1
$ErrorActionPreference = 'Stop'

# Keep this script ASCII-only so Windows PowerShell 5.1 cannot misread its source encoding.
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RequiredFiles = @('setup.py', 'requirements.txt', 'START-HERE.bat')
foreach ($Name in $RequiredFiles) {
    $Path = Join-Path $RepoRoot $Name
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing '$Name'. Save this script in the root of the Strata repository, next to setup.py and START-HERE.bat."
    }
}

$ReportDir = Join-Path $RepoRoot 'docs\reports'
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
$LogPath = Join-Path $ReportDir ("Install-Strata-Dependencies-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

function Test-PythonCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [string[]]$PrefixArgs = @()
    )
    try {
        & $Executable @PrefixArgs -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) and sys.maxsize > 2**32 else 1)' 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
}

function Find-Python {
    $Launcher = Get-Command 'py.exe' -ErrorAction SilentlyContinue
    if ($Launcher) {
        foreach ($Version in @('3.13', '3.12', '3.11', '3.10')) {
            $Prefix = @("-$Version")
            if (Test-PythonCommand -Executable $Launcher.Source -PrefixArgs $Prefix) {
                return [PSCustomObject]@{
                    Executable = $Launcher.Source
                    PrefixArgs = $Prefix
                }
            }
        }
    }

    $Candidates = @()
    foreach ($Directory in @('Python313', 'Python312', 'Python311', 'Python310')) {
        $Candidates += (Join-Path $env:LOCALAPPDATA "Programs\Python\$Directory\python.exe")
    }
    $PythonCommand = Get-Command 'python.exe' -ErrorAction SilentlyContinue
    if ($PythonCommand) {
        $Candidates += $PythonCommand.Source
    }

    foreach ($Candidate in ($Candidates | Select-Object -Unique)) {
        if ((Test-Path -LiteralPath $Candidate -PathType Leaf) -and (Test-PythonCommand -Executable $Candidate)) {
            return [PSCustomObject]@{
                Executable = $Candidate
                PrefixArgs = @()
            }
        }
    }

    return $null
}

$Failure = $null
$TranscriptStarted = $false
try {
    Start-Transcript -Path $LogPath -Force | Out-Null
    $TranscriptStarted = $true

    Write-Host '=== Strata dependency setup for Windows ===' -ForegroundColor Cyan
    Write-Host "Project directory: $RepoRoot"
    Write-Host "Log file: $LogPath"

    $Python = Find-Python
    if (-not $Python) {
        $Winget = Get-Command 'winget.exe' -ErrorAction SilentlyContinue
        if (-not $Winget) {
            throw 'Python 3.10+ (64-bit) was not found and winget is unavailable. Install 64-bit Python from https://www.python.org/downloads/ or install App Installer from Microsoft Store, then run this script again.'
        }

        Write-Host 'Python 3.10+ (64-bit) was not found. Installing Python 3.12 for the current user...' -ForegroundColor Yellow
        & $Winget.Source install --exact --id Python.Python.3.12 --scope user --silent --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity
        $WingetExitCode = $LASTEXITCODE
        $Python = Find-Python
        if (-not $Python) {
            throw "Python installation could not be confirmed (winget exit code: $WingetExitCode). Install 64-bit Python 3.12 manually and run this script again."
        }
    }

    $VenvDir = Join-Path $RepoRoot '.venv'
    $VenvPython = Join-Path $VenvDir 'Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $VenvPython -PathType Leaf)) {
        Write-Host 'Creating isolated Python environment .venv...'
        $PythonArgs = @($Python.PrefixArgs)
        & $Python.Executable @PythonArgs -m venv $VenvDir
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $VenvPython -PathType Leaf)) {
            throw 'Could not create .venv. Check the Python installation and write permissions for the project directory.'
        }
    }
    else {
        Write-Host 'Using the existing .venv environment.'
    }

    if (-not (Test-PythonCommand -Executable $VenvPython)) {
        throw 'The Python interpreter in .venv is not a working 64-bit Python 3.10+ installation. Inspect .venv manually before running setup again.'
    }

    Write-Host 'Upgrading pip in .venv...'
    & $VenvPython -m pip install --upgrade pip
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not upgrade pip.'
    }

    $Requirements = Join-Path $RepoRoot 'requirements.txt'
    Write-Host 'Installing the pinned dependencies from requirements.txt...'
    & $VenvPython -m pip install --disable-pip-version-check -r $Requirements
    if ($LASTEXITCODE -ne 0) {
        throw 'pip could not install all dependencies listed in requirements.txt.'
    }

    Write-Host 'Checking required Python module imports...'
    # jsonschema is intentionally not checked here: it is not listed in this repository requirements file.
    & $VenvPython -c 'import numpy, jinja2, regex, yaml, tqdm, requests, PIL, psutil; print("Required module imports succeeded.")'
    if ($LASTEXITCODE -ne 0) {
        throw 'One or more required Python module imports failed.'
    }

    Write-Host 'Checking dependency consistency...'
    & $VenvPython -m pip check
    if ($LASTEXITCODE -ne 0) {
        throw 'pip check reported dependency conflicts.'
    }

    Write-Host ''
    Write-Host 'Base Python dependencies are installed.' -ForegroundColor Green
    Write-Host 'Next step: run START-HERE.bat from this project directory. It will configure the engine and required GPU libraries for your hardware.'
    Write-Host "Installation log: $LogPath"
}
catch {
    $Failure = $_
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Review the log file if it was created: $LogPath" -ForegroundColor Yellow
}
finally {
    if ($TranscriptStarted) {
        try {
            Stop-Transcript | Out-Null
        }
        catch {
            # Keep logging failures from hiding the original installation error.
        }
    }
}

if ($Failure) {
    exit 1
}
