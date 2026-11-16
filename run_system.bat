@echo off
TITLE AeroOps - Airport Management System
cd /d "%~dp0"

echo ==========================================================
echo  AERO-OPS AIRPORT MANAGEMENT SYSTEM - SYSTEM LAUNCHER
echo ==========================================================
echo Starting FastAPI Backend and Web Operations Dashboard...

REM Launch default web browser after 2 seconds in background
start "" cmd /c "timeout /t 2 /nobreak >nul & start http://localhost:8080"

REM Run Uvicorn server using the created virtual environment
".venv\Scripts\python.exe" -m uvicorn backend.app.main:app --host 0.0.0.0 --port 8080 --reload

pause
