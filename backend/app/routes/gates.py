"""
Gate Management Route Handlers.
Controls gate assignments and collision-preventing allocations.
"""

from fastapi import APIRouter, HTTPException
from .. import db
from ..models import GateAssignRequest

router = APIRouter(prefix="/api/gates", tags=["Gates"])


@router.get("")
def get_all_gates():
    """Retrieves all airport gates with current status and assigned flight."""
    conn = db.get_connection()
    if conn:
        try:
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT 
                        g.gate_id,
                        t.terminal_code,
                        t.name AS terminal_name,
                        g.gate_number,
                        g.gate_type,
                        g.status,
                        fr.flight_number AS current_flight_number,
                        al.name AS airline_name,
                        orig.iata_code AS origin_iata,
                        dest.iata_code AS destination_iata,
                        fi.flight_instance_id,
                        fi.status AS flight_status
                    FROM gates g
                    JOIN terminals t ON g.terminal_id = t.terminal_id
                    LEFT JOIN flight_instances fi ON fi.departure_gate_id = g.gate_id 
                        AND fi.status NOT IN ('CANCELLED', 'ARRIVED')
                    LEFT JOIN flight_routes fr ON fi.route_id = fr.route_id
                    LEFT JOIN airlines al ON fr.airline_id = al.airline_id
                    LEFT JOIN airports orig ON fr.origin_airport_id = orig.airport_id
                    LEFT JOIN airports dest ON fr.destination_airport_id = dest.airport_id
                    ORDER BY t.terminal_code, g.gate_number;
                """)
                gates = cur.fetchall()
                return {"source": "PostgreSQL", "gates": gates}
        except Exception as e:
            print(f"[DB Gate Query Error]: {e}")
        finally:
            conn.close()

    return {"source": "Demo Mode", "gates": db.DEMO_GATES}


@router.post("/assign")
def assign_gate(req: GateAssignRequest):
    """Assigns a flight to a designated gate via stored procedure sp_assign_flight_gate."""
    conn = db.get_connection()
    if conn:
        try:
            with conn.cursor() as cur:
                cur.execute(
                    "CALL sp_assign_flight_gate(%s, %s, %s);",
                    (req.flight_instance_id, req.gate_id, req.assignment_type)
                )
            return {
                "success": True, 
                "message": f"Assigned Gate ID {req.gate_id} to Flight ID {req.flight_instance_id} for {req.assignment_type}"
            }
        except Exception as e:
            # Stored procedure will raise exception if there's a conflict
            raise HTTPException(status_code=400, detail=str(e))
        finally:
            conn.close()

    # Demo mode assignment
    for g in db.DEMO_GATES:
        if g["gate_id"] == req.gate_id:
            if g["status"] == "OCCUPIED":
                raise HTTPException(status_code=400, detail=f"Gate {g['gate_number']} is already occupied by another aircraft.")
            g["status"] = "RESERVED"
            g["current_flight"] = f"FL-{req.flight_instance_id}"
            return {"success": True, "message": f"[Demo] Assigned Gate {g['gate_number']} to Flight {req.flight_instance_id}"}

    raise HTTPException(status_code=404, detail="Gate not found")
