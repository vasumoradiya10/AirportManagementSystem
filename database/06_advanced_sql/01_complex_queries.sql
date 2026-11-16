-- ============================================================================
-- AIRPORT MANAGEMENT SYSTEM (AMS) - ADVANCED SQL TECHNIQUES
-- PostgreSQL 14+ / 16+ Compatible
-- Topics:
--   1. Recursive CTE: Multi-Leg Flight & Connection Path Discovery
--   2. Window Functions: Aircraft Turnaround Interval Analysis (LAG/LEAD)
--   3. Window Analytics: Route Revenue & Seat Occupancy Percentiles
--   4. Table Partitioning Pattern (High-Volume Flight History)
--   5. Multi-Tenant Row-Level Security (RLS) Policies
-- ============================================================================

-- ============================================================================
-- 1. RECURSIVE CTE: MULTI-LEG CONNECTING FLIGHT ITINERARY FINDER
-- Finds direct and connecting flights (up to 2 layovers) between Origin & Destination
-- Enforces valid layover windows (1.5 hours to 8 hours) between connecting legs
-- ============================================================================

WITH RECURSIVE flight_itineraries AS (
    -- Anchor member: Initial outbound flights from origin
    SELECT 
        fi.flight_instance_id AS current_flight_id,
        orig.iata_code AS leg_origin,
        dest.iata_code AS leg_dest,
        ARRAY[orig.iata_code, dest.iata_code]::VARCHAR[] AS full_route,
        fi.scheduled_departure AS departure_time,
        fi.scheduled_arrival AS arrival_time,
        1 AS total_legs,
        (EXTRACT(EPOCH FROM (fi.scheduled_arrival - fi.scheduled_departure)) / 60)::INT AS total_flight_mins,
        0::INT AS total_layover_mins
    FROM flight_instances fi
    JOIN flight_routes fr ON fi.route_id = fr.route_id
    JOIN airports orig ON fr.origin_airport_id = orig.airport_id
    JOIN airports dest ON fr.destination_airport_id = dest.airport_id
    WHERE orig.iata_code = 'DEL' -- Search Origin: Delhi (Example)
      AND fi.status NOT IN ('CANCELLED')

    UNION ALL

    -- Recursive member: Find connecting flights from the destination of previous leg
    SELECT 
        next_fi.flight_instance_id,
        curr.leg_dest,
        next_dest.iata_code,
        curr.full_route || next_dest.iata_code,
        curr.departure_time,
        next_fi.scheduled_arrival,
        curr.total_legs + 1,
        curr.total_flight_mins + (EXTRACT(EPOCH FROM (next_fi.scheduled_arrival - next_fi.scheduled_departure)) / 60)::INT,
        curr.total_layover_mins + (EXTRACT(EPOCH FROM (next_fi.scheduled_departure - curr.arrival_time)) / 60)::INT
    FROM flight_itineraries curr
    JOIN airports transfer_apt ON curr.leg_dest = transfer_apt.iata_code
    JOIN flight_routes next_fr ON next_fr.origin_airport_id = transfer_apt.airport_id
    JOIN flight_instances next_fi ON next_fi.route_id = next_fr.route_id
    JOIN airports next_dest ON next_fr.destination_airport_id = next_dest.airport_id
    WHERE curr.total_legs < 3 -- Maximum 2 connections (3 legs total)
      AND NOT (next_dest.iata_code = ANY(curr.full_route)) -- Prevent circular routing
      AND next_fi.status NOT IN ('CANCELLED')
      -- Connection Layover Rules: Minimum 90 mins, Maximum 480 mins (8 hours)
      AND next_fi.scheduled_departure >= curr.arrival_time + INTERVAL '90 minutes'
      AND next_fi.scheduled_departure <= curr.arrival_time + INTERVAL '8 hours'
)
SELECT 
    ARRAY_TO_STRING(full_route, ' -> ') AS itinerary_path,
    total_legs,
    departure_time,
    arrival_time,
    total_flight_mins,
    total_layover_mins,
    (total_flight_mins + total_layover_mins) AS total_journey_mins
FROM flight_itineraries
WHERE leg_dest = 'JFK' -- Search Destination: New York JFK (Example)
ORDER BY total_journey_mins ASC;

-- ============================================================================
-- 2. WINDOW FUNCTIONS: AIRCRAFT GROUND TURNAROUND INTERVALS (LAG / LEAD)
-- Detects tight turnaround buffers (< 45 mins) and operational bottlenecks
-- ============================================================================

SELECT 
    ac.registration_number AS tail_number,
    am.model_name,
    fr.flight_number,
    orig.iata_code AS origin,
    dest.iata_code AS destination,
    fi.scheduled_departure,
    fi.scheduled_arrival,
    -- Previous arrival time of this specific aircraft
    LAG(fi.scheduled_arrival) OVER (
        PARTITION BY fi.aircraft_id 
        ORDER BY fi.scheduled_departure
    ) AS previous_flight_arrival,
    -- Calculate ground turnaround duration
    ROUND(
        EXTRACT(EPOCH FROM (
            fi.scheduled_departure - LAG(fi.scheduled_arrival) OVER (
                PARTITION BY fi.aircraft_id 
                ORDER BY fi.scheduled_departure
            )
        )) / 60.0, 
        0
    ) AS turnaround_minutes,
    CASE 
        WHEN EXTRACT(EPOCH FROM (fi.scheduled_departure - LAG(fi.scheduled_arrival) OVER (
            PARTITION BY fi.aircraft_id ORDER BY fi.scheduled_departure
        ))) / 60.0 < 45 THEN 'CRITICAL - TIGHT TURNAROUND'
        WHEN EXTRACT(EPOCH FROM (fi.scheduled_departure - LAG(fi.scheduled_arrival) OVER (
            PARTITION BY fi.aircraft_id ORDER BY fi.scheduled_departure
        ))) / 60.0 BETWEEN 45 AND 90 THEN 'OPTIMAL'
        ELSE 'EXTENDED LAYOVER'
    END AS turnaround_assessment
