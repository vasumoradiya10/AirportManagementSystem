"""
Baggage Tracking Route Handlers.
Tracks luggage status checkpoints and scan events across the airport.
Provides full relational integration with Flights, Bookings, and Passengers.
"""

from fastapi import APIRouter, HTTPException
from typing import Optional
from .. import db
from ..models import BaggageScanRequest

router = APIRouter(prefix="/api/baggage", tags=["Baggage"])


@router.get("")
def get_all_baggage():
    """Retrieves all tracked luggage across the airport with their linked flight and passenger."""
    conn = db.get_connection()
    if conn:
        try:
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT 
                        bg.baggage_id,
                        bg.tag_number,
                        b.booking_reference,
                        p.first_name || ' ' || p.last_name AS passenger_name,
                        fr.flight_number,
                        al.name AS airline_name,
                        orig.iata_code || ' ➔ ' || dest.iata_code AS route,
                        bg.weight_kg,
                        bg.status AS current_status,
                        fi.status AS flight_status,
                        COALESCE(
                            (SELECT checkpoint_location FROM baggage_tracking_events 
                             WHERE baggage_id = bg.baggage_id ORDER BY scanned_at DESC LIMIT 1),
                            'Check-in Desk'
                        ) AS last_location
                    FROM baggage bg
                    JOIN bookings b ON bg.booking_id = b.booking_id
                    JOIN passengers p ON b.passenger_id = p.passenger_id
                    JOIN flight_instances fi ON bg.flight_instance_id = fi.flight_instance_id
                    JOIN flight_routes fr ON fi.route_id = fr.route_id
                    JOIN airlines al ON fr.airline_id = al.airline_id
                    JOIN airports orig ON fr.origin_airport_id = orig.airport_id
                    JOIN airports dest ON fr.destination_airport_id = dest.airport_id
                    ORDER BY bg.baggage_id DESC;
                """)
                bags = cur.fetchall()
                return {"source": "PostgreSQL", "count": len(bags), "baggage_list": bags}
        except Exception as e:
            print(f"[DB Baggage List Error]: {e}")
        finally:
            conn.close()

    return {"source": "Demo Mode", "count": len(db.DEMO_BAGGAGE), "baggage_list": list(db.DEMO_BAGGAGE.values())}


@router.get("/{tag_number}")
def track_baggage(tag_number: str):
    """
    Retrieves real-time baggage location and tracking milestone events.
    Accepts either luggage Tag Number (e.g. BAG-AI-88910) or Booking PNR (e.g. F2BEKG).
    """
    clean_query = tag_number.strip().upper()
    conn = db.get_connection()
    if conn:
        try:
            with conn.cursor() as cur:
                # 1. Fetch bag info linked to booking, passenger, and flight
                cur.execute("""
                    SELECT 
                        bg.baggage_id,
                        bg.tag_number,
                        b.booking_reference,
                        p.first_name || ' ' || p.last_name AS passenger_name,
                        fr.flight_number,
                        al.name AS airline_name,
                        orig.iata_code || ' ➔ ' || dest.iata_code AS route,
                        bg.weight_kg,
                        bg.status AS current_status,
                        fi.status AS flight_status
                    FROM baggage bg
                    JOIN bookings b ON bg.booking_id = b.booking_id
                    JOIN passengers p ON b.passenger_id = p.passenger_id
                    JOIN flight_instances fi ON bg.flight_instance_id = fi.flight_instance_id
                    JOIN flight_routes fr ON fi.route_id = fr.route_id
                    JOIN airlines al ON fr.airline_id = al.airline_id
                    JOIN airports orig ON fr.origin_airport_id = orig.airport_id
                    JOIN airports dest ON fr.destination_airport_id = dest.airport_id
                    WHERE bg.tag_number = %s OR b.booking_reference = %s
                    LIMIT 1;
                """, (clean_query, clean_query))
                bag = cur.fetchone()
                if not bag:
                    raise HTTPException(status_code=404, detail=f"No baggage record found for '{clean_query}'.")

                # 2. Fetch timeline events
                cur.execute("""
                    SELECT 
                        event_status AS event, 
                        event_status AS scan_event,
                        checkpoint_location AS location, 
                        TO_CHAR(scanned_at, 'YYYY-MM-DD HH24:MI:SS') AS scanned_at,
                        TO_CHAR(scanned_at, 'HH24:MI:SS') AS time,
                        scanned_by
                    FROM baggage_tracking_events
                    WHERE baggage_id = %s
                    ORDER BY scanned_at ASC;
                """, (bag["baggage_id"],))
                events = cur.fetchall()

                return {
                    "source": "PostgreSQL",
                    "tag_number": bag["tag_number"],
                    "booking_reference": bag["booking_reference"],
                    "passenger_name": bag["passenger_name"],
                    "flight_number": bag["flight_number"],
                    "airline_name": bag["airline_name"],
                    "route": bag["route"],
                    "weight_kg": float(bag["weight_kg"]),
                    "current_status": bag["current_status"],
                    "flight_status": bag["flight_status"],
                    "scans": events,
                    "timeline": events
                }
        except HTTPException:
            raise
        except Exception as e:
            print(f"[DB Baggage Query Error]: {e}")
            raise HTTPException(status_code=500, detail=str(e))
        finally:
            conn.close()

    if clean_query in db.DEMO_BAGGAGE:
        demo_bag = db.DEMO_BAGGAGE[clean_query]
        return {
            "source": "Demo Mode",
            "tag_number": demo_bag.get("tag_number", clean_query),
            "booking_reference": demo_bag.get("booking_reference", "DEMOPNR"),
            "passenger_name": demo_bag.get("passenger_name", "Demo Traveler"),
            "flight_number": demo_bag.get("flight_number", "AI101"),
            "route": "DEL ➔ JFK",
            "weight_kg": 23.0,
            "current_status": demo_bag.get("current_status", "LOADED"),
            "scans": demo_bag.get("timeline", []),
            "timeline": demo_bag.get("timeline", [])
        }

    raise HTTPException(status_code=404, detail=f"Baggage '{clean_query}' not found.")


@router.post("/{tag_number}/scan")
def log_baggage_scan(tag_number: str, req: BaggageScanRequest):
    """Logs a new milestone checkpoint scan event for a baggage tag and updates its status."""
    clean_tag = tag_number.strip().upper()
    conn = db.get_connection()
    if conn:
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT baggage_id FROM baggage WHERE tag_number = %s;", (clean_tag,))
                row = cur.fetchone()
                if not row:
                    raise HTTPException(status_code=404, detail=f"Baggage tag '{clean_tag}' not found.")
                
                bag_id = row["baggage_id"]
                cur.execute("""
                    INSERT INTO baggage_tracking_events (baggage_id, event_status, checkpoint_location, scanned_by)
                    VALUES (%s, %s, %s, %s);
                """, (bag_id, req.event_status, req.checkpoint_location, req.scanned_by or "AMS Agent"))

                cur.execute("""
                    UPDATE baggage SET status = %s WHERE baggage_id = %s;
                """, (req.event_status, bag_id))

            return {
                "success": True, 
                "message": f"Recorded scan '{req.event_status}' at '{req.checkpoint_location}' for tag {clean_tag}."
            }
        except HTTPException:
            raise
        except Exception as e:
            print(f"[DB Baggage Scan Error]: {e}")
            raise HTTPException(status_code=500, detail=str(e))
        finally:
            conn.close()

    return {"success": True, "message": f"[Demo] Recorded scan '{req.event_status}' at '{req.checkpoint_location}'."}
