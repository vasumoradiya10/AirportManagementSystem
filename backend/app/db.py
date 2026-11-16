"""
Database Connection & Data Access Layer.
Connects to PostgreSQL with automatic demo-mode fallback when credentials are not yet supplied.
"""

import sys
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional
from . import config

try:
    import psycopg
    from psycopg.rows import dict_row
    PSYCOPG_AVAILABLE = True
except ImportError:
    PSYCOPG_AVAILABLE = False

_is_connected = False


def check_connection() -> bool:
    """Attempts a test connection to PostgreSQL."""
    global _is_connected
    if not PSYCOPG_AVAILABLE:
        _is_connected = False
        return False

    try:
        conn = psycopg.connect(
            host=config.DB_HOST,
            port=config.DB_PORT,
            dbname=config.DB_NAME,
            user=config.DB_USER,
            password=config.DB_PASSWORD,
            sslmode=config.DB_SSLMODE,
            connect_timeout=3
        )
        conn.close()
        _is_connected = True
        return True
    except Exception:
        _is_connected = False
        return False


def get_connection():
    """Returns a new psycopg connection with dictionary row factory."""
    if not PSYCOPG_AVAILABLE:
        return None
    try:
        return psycopg.connect(
            host=config.DB_HOST,
            port=config.DB_PORT,
            dbname=config.DB_NAME,
            user=config.DB_USER,
            password=config.DB_PASSWORD,
            sslmode=config.DB_SSLMODE,
            row_factory=dict_row,
            autocommit=True
        )
    except Exception:
        return None


# ============================================================================
# IN-MEMORY DEMO DATA FIXTURES (Active when PostgreSQL credentials are pending)
# ============================================================================

now = datetime.now()
DEMO_FLIGHTS = [
    {
        "flight_instance_id": 1,
        "airline_name": "Air India",
        "airline_iata": "AI",
        "flight_number": "AI101",
        "origin_iata": "DEL",
        "origin_city": "New Delhi",
        "destination_iata": "JFK",
        "destination_city": "New York",
        "scheduled_departure": (now + timedelta(hours=1, minutes=15)).strftime("%Y-%m-%d %H:%M"),
        "estimated_departure": (now + timedelta(hours=1, minutes=15)).strftime("%Y-%m-%d %H:%M"),
        "scheduled_arrival": (now + timedelta(hours=17, minutes=15)).strftime("%Y-%m-%d %H:%M"),
        "estimated_arrival": (now + timedelta(hours=17, minutes=15)).strftime("%Y-%m-%d %H:%M"),
        "flight_status": "BOARDING",
        "delay_minutes": 0,
        "departure_terminal": "T3",
        "departure_gate": "10A",
        "arrival_terminal": "T4",
        "arrival_gate": "42B",
        "aircraft_tail_number": "VT-EXG",
        "aircraft_model": "Airbus A350-900"
    },
    {
        "flight_instance_id": 2,
        "airline_name": "Emirates",
        "airline_iata": "EK",
        "flight_number": "EK511",
        "origin_iata": "DEL",
        "origin_city": "New Delhi",
        "destination_iata": "DXB",
        "destination_city": "Dubai",
        "scheduled_departure": (now + timedelta(hours=2, minutes=40)).strftime("%Y-%m-%d %H:%M"),
        "estimated_departure": (now + timedelta(hours=3, minutes=10)).strftime("%Y-%m-%d %H:%M"),
        "scheduled_arrival": (now + timedelta(hours=6, minutes=40)).strftime("%Y-%m-%d %H:%M"),
        "estimated_arrival": (now + timedelta(hours=7, minutes=10)).strftime("%Y-%m-%d %H:%M"),
        "flight_status": "DELAYED",
        "delay_minutes": 30,
        "departure_terminal": "T3",
        "departure_gate": "12A",
        "arrival_terminal": "T3",
        "arrival_gate": "A15",
        "aircraft_tail_number": "A6-EPG",
        "aircraft_model": "Boeing 777-300ER"
    },
    {
        "flight_instance_id": 3,
        "airline_name": "British Airways",
        "airline_iata": "BA",
        "flight_number": "BA142",
        "origin_iata": "DEL",
        "origin_city": "New Delhi",
        "destination_iata": "LHR",
        "destination_city": "London",
        "scheduled_departure": (now + timedelta(hours=4)).strftime("%Y-%m-%d %H:%M"),
        "estimated_departure": (now + timedelta(hours=4)).strftime("%Y-%m-%d %H:%M"),
        "scheduled_arrival": (now + timedelta(hours=13, minutes=20)).strftime("%Y-%m-%d %H:%M"),
        "estimated_arrival": (now + timedelta(hours=13, minutes=20)).strftime("%Y-%m-%d %H:%M"),
        "flight_status": "SCHEDULED",
        "delay_minutes": 0,
        "departure_terminal": "T3",
        "departure_gate": "14",
        "arrival_terminal": "T5",
        "arrival_gate": "B32",
        "aircraft_tail_number": "G-XWBA",
        "aircraft_model": "Airbus A350-900"
    },
    {
        "flight_instance_id": 4,
        "airline_name": "Singapore Airlines",
        "airline_iata": "SQ",
        "flight_number": "SQ401",
        "origin_iata": "DEL",
        "origin_city": "New Delhi",
        "destination_iata": "SIN",
        "destination_city": "Singapore",
        "scheduled_departure": (now - timedelta(minutes=45)).strftime("%Y-%m-%d %H:%M"),
        "estimated_departure": (now - timedelta(minutes=40)).strftime("%Y-%m-%d %H:%M"),
        "scheduled_arrival": (now + timedelta(hours=5)).strftime("%Y-%m-%d %H:%M"),
        "estimated_arrival": (now + timedelta(hours=5, minutes=5)).strftime("%Y-%m-%d %H:%M"),
        "flight_status": "AIRBORNE",
        "delay_minutes": 5,
        "departure_terminal": "T3",
        "departure_gate": "16",
        "arrival_terminal": "T3",
        "arrival_gate": "B2",
        "aircraft_tail_number": "9V-SMA",
        "aircraft_model": "Airbus A350-900"
    },
    {
        "flight_instance_id": 5,
        "airline_name": "Emirates",
        "airline_iata": "EK",
        "flight_number": "EK201",
        "origin_iata": "DXB",
        "origin_city": "Dubai",
        "destination_iata": "JFK",
        "destination_city": "New York",
        "scheduled_departure": (now + timedelta(hours=5, minutes=30)).strftime("%Y-%m-%d %H:%M"),
        "estimated_departure": (now + timedelta(hours=5, minutes=30)).strftime("%Y-%m-%d %H:%M"),
        "scheduled_arrival": (now + timedelta(hours=19, minutes=50)).strftime("%Y-%m-%d %H:%M"),
        "estimated_arrival": (now + timedelta(hours=19, minutes=50)).strftime("%Y-%m-%d %H:%M"),
        "flight_status": "SCHEDULED",
        "delay_minutes": 0,
        "departure_terminal": "T3",
        "departure_gate": "10B",
        "arrival_terminal": "T4",
        "arrival_gate": "22",
        "aircraft_tail_number": "A6-EOA",
        "aircraft_model": "Airbus A350-900"
    }
]

