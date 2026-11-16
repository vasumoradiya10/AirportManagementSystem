-- ============================================================================
-- AIRPORT MANAGEMENT SYSTEM (AMS) - PERFORMANCE INDEXES
-- PostgreSQL 14+ / 16+ Compatible
-- Description: B-Tree, Composite, and Partial Indexes for high-throughput queries
-- ============================================================================

-- 1. Flight Instances Search & Filter Indexes
-- Speed up queries by departure time and status (e.g. airport departure boards)
CREATE INDEX IF NOT EXISTS idx_flight_instances_sched_dept 
    ON flight_instances (scheduled_departure ASC);

CREATE INDEX IF NOT EXISTS idx_flight_instances_sched_arr 
    ON flight_instances (scheduled_arrival ASC);

CREATE INDEX IF NOT EXISTS idx_flight_instances_route_status 
    ON flight_instances (route_id, status);

-- Partial index for active/operational flights (filtering out past completed flights)
CREATE INDEX IF NOT EXISTS idx_flight_instances_active 
    ON flight_instances (flight_instance_id, scheduled_departure, status)
    WHERE status NOT IN ('ARRIVED', 'CANCELLED');

-- 2. Gate Allocation & Overlap Detection Indexes
-- Used by gate management procedures to rapidly find conflicting gate occupancies
CREATE INDEX IF NOT EXISTS idx_flight_instances_dept_gate 
    ON flight_instances (departure_gate_id, scheduled_departure, scheduled_arrival)
    WHERE departure_gate_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_flight_instances_arr_gate 
    ON flight_instances (arrival_gate_id, scheduled_arrival)
    WHERE arrival_gate_id IS NOT NULL;

-- 3. Passenger & Booking Search Indexes
CREATE INDEX IF NOT EXISTS idx_passengers_passport 
    ON passengers (passport_number);

CREATE INDEX IF NOT EXISTS idx_passengers_email 
    ON passengers (LOWER(email));

CREATE INDEX IF NOT EXISTS idx_bookings_reference 
    ON bookings (booking_reference);

CREATE INDEX IF NOT EXISTS idx_bookings_flight_passenger 
    ON bookings (flight_instance_id, passenger_id);

CREATE INDEX IF NOT EXISTS idx_bookings_status 
    ON bookings (booking_status)
    WHERE booking_status IN ('CONFIRMED', 'CHECKED_IN');

-- 4. Baggage & Real-time Tracking Indexes
CREATE INDEX IF NOT EXISTS idx_baggage_tag 
    ON baggage (tag_number);

CREATE INDEX IF NOT EXISTS idx_baggage_flight 
    ON baggage (flight_instance_id, status);

CREATE INDEX IF NOT EXISTS idx_baggage_events_timeline 
    ON baggage_tracking_events (baggage_id, scanned_at DESC);

-- 5. Route & Network Optimization Indexes
CREATE INDEX IF NOT EXISTS idx_flight_routes_origin_dest 
    ON flight_routes (origin_airport_id, destination_airport_id);

CREATE INDEX IF NOT EXISTS idx_flight_routes_airline 
    ON flight_routes (airline_id);

-- 6. Audit & History Query Indexes
CREATE INDEX IF NOT EXISTS idx_audit_flight_timestamp 
    ON flight_status_audit (flight_instance_id, changed_at DESC);

CREATE INDEX IF NOT EXISTS idx_gate_occupancy_timeline 
    ON gate_occupancy_log (gate_id, occupied_from, occupied_until);
