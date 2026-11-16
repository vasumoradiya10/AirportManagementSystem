import urllib.request
import json
import sys

base = 'http://127.0.0.1:8080'

endpoints = [
    '/api/health',
    '/api/flights/stats',
    '/api/flights/live-board',
    '/api/flights/tracking',
    '/api/gates',
    '/api/baggage',
    '/api/baggage/BAG-AI-88910',
    '/api/analytics/performance',
    '/api/analytics/turnaround',
    '/api/analytics/gate-utilization',
    '/api/analytics/routes/search?origin=DEL&dest=JFK',
    '/api/bookings/AUKKAR',
]

print("=== VERIFYING INTEGRATED AIRPORT MANAGEMENT SYSTEM ENDPOINTS ===")
all_pass = True
for ep in endpoints:
    try:
        with urllib.request.urlopen(base + ep, timeout=5) as resp:
            data = json.loads(resp.read().decode())
            src = data.get("source", "N/A")
            keys = list(data.keys())
            print(f"[PASS] {ep:<45} | status: {resp.status} | source: {src} | keys: {keys[:4]}")
    except Exception as e:
        print(f"[FAIL] {ep:<45} | ERROR: {e}")
        all_pass = False

print(f"\nAll tests passed: {all_pass}")
