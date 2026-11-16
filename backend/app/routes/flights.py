"""
Flight Operations Route Handlers.
Manages FIDS live board, flight scheduling, delay adjustments, and live aircraft tracking.
"""

from fastapi import APIRouter, HTTPException, Query
from typing import Optional, List
import math
import json
import base64
import urllib.request
from datetime import datetime, timezone
from .. import db, config
from ..models import FlightDelayRequest

router = APIRouter(prefix="/api/flights", tags=["Flights"])


@router.get("")
@router.get("/live-board")
def get_live_flight_board(status: Optional[str] = None, origin: Optional[str] = None, dest: Optional[str] = None):
    """Retrieves real-time flight records for the FIDS display board."""
    conn = db.get_connection()
    if conn:
        try:
            with conn.cursor() as cur:
                query = """
                    SELECT 
                        flight_instance_id, airline_name, airline_iata, flight_number,
                        origin_iata, origin_city, destination_iata, destination_city,
                        TO_CHAR(scheduled_departure, 'YYYY-MM-DD HH24:MI') AS scheduled_departure,
                        TO_CHAR(estimated_departure, 'YYYY-MM-DD HH24:MI') AS estimated_departure,
                        TO_CHAR(scheduled_arrival, 'YYYY-MM-DD HH24:MI') AS scheduled_arrival,
                        TO_CHAR(estimated_arrival, 'YYYY-MM-DD HH24:MI') AS estimated_arrival,
                        flight_status, delay_minutes, departure_terminal, departure_gate,
                        arrival_terminal, arrival_gate, aircraft_tail_number, aircraft_model
                    FROM vw_live_flight_board
                    WHERE 1=1
                """
                params = []
                if status:
                    query += " AND flight_status = %s"
                    params.append(status.upper())
                if origin:
                    query += " AND origin_iata = %s"
                    params.append(origin.upper())
                if dest:
                    query += " AND destination_iata = %s"
                    params.append(dest.upper())
                query += " ORDER BY scheduled_departure ASC LIMIT 50;"

                cur.execute(query, params)
                records = cur.fetchall()
                return {"source": "PostgreSQL", "count": len(records), "flights": records}
        except Exception as e:
            print(f"[DB Query Error]: {e}")
        finally:
            conn.close()

    # Fallback to Demo Data
    results = db.DEMO_FLIGHTS
    if status:
        results = [f for f in results if f["flight_status"].lower() == status.lower()]
    if origin:
        results = [f for f in results if f["origin_iata"].lower() == origin.lower()]
    if dest:
        results = [f for f in results if f["destination_iata"].lower() == dest.lower()]

    return {"source": "Demo Mode (PostgreSQL credentials pending)", "count": len(results), "flights": results}


@router.post("/{flight_id}/delay")
def update_flight_delay(flight_id: int, req: FlightDelayRequest):
    """Invokes stored procedure sp_handle_flight_delay to adjust delay and log audit events."""
    conn = db.get_connection()
    if conn:
        try:
            with conn.cursor() as cur:
                cur.execute(
                    "CALL sp_handle_flight_delay(%s, %s, %s);",
                    (flight_id, req.delay_minutes, req.delay_reason)
                )
            return {"success": True, "message": f"Flight {flight_id} delay updated to {req.delay_minutes} mins."}
        except Exception as e:
            raise HTTPException(status_code=400, detail=str(e))
        finally:
            conn.close()

    # Demo mode response
    for f in db.DEMO_FLIGHTS:
        if f["flight_instance_id"] == flight_id:
            f["delay_minutes"] = req.delay_minutes
            f["flight_status"] = "DELAYED" if req.delay_minutes > 15 else f["flight_status"]
            return {"success": True, "message": f"[Demo] Flight {flight_id} delay set to {req.delay_minutes}m."}

    raise HTTPException(status_code=404, detail="Flight not found")


def _bearing(lat1, lon1, lat2, lon2):
    """Compass bearing from point A → B in degrees (0–360)."""
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
    dlon = lon2 - lon1
    x = math.sin(dlon) * math.cos(lat2)
    y = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dlon)
    return (math.degrees(math.atan2(x, y)) + 360) % 360


