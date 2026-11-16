"""
Advanced SQL Analytics Route Handlers.
Executes Recursive CTEs, Window Functions, and On-Time Performance queries.
"""

from fastapi import APIRouter, HTTPException, Query
from typing import Optional
from .. import db

router = APIRouter(prefix="/api/analytics", tags=["Analytics"])


@router.get("/routes/search")
def search_itineraries(origin: str = Query("DEL", min_length=3, max_length=3),
                       dest: str = Query("JFK", min_length=3, max_length=3)):
    """
    Executes a Recursive CTE to find direct and connecting flights (with layovers)
    between any two airports.
    """
    origin = origin.upper()
    dest = dest.upper()

    conn = db.get_connection()
    if conn:
        try:
            with conn.cursor() as cur:
                query = """
                    WITH RECURSIVE flight_itineraries AS (
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
                        WHERE orig.iata_code = %s
                          AND fi.status NOT IN ('CANCELLED')

                        UNION ALL

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
                        WHERE curr.total_legs < 3
                          AND NOT (next_dest.iata_code = ANY(curr.full_route))
                          AND next_fi.status NOT IN ('CANCELLED')
                          AND next_fi.scheduled_departure >= curr.arrival_time + INTERVAL '60 minutes'
                          AND next_fi.scheduled_departure <= curr.arrival_time + INTERVAL '8 hours'
                    )
                    SELECT 
                        ARRAY_TO_STRING(full_route, ' -> ') AS route_path,
                        full_route,
                        total_legs,
                        TO_CHAR(departure_time, 'YYYY-MM-DD HH24:MI') AS departure_time,
                        TO_CHAR(arrival_time, 'YYYY-MM-DD HH24:MI') AS arrival_time,
                        total_flight_mins,
                        total_layover_mins,
                        (total_flight_mins + total_layover_mins) AS total_journey_mins
                    FROM flight_itineraries
                    WHERE leg_dest = %s
                    ORDER BY total_journey_mins ASC
                    LIMIT 10;
                """
                cur.execute(query, (origin, dest))
                itineraries = cur.fetchall()
                return {
                    "source": "PostgreSQL Recursive CTE",
                    "origin": origin,
                    "destination": dest,
                    "results": itineraries,
                    "itineraries": itineraries
                }
        except Exception as e:
            print(f"[DB Recursive CTE Error]: {e}")
        finally:
            conn.close()

    # Demo mode connecting flight results
    demo_itineraries = [
        {
            "route_path": f"{origin} -> DXB -> {dest}",
            "full_route": [origin, "DXB", dest],
            "total_legs": 2,
            "departure_time": "2026-09-10 08:00",
            "arrival_time": "2026-09-10 22:30",
            "total_flight_mins": 1100,
            "total_layover_mins": 150,
            "total_journey_mins": 1250
        },
        {
            "route_path": f"{origin} -> LHR -> {dest}",
            "full_route": [origin, "LHR", dest],
            "total_legs": 2,
            "departure_time": "2026-09-10 09:30",
            "arrival_time": "2026-09-11 00:10",
            "total_flight_mins": 1040,
            "total_layover_mins": 180,
            "total_journey_mins": 1220
        },
        {
            "route_path": f"{origin} -> {dest} (Non-stop)",
            "full_route": [origin, dest],
            "total_legs": 1,
            "departure_time": "2026-09-10 10:15",
            "arrival_time": "2026-09-10 17:35",
            "total_flight_mins": 960,
            "total_layover_mins": 0,
            "total_journey_mins": 960
        }
    ]
    return {
        "source": "Demo Mode (Recursive CTE Pattern)",
        "origin": origin,
        "destination": dest,
        "results": demo_itineraries,
        "itineraries": demo_itineraries
    }


