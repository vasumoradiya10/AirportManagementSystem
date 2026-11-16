-- ============================================================================
-- AIRPORT MANAGEMENT SYSTEM (AMS) - OPERATIONAL & ANALYTICAL VIEWS
-- PostgreSQL 14+ / 16+ Compatible
-- Description: Live FIDS (Flight Information Display System), Gate Status, 
--              Passenger Manifest, and Materialized Analytics Views
-- ============================================================================

-- 1. Live Flight Information Display System (FIDS) Board
-- Combines routes, airlines, gates, and statuses for flight display screens
CREATE OR REPLACE VIEW vw_live_flight_board AS
SELECT 
    fi.flight_instance_id,
    al.name AS airline_name,
    al.iata_code AS airline_iata,
    fr.flight_number,
    orig.iata_code AS origin_iata,
    orig.city AS origin_city,
    dest.iata_code AS destination_iata,
    dest.city AS destination_city,
    fi.scheduled_departure,
    COALESCE(fi.actual_departure, fi.scheduled_departure + (fi.delay_minutes || ' minutes')::INTERVAL) AS estimated_departure,
    fi.scheduled_arrival,
    COALESCE(fi.actual_arrival, fi.scheduled_arrival + (fi.delay_minutes || ' minutes')::INTERVAL) AS estimated_arrival,
    fi.status AS flight_status,
    fi.delay_minutes,
    t_dept.terminal_code AS departure_terminal,
    g_dept.gate_number AS departure_gate,
    t_arr.terminal_code AS arrival_terminal,
    g_arr.gate_number AS arrival_gate,
    ac.registration_number AS aircraft_tail_number,
    ac_mod.model_name AS aircraft_model
FROM flight_instances fi
JOIN flight_routes fr ON fi.route_id = fr.route_id
JOIN airlines al ON fr.airline_id = al.airline_id
JOIN airports orig ON fr.origin_airport_id = orig.airport_id
JOIN airports dest ON fr.destination_airport_id = dest.airport_id
LEFT JOIN gates g_dept ON fi.departure_gate_id = g_dept.gate_id
LEFT JOIN terminals t_dept ON g_dept.terminal_id = t_dept.terminal_id
LEFT JOIN gates g_arr ON fi.arrival_gate_id = g_arr.gate_id
LEFT JOIN terminals t_arr ON g_arr.terminal_id = t_arr.terminal_id
LEFT JOIN aircraft ac ON fi.aircraft_id = ac.aircraft_id
LEFT JOIN aircraft_models ac_mod ON ac.model_code = ac_mod.model_code;

-- 2. Gate Utilization and Current Availability View
CREATE OR REPLACE VIEW vw_gate_utilization AS
SELECT 
    a.iata_code AS airport_iata,
    t.terminal_code,
    g.gate_id,
    g.gate_number,
    g.gate_type,
    g.status AS gate_status,
    g.is_jetbridge_equipped,
    curr_fi.flight_instance_id AS current_flight_id,
    curr_fr.flight_number AS current_flight_number,
    curr_fi.scheduled_departure AS current_flight_departure,
    curr_fi.status AS current_flight_status
FROM gates g
JOIN terminals t ON g.terminal_id = t.terminal_id
JOIN airports a ON t.airport_id = a.airport_id
LEFT JOIN flight_instances curr_fi ON curr_fi.departure_gate_id = g.gate_id 
    AND curr_fi.status IN ('BOARDING', 'GATE_CLOSED', 'SCHEDULED')
    AND curr_fi.scheduled_departure BETWEEN CURRENT_TIMESTAMP - INTERVAL '1 hour' AND CURRENT_TIMESTAMP + INTERVAL '3 hours'
LEFT JOIN flight_routes curr_fr ON curr_fi.route_id = curr_fr.route_id;

-- 3. Comprehensive Passenger & Baggage Manifest View
CREATE OR REPLACE VIEW vw_flight_passenger_manifest AS
SELECT 
    fi.flight_instance_id,
    fr.flight_number,
    b.booking_reference,
    p.passenger_id,
    p.first_name || ' ' || p.last_name AS passenger_full_name,
    p.passport_number,
    p.nationality,
    b.seat_number,
    b.seat_class,
    b.booking_status,
    bp.barcode_token,
    bp.is_boarded,
    bp.boarded_at,
    COUNT(bg.baggage_id) AS checked_baggage_count,
    COALESCE(SUM(bg.weight_kg), 0.00) AS total_baggage_weight_kg
FROM bookings b
JOIN flight_instances fi ON b.flight_instance_id = fi.flight_instance_id
JOIN flight_routes fr ON fi.route_id = fr.route_id
JOIN passengers p ON b.passenger_id = p.passenger_id
LEFT JOIN boarding_passes bp ON b.booking_id = bp.booking_id
LEFT JOIN baggage bg ON b.booking_id = bg.booking_id
GROUP BY 
    fi.flight_instance_id, fr.flight_number, b.booking_reference, 
    p.passenger_id, p.first_name, p.last_name, p.passport_number, 
    p.nationality, b.seat_number, b.seat_class, b.booking_status, 
    bp.barcode_token, bp.is_boarded, bp.boarded_at;

-- 4. Materialized View: Airline On-Time Performance (OTP)
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_airline_performance AS
SELECT 
    al.airline_id,
    al.name AS airline_name,
    al.iata_code AS airline_iata,
    DATE_TRUNC('month', fi.scheduled_departure) AS operational_month,
    COUNT(fi.flight_instance_id) AS total_scheduled_flights,
    COUNT(CASE WHEN fi.status NOT IN ('CANCELLED') AND fi.delay_minutes <= 15 THEN 1 END) AS on_time_flights,
    COUNT(CASE WHEN fi.delay_minutes > 15 THEN 1 END) AS delayed_flights,
    COUNT(CASE WHEN fi.status = 'CANCELLED' THEN 1 END) AS cancelled_flights,
    ROUND(AVG(fi.delay_minutes)::NUMERIC, 2) AS avg_delay_minutes,
    ROUND(
        (COUNT(CASE WHEN fi.status NOT IN ('CANCELLED') AND fi.delay_minutes <= 15 THEN 1 END)::NUMERIC / 
        NULLIF(COUNT(fi.flight_instance_id), 0)) * 100, 
        2
    ) AS on_time_performance_pct
FROM flight_instances fi
JOIN flight_routes fr ON fi.route_id = fr.route_id
JOIN airlines al ON fr.airline_id = al.airline_id
GROUP BY al.airline_id, al.name, al.iata_code, DATE_TRUNC('month', fi.scheduled_departure)
WITH DATA;

-- Unique index for concurrent materialized view refresh
CREATE UNIQUE INDEX IF NOT EXISTS uq_idx_mv_airline_perf 
    ON mv_airline_performance (airline_id, operational_month);

-- Procedure to refresh materialized view concurrently
CREATE OR REPLACE PROCEDURE sp_refresh_airline_performance()
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_airline_performance;
END;
$$;
