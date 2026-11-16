"""
Configuration module for Airport Management System.
Loads database parameters and environment settings.
"""

import os
from pathlib import Path
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent.parent
ENV_PATH = BASE_DIR / ".env"

# Load .env if present
if ENV_PATH.exists():
    load_dotenv(ENV_PATH)

import urllib.parse

DB_HOST = os.getenv("DB_HOST", "localhost").strip()
DB_PORT = int(os.getenv("DB_PORT", "5432").strip().rstrip(";"))
DB_NAME = os.getenv("DB_NAME", "airport_management_system").strip().rstrip(";")
DB_USER = os.getenv("DB_USER", "postgres").strip()
_raw_pwd = os.getenv("DB_PASSWORD", "")
DB_PASSWORD = urllib.parse.unquote(_raw_pwd) if "%" in _raw_pwd else _raw_pwd
DB_SSLMODE = os.getenv("DB_SSLMODE", "prefer").strip().rstrip(";")

FRONTEND_DIR = BASE_DIR / "frontend"

OPENSKY_USERNAME = os.getenv("OPENSKY_USERNAME", "").strip()
OPENSKY_PASSWORD = os.getenv("OPENSKY_PASSWORD", "").strip()