@router.get("/turnaround")
def get_aircraft_turnaround():
    """Calculates aircraft turnaround durations on the tarmac using LAG() window functions."""
    conn = db.get_connection()
    if conn:
        try:
            with conn.cursor() as cur:
                query = """
                    SELECT 
                        ac.registration_number AS tail_number,
                        am.model_name,
                        fr.flight_number,
                        orig.iata_code AS origin,
                        dest.iata_code AS destination,
                        ROUND(
                            EXTRACT(EPOCH FROM (
                                fi.scheduled_departure - LAG(fi.scheduled_arrival) OVER (
                                    PARTITION BY fi.aircraft_id ORDER BY fi.scheduled_departure
                                )
                            )) / 60.0, 
                            0
                        ) AS turnaround_minutes,
                        CASE 
                            WHEN EXTRACT(EPOCH FROM (fi.scheduled_departure - LAG(fi.scheduled_arrival) OVER (
                                PARTITION BY fi.aircraft_id ORDER BY fi.scheduled_departure
                            ))) / 60.0 < 45 THEN 'CRITICAL'
                            ELSE 'NORMAL'
                        END AS assessment
                    FROM flight_instances fi
                    JOIN aircraft ac ON fi.aircraft_id = ac.aircraft_id
                    JOIN aircraft_models am ON ac.model_code = am.model_code
                    JOIN flight_routes fr ON fi.route_id = fr.route_id
                    JOIN airports orig ON fr.origin_airport_id = orig.airport_id
                    JOIN airports dest ON fr.destination_airport_id = dest.airport_id
                    WHERE fi.aircraft_id IS NOT NULL
                    ORDER BY ac.registration_number, fi.scheduled_departure
                    LIMIT 20;
                """
                cur.execute(query)
                records = cur.fetchall()
                return {"source": "PostgreSQL Window Functions", "turnaround": records}
        except Exception as e:
            print(f"[DB Window Error]: {e}")
        finally:
            conn.close()

    demo_turnaround = [
        {"tail_number": "VT-EXG", "model_name": "Airbus A350-900", "flight_number": "AI101", "origin": "DEL", "destination": "JFK", "turnaround_minutes": 55, "assessment": "NORMAL"},
        {"tail_number": "VT-ALQ", "model_name": "Boeing 777-300ER", "flight_number": "AI161", "origin": "DEL", "destination": "LHR", "turnaround_minutes": 38, "assessment": "CRITICAL"},
        {"tail_number": "A6-EPG", "model_name": "Boeing 777-300ER", "flight_number": "EK511", "origin": "DEL", "destination": "DXB", "turnaround_minutes": 62, "assessment": "NORMAL"},
        {"tail_number": "G-XWBA", "model_name": "Airbus A350-900", "flight_number": "BA142", "origin": "DEL", "destination": "LHR", "turnaround_minutes": 75, "assessment": "NORMAL"}
    ]
    return {"source": "Demo Mode", "turnaround": demo_turnaround}


@router.get("/performance")
def get_airline_performance():
    """Returns airline on-time performance (OTP) metrics."""
    conn = db.get_connection()
    if conn:
        try:
            with conn.cursor() as cur:
                # Refresh materialized view concurrently so it always reflects current delay adjustments
                try:
                    cur.execute("REFRESH MATERIALIZED VIEW CONCURRENTLY mv_airline_performance;")
                except Exception as ref_err:
                    print(f"[MV Refresh Warning]: {ref_err}")

                cur.execute("""
                    SELECT 
                        airline_name, airline_iata, 
                        total_scheduled_flights, on_time_flights, delayed_flights, 
                        cancelled_flights, avg_delay_minutes, on_time_performance_pct
                    FROM mv_airline_performance
                    LIMIT 10;
                """)
                rows = cur.fetchall()
                if rows:
                    return {"source": "PostgreSQL Materialized View", "performance": rows}
        except Exception as e:
            print(f"[DB MV Error]: {e}")
        finally:
            conn.close()

    demo_perf = [
        {"airline_name": "Singapore Airlines", "airline_iata": "SQ", "total_scheduled_flights": 120, "on_time_flights": 114, "delayed_flights": 6, "cancelled_flights": 0, "avg_delay_minutes": 8.5, "on_time_performance_pct": 95.0},
        {"airline_name": "Emirates", "airline_iata": "EK", "total_scheduled_flights": 240, "on_time_flights": 220, "delayed_flights": 18, "cancelled_flights": 2, "avg_delay_minutes": 12.1, "on_time_performance_pct": 91.6},
        {"airline_name": "British Airways", "airline_iata": "BA", "total_scheduled_flights": 180, "on_time_flights": 158, "delayed_flights": 20, "cancelled_flights": 2, "avg_delay_minutes": 14.3, "on_time_performance_pct": 87.8},
        {"airline_name": "Air India", "airline_iata": "AI", "total_scheduled_flights": 210, "on_time_flights": 178, "delayed_flights": 30, "cancelled_flights": 2, "avg_delay_minutes": 18.0, "on_time_performance_pct": 84.7}
    ]
    return {"source": "Demo Mode", "performance": demo_perf}


