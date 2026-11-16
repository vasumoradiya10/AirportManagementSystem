# Airport Management System (AMS) - Database & Schema Integration Guide

Welcome to the **Airport Management System (AMS)** database project. This guide explains the database structure, how to connect your PostgreSQL instance, and how to incorporate your custom schema when you are ready.

---

## 1. Directory Overview

```text
AirportManagementSystem/
├── .env.example                       <- Template for PostgreSQL connection credentials
├── .env                               <- Your private credentials (host, port, user, password)
├── requirements.txt                   <- Python database runner dependencies
├── README.md                          <- Main project documentation
├── database/
│   ├── 01_schema/                     <- Core tables, ENUM types, and constraints
│   │   └── 01_core_tables.sql
│   ├── 02_indexes/                    <- Performance indexes (B-Tree, partial, composite)
│   │   └── 01_performance_indexes.sql
│   ├── 03_views/                      <- Live FIDS board, gate status, materialized views
│   │   └── 01_operational_views.sql
│   ├── 04_functions_procedures/       <- Transactional procedures & PL/pgSQL functions
│   │   └── 01_stored_procedures.sql
│   ├── 05_triggers/                   <- Business rules & audit log triggers
│   │   └── 01_business_triggers.sql
│   ├── 06_advanced_sql/               <- Recursive CTEs, window analytics, partitioning, RLS
│   │   └── 01_complex_queries.sql
│   └── 07_seed_data/                  <- Realistic test data (airports, flights, bookings)
│       └── 01_sample_data.sql
├── scripts/
│   ├── db_manager.py                  <- Python CLI to migrate, seed, and run queries
│   └── run_setup.ps1                  <- PowerShell setup helper for Windows
└── docs/
    └── SCHEMA_GUIDE.md                <- This guide
```

---

## 2. Setting Up Database Credentials

1. Open `.env` (or copy `.env.example` to `.env`):
   ```ini
   DB_HOST=localhost            # Or your cloud host: e.g. db.xxx.supabase.co
   DB_PORT=5432
   DB_NAME=airport_management_db
   DB_USER=postgres
   DB_PASSWORD=your_actual_password
   DB_SSLMODE=prefer            # Use 'require' for cloud databases (Supabase, Neon, RDS)
   ```
2. Test connection using the database manager:
   ```powershell
   python scripts/db_manager.py test
   ```

---

## 3. How to Share or Integrate Your Schema

When you share your database schema, you have two flexible options:

### Option A: Replace or Extend the Base Tables
- Place your DDL SQL file directly into `database/01_schema/` (e.g. `02_custom_schema.sql`).
- Any new tables or modified column names can be mapped directly into the views and procedures.

### Option B: Send the Schema in Chat
- Simply paste your schema, CREATE TABLE statements, or table diagrams directly in the chat with Antigravity.
- Antigravity will automatically adapt the procedures, triggers, recursive CTEs, and views to match your exact column and table names!

---

## 4. Advanced SQL Capabilities Included

1. **Transactional Stored Procedures (`database/04_functions_procedures/`)**:
   - `sp_assign_flight_gate()`: Validates aircraft size and ensures gate non-overlap with concurrency locks.
   - `sp_process_seat_reservation()`: ACID-compliant seat booking using `SELECT ... FOR UPDATE` row locks, preventing double bookings.
   - `sp_handle_flight_delay()`: Cascading delay recalculation and notification logging.

2. **Automated Business Triggers (`database/05_triggers/`)**:
   - `trg_gate_non_collision`: Blocks overlapping gate assignments at database level.
   - `trg_flight_status_audit`: Automatically captures all status and delay history into `flight_status_audit`.
   - `trg_validate_baggage_weight`: Verifies that adding a luggage item will not exceed the aircraft's max cargo capacity.
   - `trg_update_flight_hours`: Automatically computes and adds airborne flight hours to aircraft records upon arrival.

3. **Advanced Analytics & Recursive Queries (`database/06_advanced_sql/`)**:
   - **Recursive CTE**: Multi-hop itinerary search between any two airports, respecting minimum layover intervals (e.g. 90m to 8h).
   - **Window Functions**:
     - `LAG()`: Computes ground turnaround time between consecutive flights on the same aircraft.
     - `SUM() OVER (PARTITION BY ... ORDER BY ...)`: Running cumulative revenue per airline.
     - `DENSE_RANK()`: Route revenue performance rankings.
   - **Row-Level Security (RLS)**: Airline tenant data isolation policies.
   - **Range Table Partitioning**: High-volume telemetry and flight tracking partitioning pattern.

---

## 5. Running the Pipeline

You can run the entire workflow with a single command once your `.env` credentials are saved:

```powershell
# Initialize DB, apply migrations, seed sample fixtures, and display live flight board
python scripts/db_manager.py all
```