def _heading_to_compass(deg):
    """Converts 0-360 degrees into cardinal / intercardinal compass direction."""
    dirs = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
            "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
    ix = round(deg / 22.5) % 16
    return f"{dirs[ix]} ({deg:.0f}°)"


def _get_location_description(lat, lon, progress, orig_city, dest_city, status):
    """Generates plain-English human-readable flight location description."""
    if status != 'AIRBORNE':
        if status == 'BOARDING':
            return f"At {orig_city} Gate (Boarding)"
        elif status == 'GATE_CLOSED':
            return f"At {orig_city} Gate (Pushback Pending)"
        elif status == 'DELAYED':
            return f"Holding at {orig_city} (Delayed)"
        elif status == 'SCHEDULED':
            return f"Stationed at {orig_city} Terminal"
        return f"At {orig_city}"

    if progress < 0.10:
        return f"Climbing out of {orig_city} Airspace"
    elif progress > 0.88:
        return f"Descending into {dest_city} Approach"

    # Airspace geographic zones
    if 18.0 <= lat <= 32.0 and 70.0 <= lon <= 88.0:
        return "Over Central / Northern India"
    elif 8.0 <= lat <= 18.0 and 73.0 <= lon <= 82.0:
        return "Over Southern India / Deccan Plateau"
    elif 12.0 <= lat <= 26.0 and 58.0 <= lon <= 72.0:
        return "Over Arabian Sea"
    elif 22.0 <= lat <= 30.0 and 45.0 <= lon <= 58.0:
        return "Over Persian Gulf / Arabian Peninsula"
    elif 28.0 <= lat <= 38.0 and 44.0 <= lon <= 62.0:
        return "Over Middle East / Zagros Air Corridor"
    elif 35.0 <= lat <= 44.0 and 46.0 <= lon <= 55.0:
        return "Over Caspian Sea / Caucasus Corridor"
    elif 38.0 <= lat <= 48.0 and 26.0 <= lon <= 44.0:
        return "Over Black Sea / Eastern Europe"
    elif 45.0 <= lat <= 54.0 and 6.0 <= lon <= 20.0:
        return "Over Central Europe / Alps"
    elif 48.0 <= lat <= 58.0 and -5.0 <= lon <= 6.0:
        return "Over Western Europe / English Channel"
    elif 45.0 <= lat <= 62.0 and -45.0 <= lon <= -10.0:
        return "Over North Atlantic Flight Corridor"
    elif 38.0 <= lat <= 48.0 and -75.0 <= lon <= -60.0:
        return "Over US East Coast Airspace"
    elif 6.0 <= lat <= 20.0 and 82.0 <= lon <= 96.0:
        return "Over Bay of Bengal / Andaman Sea"
    elif 1.0 <= lat <= 7.0 and 96.0 <= lon <= 104.0:
        return "Over Malacca Strait / Southeast Asia"

    return f"Cruising towards {dest_city} ({round(progress * 100)}% route complete)"