@router.get("/map-data")
def get_map_telemetry():
    """Returns geospatial coordinates of all airports and active flight paths for the Radar Map."""
    conn = db.get_connection()
    if conn:
        try:
            with conn.cursor() as cur:
                # 1. Fetch airports
                cur.execute("""
                    SELECT airport_id, iata_code, icao_code, name, city, country,
                           latitude::FLOAT, longitude::FLOAT, elevation_ft
                    FROM airports
                    ORDER BY country, city;
                """)
                airports = cur.fetchall()

                # 2. Fetch active flights with origin & destination coords
                cur.execute("""
                    SELECT 
                        fi.flight_instance_id,
                        al.name AS airline_name,
                        al.iata_code AS airline_iata,
                        fr.flight_number,
                        orig.iata_code AS origin_iata,
                        orig.city AS origin_city,
                        orig.latitude::FLOAT AS orig_lat,
                        orig.longitude::FLOAT AS orig_lon,
                        dest.iata_code AS destination_iata,
                        dest.city AS destination_city,
                        dest.latitude::FLOAT AS dest_lat,
                        dest.longitude::FLOAT AS dest_lon,
                        fi.status,
                        fi.delay_minutes,
                        TO_CHAR(fi.scheduled_departure, 'HH24:MI') AS sched_dept,
                        TO_CHAR(fi.scheduled_arrival, 'HH24:MI') AS sched_arr,
                        COALESCE(ac.model_code, 'A350-900') AS model_code
                    FROM flight_instances fi
                    JOIN flight_routes fr ON fi.route_id = fr.route_id
                    JOIN airlines al ON fr.airline_id = al.airline_id
                    JOIN airports orig ON fr.origin_airport_id = orig.airport_id
                    JOIN airports dest ON fr.destination_airport_id = dest.airport_id
                    LEFT JOIN aircraft ac ON fi.aircraft_id = ac.aircraft_id
                    ORDER BY fi.scheduled_departure ASC;
                """)
                flights = cur.fetchall()

                return {
                    "source": "PostgreSQL",
                    "airports": airports,
                    "flights": flights
                }
        except Exception as e:
            print(f"[DB Map Error]: {e}")
        finally:
            conn.close()

    return {"source": "Demo Mode", "airports": [], "flights": []}


@router.get("/gate-utilization")
def get_terminal_gate_analytics():
    """Returns aggregated gate occupancy and capacity breakdown by terminal."""
    conn = db.get_connection()
    if conn:
        try:
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT 
                        t.terminal_id,
                        t.terminal_code,
                        t.name AS terminal_name,
                        COUNT(g.gate_id) AS total_gates,
                        COUNT(CASE WHEN g.status = 'OCCUPIED' THEN 1 END) AS occupied_gates,
                        COUNT(CASE WHEN g.status = 'RESERVED' THEN 1 END) AS reserved_gates,
                        COUNT(CASE WHEN g.status = 'AVAILABLE' THEN 1 END) AS available_gates,
                        ROUND((COUNT(CASE WHEN g.status = 'OCCUPIED' THEN 1 END)::NUMERIC / NULLIF(COUNT(g.gate_id), 0)) * 100, 1) AS occupancy_pct
                    FROM terminals t
                    JOIN gates g ON t.terminal_id = g.terminal_id
                    GROUP BY t.terminal_id, t.terminal_code, t.name
                    ORDER BY t.terminal_code;
                """)
                terminal_stats = cur.fetchall()
                return {"source": "PostgreSQL", "terminals": terminal_stats}
        except Exception as e:
            print(f"[Gate Analytics Error]: {e}")
        finally:
            conn.close()

    return {"source": "Demo Mode", "terminals": []}

