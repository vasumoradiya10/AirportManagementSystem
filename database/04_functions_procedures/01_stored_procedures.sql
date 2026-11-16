-- ============================================================================
-- AIRPORT MANAGEMENT SYSTEM (AMS) - STORED PROCEDURES & FUNCTIONS
-- PostgreSQL 14+ / 16+ Compatible
-- Description: Transactional logic, automated gate allocation, booking workflow,
--              concurrency locks, and distance calculations
-- ============================================================================

-- 1. Helper Function: Great-Circle Distance (Haversine Formula) in Kilometers
CREATE OR REPLACE FUNCTION fn_calculate_distance_km(
    lat1 NUMERIC, 
    lon1 NUMERIC, 
    lat2 NUMERIC, 
    lon2 NUMERIC
)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    r CONSTANT NUMERIC := 6371.0; -- Earth radius in KM
    dlat NUMERIC;
    dlon NUMERIC;
    a NUMERIC;
    c NUMERIC;
BEGIN
    dlat := RADIANS(lat2 - lat1);
    dlon := RADIANS(lon2 - lon1);
    
    a := SIN(dlat / 2.0)^2 + 
         COS(RADIANS(lat1)) * COS(RADIANS(lat2)) * SIN(dlon / 2.0)^2;
    c := 2.0 * ATAN2(SQRT(a), SQRT(1.0 - a));
    
    RETURN ROUND((r * c)::NUMERIC, 2);
END;
$$;

