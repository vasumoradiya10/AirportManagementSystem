import urllib.request
import json
import sys

base = 'http://127.0.0.1:8080'

def post_json(path, data):
    req = urllib.request.Request(
        base + path,
        data=json.dumps(data).encode('utf-8'),
        headers={'Content-Type': 'application/json'}
    )
    with urllib.request.urlopen(req, timeout=5) as resp:
        return json.loads(resp.read().decode())

def get_json(path):
    with urllib.request.urlopen(base + path, timeout=5) as resp:
        return json.loads(resp.read().decode())

print("=== 1. TESTING TRANSACTIONAL BOOKING + AUTO BAGGAGE INTEGRATION ===")
# We book seat 18B on flight_instance_id 1 (AI101, BOARDING)
booking_req = {
    "flight_instance_id": 1,
    "first_name": "Priya",
    "last_name": "Sharma",
    "passport_number": "P11223344",
    "email": "priya.sharma@example.com",
    "seat_number": "19C",
    "seat_class": "ECONOMY",
    "ticket_price": 450.0
}
try:
    booking_res = post_json('/api/bookings/reserve', booking_req)
    print(f"[PASS] Booking Created successfully:")
    print(f"       PNR: {booking_res.get('booking_reference')}")
    print(f"       Seat: {booking_res.get('seat_number')} ({booking_res.get('seat_class')})")
    print(f"       Auto Luggage Tag: {booking_res.get('baggage_tag')}")

    pnr = booking_res.get('booking_reference')
    tag = booking_res.get('baggage_tag')

    # Test tracking luggage by PNR
    print(f"\n=== 2. TESTING BAGGAGE TRACKING BY BOOKING PNR ({pnr}) ===")
    bag_by_pnr = get_json(f'/api/baggage/{pnr}')
    print(f"[PASS] Baggage retrieved via PNR:")
    print(f"       Tag: {bag_by_pnr.get('tag_number')}")
    print(f"       Passenger: {bag_by_pnr.get('passenger_name')}")
    print(f"       Flight: {bag_by_pnr.get('flight_number')} ({bag_by_pnr.get('airline_name')})")
    print(f"       Route: {bag_by_pnr.get('route')}")
    print(f"       Current Status: {bag_by_pnr.get('current_status')}")
    print(f"       Milestones count: {len(bag_by_pnr.get('scans', []))}")

    # Test boarding pass retrieval
    print(f"\n=== 3. TESTING BOARDING PASS BY PNR ({pnr}) ===")
    bp_res = get_json(f'/api/bookings/{pnr}')
    print(f"[PASS] Boarding pass retrieved:")
    print(f"       Passenger: {bp_res.get('passenger_name')}")
    print(f"       Flight: {bp_res.get('flight_number')} | {bp_res.get('airline_name')}")
    print(f"       Route: {bp_res.get('origin_iata')} -> {bp_res.get('destination_iata')}")
    print(f"       Seat: {bp_res.get('seat_number')} | Barcode: {bp_res.get('barcode_token')}")

except Exception as e:
    print(f"[FAIL] Booking or Tracking Error: {e}")

print("\n=== 4. TESTING ALL BAGGAGE IN AIRPORT ===")
bags = get_json('/api/baggage')
print(f"[PASS] Total checked bags in database: {bags.get('count')}")
for b in bags.get('baggage_list', [])[:5]:
    print(f"       Bag {b.get('tag_number')}: {b.get('passenger_name')} | Flight {b.get('flight_number')} | {b.get('current_status')} @ {b.get('last_location')}")