FROM flight_instances fi
JOIN aircraft ac ON fi.aircraft_id = ac.aircraft_id
JOIN aircraft_models am ON ac.model_code = am.model_code
JOIN flight_routes fr ON fi.route_id = fr.route_id
JOIN airports orig ON fr.origin_airport_id = orig.airport_id
JOIN airports dest ON fr.destination_airport_id = dest.airport_id
WHERE fi.aircraft_id IS NOT NULL;

-- ============================================================================
-- 3. WINDOW ANALYTICS: CUMULATIVE REVENUE & LOAD FACTOR RANKING
-- ============================================================================

WITH route_financials AS (
    SELECT 
        al.name AS airline_name,
        orig.iata_code || ' - ' || dest.iata_code AS route_corridor,
        fi.flight_instance_id,
        fi.scheduled_departure,
        am.max_passenger_capacity,
        COUNT(b.booking_id) AS total_passengers_booked,
        COALESCE(SUM(b.ticket_price), 0.00) AS total_flight_revenue,
        ROUND((COUNT(b.booking_id)::NUMERIC / NULLIF(am.max_passenger_capacity, 0)) * 100, 1) AS load_factor_pct
    FROM flight_instances fi
    JOIN flight_routes fr ON fi.route_id = fr.route_id
    JOIN airlines al ON fr.airline_id = al.airline_id
    JOIN airports orig ON fr.origin_airport_id = orig.airport_id
    JOIN airports dest ON fr.destination_airport_id = dest.airport_id
    LEFT JOIN aircraft ac ON fi.aircraft_id = ac.aircraft_id
    LEFT JOIN aircraft_models am ON ac.model_code = am.model_code
    LEFT JOIN bookings b ON fi.flight_instance_id = b.flight_instance_id AND b.booking_status <> 'CANCELLED'
    GROUP BY al.name, orig.iata_code, dest.iata_code, fi.flight_instance_id, fi.scheduled_departure, am.max_passenger_capacity
)
SELECT 
    airline_name,
    route_corridor,
    scheduled_departure,
    total_passengers_booked,
    load_factor_pct,
    total_flight_revenue,
    -- Running cumulative revenue per airline
    SUM(total_flight_revenue) OVER (
        PARTITION BY airline_name 
        ORDER BY scheduled_departure 
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_airline_revenue,
    -- Rank routes by revenue performance within airline
    DENSE_RANK() OVER (
        PARTITION BY airline_name 
        ORDER BY total_flight_revenue DESC
    ) AS route_revenue_rank
FROM route_financials;

-- ============================================================================
-- 4. TABLE PARTITIONING ARCHITECTURE PATTERN
-- High-throughput partition design for large-scale flight tracking
-- ============================================================================

/*
-- Example DDL for creating partitioned flight telemetry or logs:
CREATE TABLE IF NOT EXISTS flight_telemetry_partitioned (
    telemetry_id        BIGSERIAL,
    flight_instance_id  BIGINT NOT NULL,
    recorded_at         TIMESTAMPTZ NOT NULL,
    altitude_feet       INTEGER,
    ground_speed_knots  INTEGER,
    latitude            NUMERIC(9, 6),
    longitude           NUMERIC(9, 6),
    heading_degrees     INTEGER,
    PRIMARY KEY (telemetry_id, recorded_at)
) PARTITION BY RANGE (recorded_at);

-- Partition creation for 2026 quarters:
CREATE TABLE IF NOT EXISTS flight_telemetry_2026_q1 PARTITION OF flight_telemetry_partitioned
    FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2026-04-01 00:00:00+00');

CREATE TABLE IF NOT EXISTS flight_telemetry_2026_q2 PARTITION OF flight_telemetry_partitioned
    FOR VALUES FROM ('2026-04-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');

CREATE TABLE IF NOT EXISTS flight_telemetry_default PARTITION OF flight_telemetry_partitioned
    DEFAULT;
*/

-- ============================================================================
-- 5. ROW-LEVEL SECURITY (RLS) MULTI-TENANT ISOLATION
-- Demonstrates multi-airline data isolation (e.g. Airline Staff access)
-- ============================================================================

-- Enable RLS on flight routes and instances
ALTER TABLE flight_routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE flight_instances ENABLE ROW LEVEL SECURITY;

-- Policy: Superusers or airport ground ops can see all flights
DROP POLICY IF EXISTS p_airport_ops_full_access ON flight_routes;
CREATE POLICY p_airport_ops_full_access ON flight_routes
    FOR ALL
    USING (CURRENT_USER = 'postgres' OR CURRENT_USER LIKE '%admin%');

-- Policy: Airline tenant isolation based on current session application setting
-- e.g. SET LOCAL app.current_airline_id = '1';
DROP POLICY IF EXISTS p_airline_tenant_isolation ON flight_routes;
CREATE POLICY p_airline_tenant_isolation ON flight_routes
    FOR ALL
    USING (
        CURRENT_USER = 'postgres' 
        OR airline_id = NULLIF(CURRENT_SETTING('app.current_airline_id', true), '')::INT
    );