@router.get("/tracking")
def get_live_aircraft_positions():
    """
    Interpolated current GPS positions & human-readable locations for all active flights.
    AIRBORNE flights: position calculated by elapsed % of route with speed, altitude, and heading.
    """
    conn = db.get_connection()
    if not conn:
        return {"source": "Demo Mode", "aircraft": []}

    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    fi.flight_instance_id,
                    al.name           AS airline_name,
                    al.iata_code      AS airline_iata,
                    fr.flight_number,
                    fi.status,
                    fi.delay_minutes,
                    orig.iata_code    AS origin_iata,
                    orig.city         AS origin_city,
                    orig.latitude::FLOAT  AS orig_lat,
                    orig.longitude::FLOAT AS orig_lon,
                    dest.iata_code    AS dest_iata,
                    dest.city         AS dest_city,
                    dest.latitude::FLOAT  AS dest_lat,
                    dest.longitude::FLOAT AS dest_lon,
                    fi.scheduled_departure AT TIME ZONE 'UTC' AS dep_utc,
                    fi.scheduled_arrival   AT TIME ZONE 'UTC' AS arr_utc,
                    COALESCE(ac.model_code, 'A350') AS aircraft_model
                FROM flight_instances fi
                JOIN flight_routes fr ON fi.route_id = fr.route_id
                JOIN airlines al      ON fr.airline_id = al.airline_id
                JOIN airports orig    ON fr.origin_airport_id = orig.airport_id
                JOIN airports dest    ON fr.destination_airport_id = dest.airport_id
                LEFT JOIN aircraft ac ON fi.aircraft_id = ac.aircraft_id
                WHERE fi.status NOT IN ('CANCELLED', 'ARRIVED')
                ORDER BY fi.scheduled_departure ASC;
            """)
            rows = cur.fetchall()

        now = datetime.now(timezone.utc)
        aircraft = []

        for r in rows:
            dep = r["dep_utc"]
            arr = r["arr_utc"]
            if dep.tzinfo is None:
                dep = dep.replace(tzinfo=timezone.utc)
            if arr.tzinfo is None:
                arr = arr.replace(tzinfo=timezone.utc)

            total_secs = (arr - dep).total_seconds()
            elapsed_secs = (now - dep).total_seconds()

            is_airborne = (r["status"] == "AIRBORNE" and total_secs > 0)
            progress = max(0.0, min(1.0, elapsed_secs / total_secs)) if is_airborne else 0.0

            lat = r["orig_lat"] + progress * (r["dest_lat"] - r["orig_lat"])
            lon = r["orig_lon"] + progress * (r["dest_lon"] - r["orig_lon"])
            heading = _bearing(r["orig_lat"], r["orig_lon"], r["dest_lat"], r["dest_lon"])

            alt_ft = 36000 if is_airborne else 0
            speed_kts = 490 if is_airborne else 0

            # Text progress bar: e.g. [====------] 40%
            pct = round(progress * 100, 1)
            filled = int(pct / 10)
            bar_text = f"[{'=' * filled}{'-' * (10 - filled)}] {pct:.1f}%" if is_airborne else "At Gate"

            location_desc = _get_location_description(
                lat, lon, progress, r["origin_city"], r["dest_city"], r["status"]
            )

            aircraft.append({
                "flight_instance_id": r["flight_instance_id"],
                "flight_number":      r["flight_number"],
                "airline_name":       r["airline_name"],
                "airline_iata":       r["airline_iata"],
                "status":             r["status"],
                "delay_minutes":      r["delay_minutes"],
                "origin_iata":        r["origin_iata"],
                "origin_city":        r["origin_city"],
                "dest_iata":          r["dest_iata"],
                "dest_city":          r["dest_city"],
                "orig_lat":           r["orig_lat"],
                "orig_lon":           r["orig_lon"],
                "dest_lat":           r["dest_lat"],
                "dest_lon":           r["dest_lon"],
                "lat":                round(lat, 4),
                "lon":                round(lon, 4),
                "coord_formatted":    f"{abs(lat):.2f}° {'N' if lat>=0 else 'S'}, {abs(lon):.2f}° {'E' if lon>=0 else 'W'}",
                "location_text":      location_desc,
                "altitude_ft":        alt_ft,
                "altitude_formatted": f"{alt_ft:,} ft" if is_airborne else "Ground",
                "speed_kts":          speed_kts,
                "speed_formatted":    f"{speed_kts} kts" if is_airborne else "0 kts",
                "heading":            round(heading, 1),
                "compass_dir":        _heading_to_compass(heading) if is_airborne else "—",
                "progress_pct":       pct,
                "progress_bar_text":  bar_text,
                "aircraft_model":     r["aircraft_model"],
                "dep_utc":            dep.strftime("%H:%M"),
                "arr_utc":            arr.strftime("%H:%M"),
            })

        return {"source": "PostgreSQL", "timestamp": now.isoformat(), "aircraft": aircraft}

    except Exception as e:
        print(f"[Tracking Error]: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        conn.close()


@router.get("/opensky")
def get_opensky_live_radar(
    lamin: float = Query(5.0, description="Minimum latitude"),
    lamax: float = Query(40.0, description="Maximum latitude"),
    lomin: float = Query(40.0, description="Minimum longitude"),
    lomax: float = Query(105.0, description="Maximum longitude")
):
    """
    Fetches real-time ADS-B transponder states from OpenSky Network.
    Uses OPENSKY_USERNAME and OPENSKY_PASSWORD from .env if configured.
    """
    url = f"https://opensky-network.org/api/states/all?lamin={lamin}&lamax={lamax}&lomin={lomin}&lomax={lomax}"
    req = urllib.request.Request(url, headers={"User-Agent": "AeroOps-AirportManagement/1.0"})

    if config.OPENSKY_USERNAME and config.OPENSKY_PASSWORD:
        auth_str = f"{config.OPENSKY_USERNAME}:{config.OPENSKY_PASSWORD}"
        b64_auth = base64.b64encode(auth_str.encode()).decode()
        req.add_header("Authorization", f"Basic {b64_auth}")

    try:
        with urllib.request.urlopen(req, timeout=8) as response:
            data = json.loads(response.read().decode())
            states = data.get("states", []) or []

            live_planes = []
            for s in states[:60]:
                callsign = (s[1] or "").strip()
                if not callsign:
                    continue
                country = s[2] or "Unknown"
                lon = s[5]
                lat = s[6]
                baro_alt = s[7]
                on_ground = s[8]
                velocity = s[9]
                track = s[10]

                if lat is None or lon is None:
                    continue

                alt_ft = int(baro_alt * 3.28084) if baro_alt else 0
                speed_kts = int(velocity * 1.94384) if velocity else 0

                live_planes.append({
                    "callsign":           callsign,
                    "country":            country,
                    "lat":                round(lat, 4),
                    "lon":                round(lon, 4),
                    "coord_formatted":    f"{abs(lat):.2f}° {'N' if lat>=0 else 'S'}, {abs(lon):.2f}° {'E' if lon>=0 else 'W'}",
                    "altitude_formatted": f"{alt_ft:,} ft" if not on_ground else "Ground",
                    "speed_formatted":    f"{speed_kts} kts" if not on_ground else "0 kts",
                    "compass_dir":        _heading_to_compass(track or 0) if not on_ground else "—",
                    "status":             "ON GROUND" if on_ground else "AIRBORNE",
                })

            return {
                "source": "OpenSky Network (Live ADS-B Transponders)",
                "authenticated": bool(config.OPENSKY_USERNAME),
                "count": len(live_planes),
                "aircraft": live_planes
            }
    except Exception as e:
        return {
            "source": "OpenSky Network",
            "error": str(e),
            "authenticated": bool(config.OPENSKY_USERNAME),
            "aircraft": []
        }



@router.get("/stats")
def get_dashboard_stats():
    """KPI counts: total flights, airborne, delayed, boarding, gates occupied."""
    conn = db.get_connection()
    if conn:
        try:
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT
                        COUNT(*)                                       AS total_flights,
                        COUNT(*) FILTER (WHERE status='AIRBORNE')     AS airborne,
                        COUNT(*) FILTER (WHERE status='BOARDING')     AS boarding,
                        COUNT(*) FILTER (WHERE status='DELAYED')      AS delayed,
                        COUNT(*) FILTER (WHERE status='SCHEDULED')    AS scheduled,
                        COUNT(*) FILTER (WHERE status='CANCELLED')    AS cancelled
                    FROM flight_instances;
                """)
                stats = cur.fetchone()
                cur.execute("""
                    SELECT COUNT(*) FILTER (WHERE status='OCCUPIED') AS occupied_gates,
                           COUNT(*) AS total_gates
                    FROM gates;
                """)
                gate_stats = cur.fetchone()
                return {
                    "source": "PostgreSQL",
                    "flights": dict(stats) if stats else {},
                    "gates": dict(gate_stats) if gate_stats else {}
                }
        except Exception as e:
            print(f"[Stats Error]: {e}")
        finally:
            conn.close()

    return {
        "source": "Demo Mode",
        "flights": {"total_flights": 15, "airborne": 3, "boarding": 4, "delayed": 2, "scheduled": 6, "cancelled": 0},
        "gates": {"occupied_gates": 7, "total_gates": 20}
    }

