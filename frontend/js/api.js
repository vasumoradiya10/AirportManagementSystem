/**
 * AeroOps API Client
 * Thin wrapper around all backend REST endpoints.
 */

const API = (() => {
  const BASE = '';

  async function get(path) {
    const res = await fetch(BASE + path);
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err.detail || `HTTP ${res.status}`);
    }
    return res.json();
  }

  async function post(path, body) {
    const res = await fetch(BASE + path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err.detail || `HTTP ${res.status}`);
    }
    return res.json();
  }

  return {
    // ── System ──────────────────────────────────────────────────────
    health:            ()            => get('/api/health'),
    stats:             ()            => get('/api/flights/stats'),

    // ── Flights ─────────────────────────────────────────────────────
    liveBoard:         (params = {}) => {
      const q = new URLSearchParams(Object.fromEntries(Object.entries(params).filter(([,v]) => v)));
      return get(`/api/flights/live-board${q.toString() ? '?' + q : ''}`);
    },
    tracking:          ()            => get('/api/flights/tracking'),
    opensky:           ()            => get('/api/flights/opensky'),
    delayFlight:       (id, body)    => post(`/api/flights/${id}/delay`, body),

    // ── Gates ───────────────────────────────────────────────────────
    gates:             ()            => get('/api/gates'),
    assignGate:        (body)        => post('/api/gates/assign', body),

    // ── Bookings ────────────────────────────────────────────────────
    createBooking:     (body)        => post('/api/bookings/reserve', body),
    getBooking:        (pnr)         => get(`/api/bookings/${encodeURIComponent(pnr)}`),

    // ── Baggage ─────────────────────────────────────────────────────
    allBaggage:        ()            => get('/api/baggage'),
    trackBaggage:      (tag)         => get(`/api/baggage/${encodeURIComponent(tag)}`),
    scanBaggage:       (tag, body)   => post(`/api/baggage/${encodeURIComponent(tag)}/scan`, body),

    // ── Analytics ───────────────────────────────────────────────────
    mapData:           ()            => get('/api/analytics/map-data'),
    searchRoutes:      (orig, dest)  => get(`/api/analytics/routes/search?origin=${orig}&dest=${dest}`),
    turnaround:        ()            => get('/api/analytics/turnaround'),
    performance:       ()            => get('/api/analytics/performance'),
    gateUtilization:   ()            => get('/api/analytics/gate-utilization'),
  };
})();

// Export for ES module consumption
export default API;
