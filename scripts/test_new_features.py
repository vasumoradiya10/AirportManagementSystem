import urllib.request
import json

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

print("=== 1. TESTING BAGGAGE CHECKPOINT SCAN ADVANCEMENT ===")
scan_req = {
    "event_status": "SECURITY_CLEARED",
    "checkpoint_location": "T3 Explosive Detection System X-Ray 2",
    "scanned_by": "Security Officer Mehra"
}
scan_res = post_json('/api/baggage/BAG-DUH-95846/scan', scan_req)
print(f"[PASS] Scan logged: {scan_res.get('message')}")

# Verify bag tracking reflects new milestone
bag_data = get_json('/api/baggage/BAG-DUH-95846')
print(f"       Current Status: {bag_data.get('current_status')}")
print(f"       Total Milestones: {len(bag_data.get('scans', []))}")
for s in bag_data.get('scans', []):
    print(f"         - {s.get('time')} | {s.get('event')} @ {s.get('location')} [{s.get('scanned_by')}]")

print("\n=== 2. TESTING FLIGHT DELAY UPDATE VIA STORED PROCEDURE ===")
delay_req = {
    "delay_minutes": 35,
    "delay_reason": "ATC Slot Delay & Late Inbound Ground Turnaround"
}
delay_res = post_json('/api/flights/1/delay', delay_req)
print(f"[PASS] Delay updated: {delay_res.get('message')}")

# Verify FIDS reflects delay
fids_data = get_json('/api/flights/live-board')
f1 = next((f for f in fids_data.get('flights', []) if f['flight_instance_id'] == 1), None)
if f1:
    print(f"       Flight {f1.get('flight_number')} status: {f1.get('flight_status')}, delay: +{f1.get('delay_minutes')}m")
