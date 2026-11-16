-- ============================================================================
-- AIRPORT MANAGEMENT SYSTEM (AMS) - CORE DATABASE SCHEMA
-- PostgreSQL 14+ / 16+ Compatible
-- Description: Core tables, ENUM types, primary keys, foreign keys & constraints
-- ============================================================================

-- Create Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- ============================================================================
-- 1. ENUMS
-- ============================================================================

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'flight_status_enum') THEN
        CREATE TYPE flight_status_enum AS ENUM (
            'SCHEDULED', 'BOARDING', 'GATE_CLOSED', 'DEPARTED', 
            'AIRBORNE', 'LANDED', 'ARRIVED', 'DELAYED', 'CANCELLED', 'DIVERTED'
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'seat_class_enum') THEN
        CREATE TYPE seat_class_enum AS ENUM (
            'ECONOMY', 'PREMIUM_ECONOMY', 'BUSINESS', 'FIRST'
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'booking_status_enum') THEN
        CREATE TYPE booking_status_enum AS ENUM (
            'CONFIRMED', 'CHECKED_IN', 'BOARDED', 'CANCELLED', 'NO_SHOW'
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'baggage_status_enum') THEN
        CREATE TYPE baggage_status_enum AS ENUM (
            'CHECKED_IN', 'SECURITY_CLEARED', 'LOADED', 'IN_TRANSIT', 
            'TRANSFERRED', 'UNLOADED', 'BAGGAGE_CLAIM', 'CLAIMED', 'LOST'
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'gate_status_enum') THEN
        CREATE TYPE gate_status_enum AS ENUM (
            'AVAILABLE', 'OCCUPIED', 'RESERVED', 'MAINTENANCE', 'CLOSED'
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'crew_role_enum') THEN
        CREATE TYPE crew_role_enum AS ENUM (
            'CAPTAIN', 'FIRST_OFFICER', 'FLIGHT_ENGINEER', 'PURSER', 'FLIGHT_ATTENDANT'
        );
    END IF;
END $$;

-- ============================================================================
-- 2. AIRPORT & INFRASTRUCTURE TABLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS airports (
    airport_id              SERIAL PRIMARY KEY,
    iata_code               CHAR(3) NOT NULL UNIQUE,
    icao_code               CHAR(4) NOT NULL UNIQUE,
    name                    VARCHAR(150) NOT NULL,
    city                    VARCHAR(100) NOT NULL,
    country                 VARCHAR(100) NOT NULL,
    latitude                NUMERIC(9, 6) NOT NULL,
    longitude               NUMERIC(9, 6) NOT NULL,
    elevation_ft            INTEGER DEFAULT 0,
    timezone                VARCHAR(50) NOT NULL DEFAULT 'UTC',
    is_international        BOOLEAN DEFAULT TRUE,
    created_at              TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_iata_uppercase CHECK (iata_code = UPPER(iata_code)),
    CONSTRAINT chk_icao_uppercase CHECK (icao_code = UPPER(icao_code))
);

CREATE TABLE IF NOT EXISTS terminals (
    terminal_id             SERIAL PRIMARY KEY,
    airport_id              INTEGER NOT NULL REFERENCES airports(airport_id) ON DELETE CASCADE,
    terminal_code           VARCHAR(10) NOT NULL,
    name                    VARCHAR(100) NOT NULL,
    total_gates             INTEGER NOT NULL DEFAULT 0,
    is_international        BOOLEAN DEFAULT TRUE,
    CONSTRAINT uq_airport_terminal UNIQUE (airport_id, terminal_code)
);

CREATE TABLE IF NOT EXISTS gates (
    gate_id                 SERIAL PRIMARY KEY,
    terminal_id             INTEGER NOT NULL REFERENCES terminals(terminal_id) ON DELETE CASCADE,
    gate_number             VARCHAR(10) NOT NULL,
    gate_type               VARCHAR(30) DEFAULT 'NARROW_BODY' 
                            CHECK (gate_type IN ('NARROW_BODY', 'WIDE_BODY', 'REGIONAL', 'HEAVY')),
    status                  gate_status_enum NOT NULL DEFAULT 'AVAILABLE',
    is_jetbridge_equipped   BOOLEAN DEFAULT TRUE,
    CONSTRAINT uq_terminal_gate UNIQUE (terminal_id, gate_number)
);

CREATE TABLE IF NOT EXISTS runways (
    runway_id               SERIAL PRIMARY KEY,
    airport_id              INTEGER NOT NULL REFERENCES airports(airport_id) ON DELETE CASCADE,
    runway_identifier       VARCHAR(10) NOT NULL, -- e.g., '09L/27R'
    length_meters           NUMERIC(7, 2) NOT NULL,
    width_meters            NUMERIC(6, 2) NOT NULL,
    surface_type            VARCHAR(50) DEFAULT 'ASPHALT',
    is_active               BOOLEAN DEFAULT TRUE,
    CONSTRAINT uq_airport_runway UNIQUE (airport_id, runway_identifier)
);

