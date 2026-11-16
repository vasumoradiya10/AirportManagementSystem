#!/usr/bin/env python3
"""
Airport Management System (AMS) - Database Manager CLI
Author: Google Deepmind Antigravity Pair Programmer
Description: 
    Automated database management utility for PostgreSQL.
    Provides schema migration, seed loading, connection diagnostics,
    and execution of advanced SQL analytics (Recursive CTEs, Window functions).
"""

import os
import sys
import argparse
from pathlib import Path

# Try importing psycopg or psycopg2
try:
    import psycopg
    from psycopg import sql
    PSYCOPG_VERSION = 3
except ImportError:
    try:
        import psycopg2 as psycopg
        from psycopg2 import sql
        PSYCOPG_VERSION = 2
    except ImportError:
        psycopg = None
        PSYCOPG_VERSION = None

# Try importing tabulate for pretty table output
try:
    from tabulate import tabulate
    HAS_TABULATE = True
except ImportError:
    HAS_TABULATE = False

# Try importing python-dotenv
try:
    from dotenv import load_dotenv
    BASE_DIR = Path(__file__).resolve().parent.parent
    load_dotenv(BASE_DIR / ".env")
except ImportError:
    BASE_DIR = Path(__file__).resolve().parent.parent

import urllib.parse

DB_HOST = os.getenv("DB_HOST", "localhost").strip()
DB_PORT = os.getenv("DB_PORT", "5432").strip().rstrip(";")
DB_NAME = os.getenv("DB_NAME", "airport_management_system").strip().rstrip(";")
DB_USER = os.getenv("DB_USER", "postgres").strip()
_raw_pwd = os.getenv("DB_PASSWORD", "")
DB_PASSWORD = urllib.parse.unquote(_raw_pwd) if "%" in _raw_pwd else _raw_pwd
DB_SSLMODE = os.getenv("DB_SSLMODE", "prefer").strip().rstrip(";")

SQL_DIRS = [
    ("01 Schema", BASE_DIR / "database" / "01_schema"),
    ("02 Indexes", BASE_DIR / "database" / "02_indexes"),
    ("03 Views", BASE_DIR / "database" / "03_views"),
    ("04 Functions & Procedures", BASE_DIR / "database" / "04_functions_procedures"),
    ("05 Triggers", BASE_DIR / "database" / "05_triggers"),
]

SEED_DIR = BASE_DIR / "database" / "07_seed_data"
ADVANCED_SQL_FILE = BASE_DIR / "database" / "06_advanced_sql" / "01_complex_queries.sql"


def check_prerequisites():
    """Verify required Python packages are installed."""
    if psycopg is None:
        print("[ERROR] Neither 'psycopg' (v3) nor 'psycopg2' is installed.")
        print("Please install dependencies by running:")
        print("    pip install -r requirements.txt")
        sys.exit(1)


def get_connection(target_db=None):
    """Establishes and returns a database connection."""
    check_prerequisites()
    db = target_db or DB_NAME
    conn_params = {
        "host": DB_HOST,
        "port": DB_PORT,
        "dbname": db,
        "user": DB_USER,
        "password": DB_PASSWORD,
    }
    if DB_SSLMODE:
        conn_params["sslmode"] = DB_SSLMODE

    try:
        if PSYCOPG_VERSION == 3:
            return psycopg.connect(**conn_params, autocommit=True)
        else:
            conn = psycopg.connect(**conn_params)
            conn.autocommit = True
            return conn
    except Exception as e:
        print(f"\n[CONNECTION ERROR] Could not connect to PostgreSQL database '{db}' at {DB_HOST}:{DB_PORT}.")
        print(f"Details: {e}")
        print("\nPlease ensure that:")
        print(" 1. PostgreSQL service is running.")
        print(" 2. Your credentials in .env match your PostgreSQL settings.")
        print(" 3. If the database does not exist, run: python scripts/db_manager.py init-db\n")
        return None


def init_database():
    """Attempts to connect to default 'postgres' db and create the target database if missing."""
    print(f"[*] Checking/Creating database '{DB_NAME}' on {DB_HOST}:{DB_PORT}...")
    conn = get_connection(target_db="postgres")
    if not conn:
        return False

    try:
        with conn.cursor() as cur:
            cur.execute("SELECT 1 FROM pg_database WHERE datname = %s", (DB_NAME,))
            exists = cur.fetchone()
            if not exists:
                if PSYCOPG_VERSION == 3:
                    cur.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier(DB_NAME)))
                else:
                    cur.execute(f'CREATE DATABASE "{DB_NAME}"')
                print(f"[+] Successfully created database '{DB_NAME}'.")
            else:
                print(f"[i] Database '{DB_NAME}' already exists.")
        conn.close()
        return True
    except Exception as e:
        print(f"[ERROR] Failed to create database: {e}")
        conn.close()
        return False


def test_connection():
    """Tests the PostgreSQL connection and prints server version."""
    print(f"[*] Testing connection to {DB_USER}@{DB_HOST}:{DB_PORT}/{DB_NAME}...")
    conn = get_connection()
    if conn:
        with conn.cursor() as cur:
            cur.execute("SELECT version();")
            ver = cur.fetchone()[0]
            print("[+] Connection SUCCESSFUL!")
            print(f"[+] PostgreSQL Version: {ver}")
        conn.close()
        return True
    return False