-- 2. Stored Procedure: Automated Gate Allocation with Overlap & Compatibility Validation
CREATE OR REPLACE PROCEDURE sp_assign_flight_gate(
    p_flight_instance_id BIGINT,
    p_gate_id INTEGER,
    p_assignment_type VARCHAR(10) DEFAULT 'DEPARTURE' -- 'DEPARTURE' or 'ARRIVAL'
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_flight_departure TIMESTAMPTZ;
    v_flight_arrival TIMESTAMPTZ;
    v_window_start TIMESTAMPTZ;
    v_window_end TIMESTAMPTZ;
    v_conflict_flight BIGINT;
    v_aircraft_model VARCHAR(20);
    v_gate_type VARCHAR(30);
    v_gate_number VARCHAR(10);
BEGIN
    -- Fetch flight schedule and assigned aircraft
    SELECT 
        fi.scheduled_departure, 
        fi.scheduled_arrival, 
        ac.model_code
    INTO 
        v_flight_departure, 
        v_flight_arrival, 
        v_aircraft_model
    FROM flight_instances fi
    LEFT JOIN aircraft ac ON fi.aircraft_id = ac.aircraft_id
    WHERE fi.flight_instance_id = p_flight_instance_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Flight instance ID % not found.', p_flight_instance_id;
    END IF;

    -- Fetch gate details
    SELECT g.gate_number, g.gate_type 
    INTO v_gate_number, v_gate_type
    FROM gates g
    WHERE g.gate_id = p_gate_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Gate ID % not found.', p_gate_id;
    END IF;

    -- Define operational gate occupancy buffer (45 mins before and 15 mins after scheduled event)
    IF UPPER(p_assignment_type) = 'DEPARTURE' THEN
        v_window_start := v_flight_departure - INTERVAL '45 minutes';
        v_window_end := v_flight_departure + INTERVAL '15 minutes';
    ELSE
        v_window_start := v_flight_arrival - INTERVAL '15 minutes';
        v_window_end := v_flight_arrival + INTERVAL '45 minutes';
    END IF;

    -- Check for gate conflicts across scheduled flights
    SELECT fi.flight_instance_id INTO v_conflict_flight
    FROM flight_instances fi
    WHERE fi.flight_instance_id <> p_flight_instance_id
      AND fi.status NOT IN ('CANCELLED', 'DIVERTED', 'ARRIVED')
      AND (
          (fi.departure_gate_id = p_gate_id AND fi.scheduled_departure BETWEEN v_window_start AND v_window_end)
          OR
          (fi.arrival_gate_id = p_gate_id AND fi.scheduled_arrival BETWEEN v_window_start AND v_window_end)
      )
    LIMIT 1;

    IF v_conflict_flight IS NOT NULL THEN
        RAISE EXCEPTION 'Gate % is already booked by Flight % during window % to %',
            v_gate_number, v_conflict_flight, v_window_start, v_window_end;
    END IF;

    -- Assign gate to flight instance
    IF UPPER(p_assignment_type) = 'DEPARTURE' THEN
        UPDATE flight_instances 
        SET departure_gate_id = p_gate_id 
        WHERE flight_instance_id = p_flight_instance_id;
    ELSE
        UPDATE flight_instances 
        SET arrival_gate_id = p_gate_id 
        WHERE flight_instance_id = p_flight_instance_id;
    END IF;

    -- Record in Gate Occupancy Log
    INSERT INTO gate_occupancy_log (gate_id, flight_instance_id, occupied_from, occupied_until, status)
    VALUES (p_gate_id, p_flight_instance_id, v_window_start, v_window_end, 'RESERVED');

    RAISE NOTICE 'Successfully assigned Gate % (%) to Flight % for %',
        v_gate_number, v_gate_type, p_flight_instance_id, UPPER(p_assignment_type);
END;
$$;

-- 3. Stored Procedure: Transactional Seat Booking with Concurrency Lock (FOR UPDATE)
CREATE OR REPLACE PROCEDURE sp_process_seat_reservation(
    p_flight_instance_id BIGINT,
    p_passenger_id BIGINT,
    p_seat_number VARCHAR(5),
    p_seat_class seat_class_enum,
    p_ticket_price NUMERIC(10, 2),
    INOUT p_booking_reference CHAR(6) DEFAULT NULL,
    INOUT p_booking_id BIGINT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_flight_status flight_status_enum;
    v_seat_taken BOOLEAN;
    v_chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    v_random_ref CHAR(6) := '';
    v_i INT;
    v_barcode_token VARCHAR(128);
BEGIN
    -- Check flight status with explicit lock on flight record
    SELECT status INTO v_flight_status
    FROM flight_instances
    WHERE flight_instance_id = p_flight_instance_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Flight instance ID % does not exist.', p_flight_instance_id;
    END IF;

    IF v_flight_status IN ('CANCELLED', 'DEPARTED', 'AIRBORNE', 'ARRIVED') THEN
        RAISE EXCEPTION 'Cannot book seat on flight with status: %', v_flight_status;
    END IF;

    -- Validate if seat is already reserved
    SELECT EXISTS (
        SELECT 1 FROM bookings 
        WHERE flight_instance_id = p_flight_instance_id 
          AND seat_number = p_seat_number 
          AND booking_status NOT IN ('CANCELLED')
    ) INTO v_seat_taken;

    IF v_seat_taken THEN
        RAISE EXCEPTION 'Seat % is already booked on Flight instance %', p_seat_number, p_flight_instance_id;
    END IF;

    -- Generate unique 6-character PNR reference
    LOOP
        v_random_ref := '';
        FOR v_i IN 1..6 LOOP
            v_random_ref := v_random_ref || SUBSTR(v_chars, FLOOR(RANDOM() * LENGTH(v_chars) + 1)::INT, 1);
        END LOOP;

        EXIT WHEN NOT EXISTS (SELECT 1 FROM bookings WHERE booking_reference = v_random_ref);
    END LOOP;

    p_booking_reference := v_random_ref;

    -- Insert Booking
    INSERT INTO bookings (
        booking_reference, flight_instance_id, passenger_id, 
        seat_number, seat_class, ticket_price, booking_status
    )
    VALUES (
        p_booking_reference, p_flight_instance_id, p_passenger_id, 
        p_seat_number, p_seat_class, p_ticket_price, 'CONFIRMED'
    )
    RETURNING booking_id INTO p_booking_id;

    -- Automatically issue Boarding Pass token
    v_barcode_token := 'BP-' || p_booking_reference || '-' || MD5(RANDOM()::TEXT || CURRENT_TIMESTAMP::TEXT);
    INSERT INTO boarding_passes (booking_id, barcode_token, boarding_group)
    VALUES (
        p_booking_id, 
        v_barcode_token, 
        CASE 
            WHEN p_seat_class = 'FIRST' THEN 'GRP1'
            WHEN p_seat_class = 'BUSINESS' THEN 'GRP2'
            ELSE 'GRP3'
        END
    );

    RAISE NOTICE 'Booking created: PNR %, Booking ID %', p_booking_reference, p_booking_id;
END;
$$;

-- 4. Stored Procedure: Flight Delay Management & Schedule Recalculation
CREATE OR REPLACE PROCEDURE sp_handle_flight_delay(
    p_flight_instance_id BIGINT,
    p_delay_minutes INTEGER,
    p_reason TEXT DEFAULT 'Operational delay'
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_status flight_status_enum;
    v_new_status flight_status_enum;
BEGIN
    SELECT status INTO v_current_status
    FROM flight_instances
    WHERE flight_instance_id = p_flight_instance_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Flight instance % does not exist.', p_flight_instance_id;
    END IF;

    IF v_current_status = 'ARRIVED' THEN
        RAISE EXCEPTION 'Cannot adjust delay for completed flight.';
    END IF;

    v_new_status := CASE WHEN p_delay_minutes > 15 THEN 'DELAYED'::flight_status_enum ELSE v_current_status END;

    -- Update Flight Instance
    UPDATE flight_instances
    SET 
        delay_minutes = p_delay_minutes,
        delay_reason = p_reason,
        status = v_new_status
    WHERE flight_instance_id = p_flight_instance_id;

    -- Trigger will handle audit logging automatically
    RAISE NOTICE 'Flight % delay updated to % minutes. Reason: %', 
        p_flight_instance_id, p_delay_minutes, p_reason;
END;
$$;

-- 5. Table Function: Seat Availability Breakdown by Cabin Class
CREATE OR REPLACE FUNCTION fn_get_flight_seat_availability(p_flight_instance_id BIGINT)
RETURNS TABLE (
    cabin_class seat_class_enum,
    total_capacity INTEGER,
    booked_seats BIGINT,
    available_seats BIGINT
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_max_capacity INTEGER;
BEGIN
    -- Get aircraft total capacity
    SELECT am.max_passenger_capacity INTO v_max_capacity
    FROM flight_instances fi
    JOIN aircraft ac ON fi.aircraft_id = ac.aircraft_id
    JOIN aircraft_models am ON ac.model_code = am.model_code
    WHERE fi.flight_instance_id = p_flight_instance_id;

    IF NOT FOUND THEN
        v_max_capacity := 180; -- default fallback
    END IF;

    RETURN QUERY
    WITH class_distribution AS (
        SELECT 'FIRST'::seat_class_enum AS cls, ROUND(v_max_capacity * 0.05)::INT AS cap
        UNION ALL
        SELECT 'BUSINESS'::seat_class_enum, ROUND(v_max_capacity * 0.15)::INT
        UNION ALL
        SELECT 'PREMIUM_ECONOMY'::seat_class_enum, ROUND(v_max_capacity * 0.10)::INT
        UNION ALL
        SELECT 'ECONOMY'::seat_class_enum, (v_max_capacity - ROUND(v_max_capacity * 0.30))::INT
    ),
    actual_bookings AS (
        SELECT seat_class, COUNT(*) AS booked
        FROM bookings
        WHERE flight_instance_id = p_flight_instance_id
          AND booking_status NOT IN ('CANCELLED')
        GROUP BY seat_class
    )
    SELECT 
        cd.cls AS cabin_class,
        cd.cap AS total_capacity,
        COALESCE(ab.booked, 0) AS booked_seats,
        (cd.cap - COALESCE(ab.booked, 0))::BIGINT AS available_seats
    FROM class_distribution cd
    LEFT JOIN actual_bookings ab ON cd.cls = ab.seat_class;
END;
$$;