-- ============================================================================
-- 3. AIRLINES & FLEET TABLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS airlines (
    airline_id              SERIAL PRIMARY KEY,
    iata_code               CHAR(2) NOT NULL UNIQUE,
    icao_code               CHAR(3) NOT NULL UNIQUE,
    name                    VARCHAR(100) NOT NULL,
    callsign                VARCHAR(50),
    country                 VARCHAR(100) NOT NULL,
    headquarters            VARCHAR(150),
    is_active               BOOLEAN DEFAULT TRUE,
    created_at              TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS aircraft_models (
    model_code              VARCHAR(20) PRIMARY KEY, -- e.g., 'B777-300ER', 'A350-900', 'A320neo'
    manufacturer            VARCHAR(100) NOT NULL,   -- Boeing, Airbus, Embraer
    model_name              VARCHAR(100) NOT NULL,
    max_passenger_capacity  INTEGER NOT NULL CHECK (max_passenger_capacity > 0),
    max_cargo_capacity_kg   NUMERIC(10, 2) NOT NULL CHECK (max_cargo_capacity_kg > 0),
    max_range_km            INTEGER NOT NULL,
    cruising_speed_kmh      INTEGER NOT NULL,
    required_runway_meters  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS aircraft (
    aircraft_id             SERIAL PRIMARY KEY,
    registration_number     VARCHAR(20) NOT NULL UNIQUE, -- Tail number e.g., 'N123AA', 'VT-EXG'
    airline_id              INTEGER NOT NULL REFERENCES airlines(airline_id) ON DELETE RESTRICT,
    model_code              VARCHAR(20) NOT NULL REFERENCES aircraft_models(model_code) ON DELETE RESTRICT,
    manufacture_date        DATE NOT NULL,
    last_maintenance_date   DATE,
    next_maintenance_due    DATE,
    total_flight_hours      NUMERIC(9, 2) DEFAULT 0.00,
    is_airworthy            BOOLEAN DEFAULT TRUE,
    created_at              TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- 4. ROUTES & FLIGHT OPERATIONS TABLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS flight_routes (
    route_id                SERIAL PRIMARY KEY,
    airline_id              INTEGER NOT NULL REFERENCES airlines(airline_id) ON DELETE RESTRICT,
    flight_number           VARCHAR(10) NOT NULL, -- e.g., 'AA100', 'AI101'
    origin_airport_id       INTEGER NOT NULL REFERENCES airports(airport_id) ON DELETE RESTRICT,
    destination_airport_id  INTEGER NOT NULL REFERENCES airports(airport_id) ON DELETE RESTRICT,
    scheduled_duration_mins INTEGER NOT NULL CHECK (scheduled_duration_mins > 0),
    distance_km             INTEGER NOT NULL CHECK (distance_km > 0),
    is_active               BOOLEAN DEFAULT TRUE,
    CONSTRAINT uq_airline_flight_number UNIQUE (airline_id, flight_number),
    CONSTRAINT chk_route_airports_differ CHECK (origin_airport_id <> destination_airport_id)
);

CREATE TABLE IF NOT EXISTS flight_instances (
    flight_instance_id      BIGSERIAL PRIMARY KEY,
    route_id                INTEGER NOT NULL REFERENCES flight_routes(route_id) ON DELETE RESTRICT,
    aircraft_id             INTEGER REFERENCES aircraft(aircraft_id) ON DELETE SET NULL,
    departure_gate_id       INTEGER REFERENCES gates(gate_id) ON DELETE SET NULL,
    arrival_gate_id         INTEGER REFERENCES gates(gate_id) ON DELETE SET NULL,
    scheduled_departure     TIMESTAMPTZ NOT NULL,
    scheduled_arrival       TIMESTAMPTZ NOT NULL,
    actual_departure        TIMESTAMPTZ,
    actual_arrival          TIMESTAMPTZ,
    status                  flight_status_enum NOT NULL DEFAULT 'SCHEDULED',
    delay_minutes           INTEGER DEFAULT 0,
    delay_reason            TEXT,
    created_at              TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_sched_arrival_after_departure CHECK (scheduled_arrival > scheduled_departure)
);

-- ============================================================================
-- 5. PASSENGERS, BOOKINGS & BOARDING
-- ============================================================================

CREATE TABLE IF NOT EXISTS passengers (
    passenger_id            BIGSERIAL PRIMARY KEY,
    first_name              VARCHAR(60) NOT NULL,
    last_name               VARCHAR(60) NOT NULL,
    passport_number         VARCHAR(50) NOT NULL UNIQUE,
    nationality             VARCHAR(60) NOT NULL,
    date_of_birth           DATE NOT NULL,
    email                   VARCHAR(120) NOT NULL,
    phone_number            VARCHAR(30),
    frequent_flyer_number   VARCHAR(50),
    created_at              TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS bookings (
    booking_id              BIGSERIAL PRIMARY KEY,
    booking_reference       CHAR(6) NOT NULL UNIQUE, -- PNR format e.g., 'X8KJ2Q'
    flight_instance_id      BIGINT NOT NULL REFERENCES flight_instances(flight_instance_id) ON DELETE CASCADE,
    passenger_id            BIGINT NOT NULL REFERENCES passengers(passenger_id) ON DELETE RESTRICT,
    seat_number             VARCHAR(5) NOT NULL, -- e.g., '14A', '01F'
    seat_class              seat_class_enum NOT NULL DEFAULT 'ECONOMY',
    ticket_price            NUMERIC(10, 2) NOT NULL CHECK (ticket_price >= 0),
    booking_status          booking_status_enum NOT NULL DEFAULT 'CONFIRMED',
    booked_at               TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_flight_seat UNIQUE (flight_instance_id, seat_number),
    CONSTRAINT uq_flight_passenger UNIQUE (flight_instance_id, passenger_id)
);

CREATE TABLE IF NOT EXISTS boarding_passes (
    pass_id                 BIGSERIAL PRIMARY KEY,
    booking_id              BIGINT NOT NULL UNIQUE REFERENCES bookings(booking_id) ON DELETE CASCADE,
    barcode_token           VARCHAR(128) NOT NULL UNIQUE,
    boarding_group          VARCHAR(5) NOT NULL DEFAULT 'GRP3',
    issued_at               TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    is_boarded              BOOLEAN DEFAULT FALSE,
    boarded_at              TIMESTAMPTZ
);

-- ============================================================================
-- 6. BAGGAGE & TRACKING
-- ============================================================================

CREATE TABLE IF NOT EXISTS baggage (
    baggage_id              BIGSERIAL PRIMARY KEY,
    tag_number              VARCHAR(30) NOT NULL UNIQUE, -- e.g., 'BAG-2026-98174'
    booking_id              BIGINT NOT NULL REFERENCES bookings(booking_id) ON DELETE CASCADE,
    flight_instance_id      BIGINT NOT NULL REFERENCES flight_instances(flight_instance_id) ON DELETE CASCADE,
    weight_kg               NUMERIC(5, 2) NOT NULL CHECK (weight_kg > 0 AND weight_kg <= 100.00),
    status                  baggage_status_enum NOT NULL DEFAULT 'CHECKED_IN',
    is_oversized            BOOLEAN DEFAULT FALSE,
    is_fragile              BOOLEAN DEFAULT FALSE,
    created_at              TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS baggage_tracking_events (
    event_id                BIGSERIAL PRIMARY KEY,
    baggage_id              BIGINT NOT NULL REFERENCES baggage(baggage_id) ON DELETE CASCADE,
    event_status            baggage_status_enum NOT NULL,
    checkpoint_location     VARCHAR(100) NOT NULL, -- e.g., 'Terminal 1 Belt 3', 'Ramp Loading Bay 4'
    scanned_by              VARCHAR(100) DEFAULT 'Automated Scanner',
    scanned_at              TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    remarks                 TEXT
);

-- ============================================================================
-- 7. CREW & ASSIGNMENTS
-- ============================================================================

CREATE TABLE IF NOT EXISTS crew_members (
    crew_id                 SERIAL PRIMARY KEY,
    airline_id              INTEGER NOT NULL REFERENCES airlines(airline_id) ON DELETE CASCADE,
    first_name              VARCHAR(60) NOT NULL,
    last_name               VARCHAR(60) NOT NULL,
    role                    crew_role_enum NOT NULL,
    license_number          VARCHAR(50) NOT NULL UNIQUE,
    total_flight_hours      INTEGER DEFAULT 0,
    is_active               BOOLEAN DEFAULT TRUE,
    created_at              TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS flight_crew_assignments (
    assignment_id           BIGSERIAL PRIMARY KEY,
    flight_instance_id      BIGINT NOT NULL REFERENCES flight_instances(flight_instance_id) ON DELETE CASCADE,
    crew_id                 INTEGER NOT NULL REFERENCES crew_members(crew_id) ON DELETE CASCADE,
    duty_role               crew_role_enum NOT NULL,
    assigned_at             TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_flight_crew_member UNIQUE (flight_instance_id, crew_id)
);

-- ============================================================================
-- 8. AUDIT TRAILS & EVENT LOGGING
-- ============================================================================

CREATE TABLE IF NOT EXISTS flight_status_audit (
    audit_id                BIGSERIAL PRIMARY KEY,
    flight_instance_id      BIGINT NOT NULL REFERENCES flight_instances(flight_instance_id) ON DELETE CASCADE,
    old_status              flight_status_enum,
    new_status              flight_status_enum NOT NULL,
    delay_minutes           INTEGER DEFAULT 0,
    changed_by              VARCHAR(100) DEFAULT CURRENT_USER,
    change_reason           TEXT,
    changed_at              TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS gate_occupancy_log (
    log_id                  BIGSERIAL PRIMARY KEY,
    gate_id                 INTEGER NOT NULL REFERENCES gates(gate_id) ON DELETE CASCADE,
    flight_instance_id      BIGINT NOT NULL REFERENCES flight_instances(flight_instance_id) ON DELETE CASCADE,
    occupied_from           TIMESTAMPTZ NOT NULL,
    occupied_until          TIMESTAMPTZ,
    status                  gate_status_enum NOT NULL,
    created_at              TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);