DEMO_GATES = [
    {"gate_id": 1, "terminal_code": "T3", "gate_number": "10A", "gate_type": "WIDE_BODY", "status": "OCCUPIED", "current_flight": "AI101"},
    {"gate_id": 2, "terminal_code": "T3", "gate_number": "10B", "gate_type": "WIDE_BODY", "status": "RESERVED", "current_flight": "EK201"},
    {"gate_id": 3, "terminal_code": "T3", "gate_number": "12A", "gate_type": "WIDE_BODY", "status": "OCCUPIED", "current_flight": "EK511"},
    {"gate_id": 4, "terminal_code": "T3", "gate_number": "14", "gate_type": "NARROW_BODY", "status": "RESERVED", "current_flight": "BA142"},
    {"gate_id": 5, "terminal_code": "T3", "gate_number": "16", "gate_type": "NARROW_BODY", "status": "AVAILABLE", "current_flight": None},
    {"gate_id": 6, "terminal_code": "T3", "gate_number": "18", "gate_type": "NARROW_BODY", "status": "AVAILABLE", "current_flight": None},
    {"gate_id": 7, "terminal_code": "T3", "gate_number": "20A", "gate_type": "WIDE_BODY", "status": "AVAILABLE", "current_flight": None},
    {"gate_id": 8, "terminal_code": "T3", "gate_number": "22", "gate_type": "REGIONAL", "status": "MAINTENANCE", "current_flight": None},
]

DEMO_BOOKINGS = {
    "X8KJ2Q": {
        "booking_reference": "X8KJ2Q",
        "flight_number": "AI101",
        "passenger_name": "Aarav Sharma",
        "passport_number": "Z9821443",
        "seat_number": "12A",
        "seat_class": "BUSINESS",
        "ticket_price": 1450.00,
        "booking_status": "CONFIRMED",
        "barcode_token": "BP-X8KJ2Q-e9c52b",
        "boarding_group": "GRP2",
        "checked_baggage_count": 1,
        "total_baggage_weight_kg": 23.5
    }
}

DEMO_BAGGAGE = {
    "BAG-AI-90021": {
        "tag_number": "BAG-AI-90021",
        "booking_reference": "X8KJ2Q",
        "passenger_name": "Aarav Sharma",
        "flight_number": "AI101",
        "weight_kg": 23.5,
        "current_status": "LOADED",
        "timeline": [
            {"status": "CHECKED_IN", "location": "Terminal 3 Check-in Counter 12", "time": (now - timedelta(minutes=70)).strftime("%H:%M")},
            {"status": "SECURITY_CLEARED", "location": "In-line Explosive Detection System 2", "time": (now - timedelta(minutes=55)).strftime("%H:%M")},
            {"status": "LOADED", "location": "Ramp Area Gate 10A Forward Hold", "time": (now - timedelta(minutes=20)).strftime("%H:%M")}
        ]
    }
}
