"""
Pydantic models for API request and response data structures.
"""

from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime


class FlightDelayRequest(BaseModel):
    delay_minutes: int = Field(..., ge=0, le=1440, description="Delay in minutes")
    delay_reason: Optional[str] = Field("Operational delay", description="Reason for delay")


class GateAssignRequest(BaseModel):
    flight_instance_id: int
    gate_id: int
    assignment_type: str = Field("DEPARTURE", pattern="^(DEPARTURE|ARRIVAL)$")


class BookingCreateRequest(BaseModel):
    flight_instance_id: int
    first_name: str
    last_name: str
    passport_number: str
    email: str
    seat_number: str
    seat_class: str = Field("ECONOMY", pattern="^(ECONOMY|PREMIUM_ECONOMY|BUSINESS|FIRST)$")
    ticket_price: float = 450.00


class BaggageScanRequest(BaseModel):
    event_status: str = Field(..., pattern="^(CHECKED_IN|SECURITY_CLEARED|RAMP_LOADED|LOADED|TRANSFER_HOLD|UNLOADED|CAROUSEL_ARRIVED|CLAIMED)$")
    checkpoint_location: str
    scanned_by: Optional[str] = "Station Agent"


class ItinerarySearchRequest(BaseModel):
    origin: str = Field(..., min_length=3, max_length=3)
    destination: str = Field(..., min_length=3, max_length=3)
    max_layover_hours: Optional[int] = 8


class SqlQueryRequest(BaseModel):
    query: str = Field(..., description="SQL SELECT query to execute against PostgreSQL")

