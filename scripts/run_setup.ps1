# ============================================================================
# Airport Management System (AMS) - PowerShell Environment & Setup Script
# ============================================================================

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " AIRPORT MANAGEMENT SYSTEM (AMS) - SETUP ASSISTANT" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Project Location: $ProjectRoot"

# 1. Detect PostgreSQL Local Installation
$PgPaths = @(
    "C:\Program Files\PostgreSQL\18\bin\psql.exe",
    "C:\Program Files\PostgreSQL\16\bin\psql.exe"
)

$PsqlExe = $null
foreach ($path in $PgPaths) {
    if (Test-Path $path) {
        $PsqlExe = $path
        break
    }
}

if ($PsqlExe) {
    Write-Host "[+] Detected local psql at: $PsqlExe" -ForegroundColor Green
} else {
    Write-Host "[i] psql executable not found in default Program Files locations." -ForegroundColor Yellow
}

# 2. Check for .env file
if (-not (Test-Path "$ProjectRoot\.env")) {
    Write-Host "[*] Creating .env from .env.example..." -ForegroundColor Yellow
    Copy-Item "$ProjectRoot\.env.example" "$ProjectRoot\.env"
    Write-Host "[!] NOTE: Edit .env with your PostgreSQL credentials when ready." -ForegroundColor Yellow
} else {
    Write-Host "[+] Found existing .env file." -ForegroundColor Green
}

# 3. Python Virtual Environment Setup
Write-Host "`n[*] Checking Python installation..." -ForegroundColor Cyan
try {
    $pythonVersion = python --version
    Write-Host "[+] Python version: $pythonVersion" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Python is not installed or not in PATH." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path "$ProjectRoot\.venv")) {
    Write-Host "[*] Creating Python virtual environment (.venv)..." -ForegroundColor Cyan
    python -m venv "$ProjectRoot\.venv"
}

$VenvPython = "$ProjectRoot\.venv\Scripts\python.exe"
$VenvPip = "$ProjectRoot\.venv\Scripts\pip.exe"

Write-Host "[*] Installing required packages in virtual environment..." -ForegroundColor Cyan
& $VenvPip install --upgrade pip --quiet
& $VenvPip install -r "$ProjectRoot\requirements.txt" --quiet
Write-Host "[+] Dependencies successfully installed." -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " SETUP COMPLETE!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "You can now run commands using the virtual environment python:"
Write-Host "  .venv\Scripts\python scripts/db_manager.py test      # Test DB connection" -ForegroundColor White
Write-Host "  .venv\Scripts\python scripts/db_manager.py all       # Migrate + Seed + Status" -ForegroundColor White
Write-Host "  .venv\Scripts\python scripts/db_manager.py status    # View live flight board" -ForegroundColor White
Write-Host "==========================================================`n"
