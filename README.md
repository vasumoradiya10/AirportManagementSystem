# ✈️ Airport Management System (PostgreSQL & Advanced SQL)

A modern, production-grade **Airport Management System (AMS)** database architecture built with **PostgreSQL 14+ / 16+** and **Advanced SQL** capabilities.

Designed to manage core airport operations, including flight scheduling, gate allocations, passenger bookings, real-time flight information displays (FIDS), baggage tracking, and aircraft maintenance intervals.

---

## 🌟 Highlights & Advanced SQL Features

- **ACID Transaction Management**: Row-level locking (`SELECT ... FOR UPDATE`) in stored procedures prevents race conditions in seat reservations and gate assignments.
- **Recursive CTEs**: Multi-leg connecting flight itinerary engine calculating flight times, valid connection windows (90 mins to 8 hours), and layover durations.
- **Analytical Window Functions**:
  - `LAG()` and `LEAD()` to track turnaround times on the tarmac for each aircraft.
  - `SUM() OVER (...)` and `DENSE_RANK()` for cumulative route revenues and airline performance ratings.
- **Materialized Views**: `mv_airline_performance` with concurrent refresh procedures (`REFRESH MATERIALIZED VIEW CONCURRENTLY`).
- **Automated Triggers**:
  - Physical gate collision prevention.
  - Real-time audit trail logging for all flight status transitions.
  - Baggage weight limits enforced against aircraft cargo limits.
  - Automatic flight hours tallying upon arrival.
- **Table Partitioning & Row-Level Security (RLS)**: Patterns for high-volume flight history and multi-tenant airline isolation.

---

## 📁 Repository Structure

```text
AirportManagementSystem/
├── .env.example                         # Database configuration template
├── requirements.txt                     # Python packages (psycopg, tabulate, etc.)
├── README.md                            # Project documentation
├── database/
│   ├── 01_schema/
│   │   └── 01_core_tables.sql           # Core tables, ENUMs, primary/foreign keys
│   ├── 02_indexes/
│   │   └── 01_performance_indexes.sql   # B-Tree, partial, and composite indexes
│   ├── 03_views/
│   │   └── 01_operational_views.sql     # Live FIDS board, gate status, manifest
│   ├── 04_functions_procedures/
│   │   └── 01_stored_procedures.sql     # Stored procedures & Haversine distance
│   ├── 05_triggers/
│   │   └── 01_business_triggers.sql     # Business rules & audit log triggers
│   ├── 06_advanced_sql/
│   │   └── 01_complex_queries.sql       # Recursive CTEs, Windowing, RLS, Partitioning
│   └── 07_seed_data/
│       └── 01_sample_data.sql           # Realistic international flight fixtures
├── scripts/
│   ├── db_manager.py                    # Complete CLI for DB migrations & queries
│   └── run_setup.ps1                    # PowerShell setup script for Windows
└── docs/
    └── SCHEMA_GUIDE.md                  # Integration & custom schema guide
```

---

## 🚀 Quick Start Guide

### 1. Configure Credentials
Copy `.env.example` to `.env`:
```powershell
Copy-Item .env.example .env
```
Open `.env` and fill in your PostgreSQL credentials:
```ini
DB_HOST=localhost
DB_PORT=5432
DB_NAME=airport_management_db
DB_USER=postgres
DB_PASSWORD=your_password
```

### 2. Automatic Windows Setup (PowerShell)
Run the setup script to initialize a virtual environment and dependencies:
```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_setup.ps1
```

### 3. Run Database Migrations & Diagnostics
Using the Python Database Manager:
```powershell
# Test connection
python scripts/db_manager.py test

# Create database (if not existing), migrate schema, insert fixtures, and display FIDS
python scripts/db_manager.py all

# View live flight board status at any time
python scripts/db_manager.py status
```

---

## 🛩️ Core Data Model Entities

- **Infrastructure**: `airports`, `terminals`, `gates`, `runways`
- **Fleet & Operations**: `airlines`, `aircraft_models`, `aircraft`, `flight_routes`, `flight_instances`
- **Passenger Services**: `passengers`, `bookings`, `boarding_passes`, `baggage`, `baggage_tracking_events`
- **Personnel & Auditing**: `crew_members`, `flight_crew_assignments`, `flight_status_audit`, `gate_occupancy_log`