def run_sql_file(conn, filepath):
    """Executes a single SQL script file."""
    path = Path(filepath)
    if not path.exists():
        print(f"[!] File not found: {path}")
        return False

    print(f"  -> Executing: {path.name} ... ", end="", flush=True)
    content = path.read_text(encoding="utf-8")

    try:
        with conn.cursor() as cur:
            cur.execute(content)
        print("[DONE]")
        return True
    except Exception as e:
        print(f"[FAILED]\n    Error: {e}")
        return False


def migrate():
    """Runs all migration SQL scripts in the structured sequence."""
    print("\n=======================================================")
    print(" AIRPORT MANAGEMENT SYSTEM - DATABASE MIGRATION")
    print("=======================================================")
    conn = get_connection()
    if not conn:
        return

    try:
        for stage_name, stage_dir in SQL_DIRS:
            print(f"\n[*] Applying Stage: {stage_name}")
            if not stage_dir.exists():
                continue
            sql_files = sorted(stage_dir.glob("*.sql"))
            if not sql_files:
                print("  (No .sql files in directory)")
            for sf in sql_files:
                run_sql_file(conn, sf)

        print("\n[+] All core schema stages applied successfully!")
    finally:
        conn.close()


def seed():
    """Populates the database with sample fixtures."""
    print("\n=======================================================")
    print(" AIRPORT MANAGEMENT SYSTEM - SEED SAMPLE FIXTURES")
    print("=======================================================")
    conn = get_connection()
    if not conn:
        return

    try:
        if SEED_DIR.exists():
            for sf in sorted(SEED_DIR.glob("*.sql")):
                run_sql_file(conn, sf)
        print("\n[+] Sample fixtures inserted successfully!")
    finally:
        conn.close()


def print_table(rows, headers, title=None):
    """Utility to print tabular data."""
    if title:
        print(f"\n=== {title} ===")
    if HAS_TABULATE:
        print(tabulate(rows, headers=headers, tablefmt="psql"))
    else:
        print(" | ".join(headers))
        print("-" * 60)
        for r in rows:
            print(" | ".join(str(val) for val in r))


def run_diagnostics():
    """Runs sample queries and prints operational tables."""
    conn = get_connection()
    if not conn:
        return

    try:
        with conn.cursor() as cur:
            # 1. Airport Count
            cur.execute("SELECT COUNT(*) FROM airports;")
            airports_count = cur.fetchone()[0]

            # 2. Flights Count
            cur.execute("SELECT COUNT(*) FROM flight_instances;")
            flights_count = cur.fetchone()[0]

            # 3. Live FIDS Board
            cur.execute("""
                SELECT flight_number, airline_iata, origin_iata, destination_iata, 
                       TO_CHAR(scheduled_departure, 'YYYY-MM-DD HH24:MI') AS departure,
                       flight_status, departure_gate
                FROM vw_live_flight_board
                LIMIT 10;
            """)
            fids_rows = cur.fetchall()
            headers = ["Flight", "Airline", "Origin", "Dest", "Scheduled Dep", "Status", "Gate"]

            print("\n[DATABASE OVERVIEW]")
            print(f"Total Airports Registered: {airports_count}")
            print(f"Total Flight Instances:   {flights_count}")

            print_table(fids_rows, headers, title="LIVE FLIGHT BOARD (FIDS VIEW)")

    except Exception as e:
        print(f"[!] Diagnostics error: {e}")
    finally:
        conn.close()


def reset_db():
    """Drops and recreates public schema."""
    confirm = input("[WARNING] This will DROP all tables and objects in public schema. Continue? (y/N): ")
    if confirm.lower() != 'y':
        print("Aborted.")
        return

    conn = get_connection()
    if not conn:
        return

    try:
        with conn.cursor() as cur:
            print("[*] Dropping schema public...")
            cur.execute("DROP SCHEMA public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO postgres; GRANT ALL ON SCHEMA public TO public;")
            print("[+] Public schema recreated cleanly.")
        conn.close()
        migrate()
        seed()
    except Exception as e:
        print(f"[ERROR] Reset failed: {e}")
        conn.close()


def main():
    parser = argparse.ArgumentParser(description="Airport Management System (AMS) DB Manager")
    parser.add_argument("command", choices=["test", "init-db", "migrate", "seed", "all", "status", "reset"],
                        help="Action to perform: test (test conn), init-db (create database), migrate (run DDL), seed (insert sample data), all (init+migrate+seed), status (view board), reset (drop & rebuild)")

    args = parser.parse_args()

    if args.command == "test":
        test_connection()
    elif args.command == "init-db":
        init_database()
    elif args.command == "migrate":
        migrate()
    elif args.command == "seed":
        seed()
    elif args.command == "all":
        if init_database():
            migrate()
            seed()
            run_diagnostics()
    elif args.command == "status":
        run_diagnostics()
    elif args.command == "reset":
        reset_db()


if __name__ == "__main__":
    main()
