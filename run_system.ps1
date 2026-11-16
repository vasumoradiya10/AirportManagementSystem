# AeroOps - Airport Management System PowerShell Launcher

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ProjectRoot

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " AERO-OPS AIRPORT MANAGEMENT SYSTEM - LAUNCHER" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Starting FastAPI Backend and Web Operations Dashboard..."

$PythonExe = Join-Path $ProjectRoot ".venv\Scripts\python.exe"

Start-Process "http://localhost:8080"
& $PythonExe -m uvicorn backend.app.main:app --host 0.0.0.0 --port 8080 --reload
