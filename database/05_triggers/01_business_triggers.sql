-- ============================================================================
-- AIRPORT MANAGEMENT SYSTEM (AMS) - BUSINESS TRIGGERS & AUDIT AUTOMATION
-- PostgreSQL 14+ / 16+ Compatible
-- Description: Automated business rules, state auditing, collision prevention,
--              baggage weight checks, and aircraft hours maintenance
-- ============================================================================

-- 1. Trigger Function: Comprehensive Flight Status Audit Logging
CREATE OR REPLACE FUNCTION trg_fn_audit_flight_status_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF (OLD.status IS DISTINCT FROM NEW.status) OR (OLD.delay_minutes IS DISTINCT FROM NEW.delay_minutes) THEN
        INSERT INTO flight_status_audit (
            flight_instance_id,
            old_status,
            new_status,
            delay_minutes,
            changed_by,
            change_reason,
            changed_at
        )
        VALUES (
            NEW.flight_instance_id,
            OLD.status,
            NEW.status,
            NEW.delay_minutes,
            CURRENT_USER,
            COALESCE(NEW.delay_reason, 'Status transition: ' || OLD.status || ' -> ' || NEW.status),
            CURRENT_TIMESTAMP
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_flight_status_audit ON flight_instances;
CREATE TRIGGER trg_flight_status_audit
AFTER UPDATE OF status, delay_minutes ON flight_instances
FOR EACH ROW
EXECUTE FUNCTION trg_fn_audit_flight_status_changes();

-- 2. Trigger Function: Prevent Physical Gate Collisions
CREATE OR REPLACE FUNCTION trg_fn_enforce_gate_non_collision()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_conflict_count INTEGER;
    v_buffer_start TIMESTAMPTZ;
    v_buffer_end TIMESTAMPTZ;
BEGIN
    -- Check Departure Gate Conflict
    IF NEW.departure_gate_id IS NOT NULL AND NEW.status NOT IN ('ARRIVED', 'CANCELLED') THEN
        v_buffer_start := NEW.scheduled_departure - INTERVAL '30 minutes';
        v_buffer_end := NEW.scheduled_departure + INTERVAL '15 minutes';

        SELECT COUNT(*) INTO v_conflict_count
        FROM flight_instances
        WHERE flight_instance_id <> NEW.flight_instance_id
          AND departure_gate_id = NEW.departure_gate_id
          AND status NOT IN ('ARRIVED', 'CANCELLED')
          AND scheduled_departure BETWEEN v_buffer_start AND v_buffer_end;

        IF v_conflict_count > 0 THEN
            RAISE EXCEPTION 'Gate conflict: Gate ID % is already occupied during % - %',
                NEW.departure_gate_id, v_buffer_start, v_buffer_end;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_gate_non_collision ON flight_instances;
CREATE TRIGGER trg_gate_non_collision
BEFORE INSERT OR UPDATE OF departure_gate_id, scheduled_departure, status ON flight_instances
FOR EACH ROW
EXECUTE FUNCTION trg_fn_enforce_gate_non_collision();

-- 3. Trigger Function: Validate Baggage Weight Against Aircraft Cargo Capacity
CREATE OR REPLACE FUNCTION trg_fn_validate_baggage_weight()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_total_kg NUMERIC(10, 2);
    v_max_capacity_kg NUMERIC(10, 2);
BEGIN
    -- Look up aircraft cargo limit for the flight
    SELECT am.max_cargo_capacity_kg INTO v_max_capacity_kg
    FROM flight_instances fi
    JOIN aircraft ac ON fi.aircraft_id = ac.aircraft_id
    JOIN aircraft_models am ON ac.model_code = am.model_code
    WHERE fi.flight_instance_id = NEW.flight_instance_id;

    -- If no aircraft assigned yet, skip check
    IF v_max_capacity_kg IS NOT NULL THEN
        SELECT COALESCE(SUM(weight_kg), 0.00) INTO v_current_total_kg
        FROM baggage
        WHERE flight_instance_id = NEW.flight_instance_id;

        IF (v_current_total_kg + NEW.weight_kg) > v_max_capacity_kg THEN
            RAISE EXCEPTION 'Cargo limit exceeded: Current % kg + New % kg exceeds aircraft max cargo % kg',
                v_current_total_kg, NEW.weight_kg, v_max_capacity_kg;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_baggage_weight ON baggage;
CREATE TRIGGER trg_validate_baggage_weight
BEFORE INSERT ON baggage
FOR EACH ROW
EXECUTE FUNCTION trg_fn_validate_baggage_weight();

-- 4. Trigger Function: Accumulate Aircraft Flight Hours Upon Flight Completion
CREATE OR REPLACE FUNCTION trg_fn_update_flight_hours_on_arrival()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_duration_hours NUMERIC(6, 2);
BEGIN
    IF NEW.status = 'ARRIVED' AND OLD.status <> 'ARRIVED' AND NEW.aircraft_id IS NOT NULL THEN
        -- If actual times recorded, calculate real duration; otherwise use scheduled
        IF NEW.actual_departure IS NOT NULL AND NEW.actual_arrival IS NOT NULL THEN
            v_duration_hours := ROUND((EXTRACT(EPOCH FROM (NEW.actual_arrival - NEW.actual_departure)) / 3600.0)::NUMERIC, 2);
        ELSE
            v_duration_hours := ROUND((EXTRACT(EPOCH FROM (NEW.scheduled_arrival - NEW.scheduled_departure)) / 3600.0)::NUMERIC, 2);
        END IF;

        UPDATE aircraft
        SET total_flight_hours = total_flight_hours + v_duration_hours
        WHERE aircraft_id = NEW.aircraft_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_update_flight_hours ON flight_instances;
CREATE TRIGGER trg_update_flight_hours
AFTER UPDATE OF status ON flight_instances
FOR EACH ROW
EXECUTE FUNCTION trg_fn_update_flight_hours_on_arrival();
