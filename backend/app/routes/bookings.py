"""
Passenger Booking & Boarding Pass Route Handlers.
Processes ACID transactional reservations and retrieves boarding passes.
"""

from fastapi import APIRouter, HTTPException
import random
import string
from .. import db
from ..models import BookingCreateRequest

router = APIRouter(prefix="/api/bookings", tags=["Bookings"])


@router.post("/reserve")
def create_booking(req: BookingCreateRequest):
    """Creates a new passenger reservation with row-locking and generates a boarding pass."""
    conn = db.get_connection()
    if conn:
        try:
            with conn.cursor() as cur:
                # 1. Check or insert passenger
                cur.execute("""
                    INSERT INTO passengers (first_name, last_name, passport_number, nationality, date_of_birth, email)
                    VALUES (%s, %s, %s, 'International', '1995-01-01', %s)
                    ON CONFLICT (passport_number) DO UPDATE SET email = EXCLUDED.email
                    RETURNING passenger_id;
                """, (req.first_name, req.last_name, req.passport_number, req.email))
                passenger_id = cur.fetchone()["passenger_id"]

                # 2. Call transactional procedure directly with typed parameters
                cur.execute("""
                    CALL sp_process_seat_reservation(
                        %s::BIGINT, %s::BIGINT, %s::VARCHAR, %s::seat_class_enum, %s::NUMERIC, NULL, NULL
                    );
                """, (req.flight_instance_id, passenger_id, req.seat_number, req.seat_class, req.ticket_price))
                call_res = cur.fetchone()
                booking_id = call_res.get("p_booking_id") if call_res else None

                # 3. Retrieve generated booking and boarding pass
                cur.execute("""
                    SELECT b.booking_reference, b.seat_number, b.seat_class, bp.barcode_token, bp.boarding_group
                    FROM bookings b
                    JOIN boarding_passes bp ON b.booking_id = bp.booking_id
                    WHERE b.booking_id = %s;
                """, (booking_id,))
                row = cur.fetchone()

                # 4. Generate luggage tag and check-in milestone event
                rand_digits = "".join(random.choices(string.digits, k=5))
                bag_tag = f"BAG-{row['booking_reference'][:3]}-{rand_digits}"
                cur.execute("""
                    INSERT INTO baggage (tag_number, booking_id, flight_instance_id, weight_kg, status)
                    VALUES (%s, %s, %s, 22.50, 'CHECKED_IN')
                    RETURNING baggage_id;
                """, (bag_tag, booking_id, req.flight_instance_id))
                bag_row = cur.fetchone()
                if bag_row:
                    cur.execute("""
                        INSERT INTO baggage_tracking_events (baggage_id, event_status, checkpoint_location, scanned_by)
                        VALUES (%s, 'CHECKED_IN', 'Terminal Check-in Kiosk 04', 'AMS Self-Service');
                    """, (bag_row["baggage_id"],))

                return {
                    "success": True,
                    "booking_reference": row["booking_reference"],
                    "seat_number": row["seat_number"],
                    "seat_class": row["seat_class"],
                    "baggage_tag": bag_tag,
                    "boarding_pass": {
                        "barcode_token": row["barcode_token"],
                        "boarding_group": row["boarding_group"]
                    }
                }
        except Exception as e:
            raise HTTPException(status_code=400, detail=str(e))
        finally:
            conn.close()

    # Demo mode fallback
    pnr = "".join(random.choices(string.ascii_uppercase + string.digits, k=6))
    token = f"BP-{pnr}-" + "".join(random.choices(string.hexdigits.lower(), k=6))
    demo_record = {
        "booking_reference": pnr,
        "flight_number": "AI101",
        "passenger_name": f"{req.first_name} {req.last_name}",
        "passport_number": req.passport_number,
        "seat_number": req.seat_number,
        "seat_class": req.seat_class,
        "ticket_price": req.ticket_price,
        "booking_status": "CONFIRMED",
        "barcode_token": token,
        "boarding_group": "GRP1" if req.seat_class in ["FIRST", "BUSINESS"] else "GRP3",
        "checked_baggage_count": 0,
        "total_baggage_weight_kg": 0.0
    }
    db.DEMO_BOOKINGS[pnr] = demo_record

    return {
        "success": True,
        "booking_reference": pnr,
        "seat_number": req.seat_number,
        "seat_class": req.seat_class,
        "boarding_pass": {
            "barcode_token": token,
            "boarding_group": demo_record["boarding_group"]
        }
    }


@router.get("/{pnr}")
def get_booking(pnr: str):
    """Retrieves booking and boarding pass details by PNR reference."""
    clean_pnr = pnr.strip().upper()
    conn = db.get_connection()
    if conn:
        try:
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT 
                        b.booking_reference, 
                        fr.flight_number,
                        al.name AS airline_name,
                        al.iata_code AS airline_iata,
                        orig.iata_code AS origin_iata,
                        orig.city AS origin_city,
                        dest.iata_code AS destination_iata,
                        dest.city AS destination_city,
                        p.first_name || ' ' || p.last_name AS passenger_name,
                        p.passport_number, 
                        b.seat_number, 
                        b.seat_class,
                        b.ticket_price, 
                        b.booking_status,
                        fi.status AS flight_status,
                        bp.barcode_token, 
                        bp.boarding_group,
                        COUNT(bg.baggage_id) AS checked_baggage_count,
                        COALESCE(SUM(bg.weight_kg), 0.0) AS total_baggage_weight_kg
                    FROM bookings b
                    JOIN passengers p ON b.passenger_id = p.passenger_id
                    JOIN flight_instances fi ON b.flight_instance_id = fi.flight_instance_id
                    JOIN flight_routes fr ON fi.route_id = fr.route_id
                    JOIN airlines al ON fr.airline_id = al.airline_id
                    JOIN airports orig ON fr.origin_airport_id = orig.airport_id
                    JOIN airports dest ON fr.destination_airport_id = dest.airport_id
                    LEFT JOIN boarding_passes bp ON b.booking_id = bp.booking_id
                    LEFT JOIN baggage bg ON b.booking_id = bg.booking_id
                    WHERE b.booking_reference = %s
                    GROUP BY b.booking_reference, fr.flight_number, al.name, al.iata_code,
                             orig.iata_code, orig.city, dest.iata_code, dest.city,
                             p.first_name, p.last_name, p.passport_number, b.seat_number, 
                             b.seat_class, b.ticket_price, b.booking_status, fi.status,
                             bp.barcode_token, bp.boarding_group;
                """, (clean_pnr,))
                record = cur.fetchone()
                if record:
                    resp = dict(record)
                    resp["source"] = "PostgreSQL"
                    resp["booking"] = dict(record)
                    return resp
        except Exception as e:
            print(f"[DB Booking Query Error]: {e}")
        finally:
            conn.close()

    if clean_pnr in db.DEMO_BOOKINGS:
        demo_rec = dict(db.DEMO_BOOKINGS[clean_pnr])
        demo_rec["source"] = "Demo Mode"
        demo_rec["booking"] = dict(db.DEMO_BOOKINGS[clean_pnr])
        return demo_rec

    raise HTTPException(status_code=404, detail="Booking reference not found.")
