/**
 * AeroOps — Main Application Controller  v2.0
 * Handles: tab routing, stats bar, FIDS, live map tracking,
 *          gate management, bookings, baggage, analytics & SQL workbench.
 */

import API from './api.js';

// ─────────────────────────────────────────────────────────────────────────────
// BOOT
// ─────────────────────────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  initClock();
  initTabs();
  loadHealth();
  loadStats();
  loadFlights();
  loadGates();
  populateFlightSelects();
  initBooking();
  initPnrLookup();
  initBaggage();
  initRouteForm();
  initGateForm();
  initDelayForm();
  initAnalyticsButtons();
  initOpenSkyButton();
  loadTrackingData();

  // Auto-refresh intervals
  setInterval(loadStats, 30_000);
  setInterval(loadFlights, 15_000);
  setInterval(loadTrackingData, 15_000);
});

// ─────────────────────────────────────────────────────────────────────────────
// 1. UTC CLOCK
// ─────────────────────────────────────────────────────────────────────────────
function initClock() {
  const el = document.getElementById('utc-clock');
  const tick = () => {
    if (el) {
      const now = new Date();
      el.textContent = now.toUTCString().replace(' GMT', ' UTC');
    }
  };
  tick();
  setInterval(tick, 1000);
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. TAB ROUTING
// ─────────────────────────────────────────────────────────────────────────────
function initTabs() {
  const btns = document.querySelectorAll('.tab-btn');
  btns.forEach(btn => {
    btn.addEventListener('click', () => {
      btns.forEach(b => b.classList.remove('active'));
      document.querySelectorAll('.tab-pane').forEach(p => p.classList.remove('active'));

      btn.classList.add('active');
      const id = 'tab-' + btn.dataset.tab;
      const pane = document.getElementById(id);
      if (pane) pane.classList.add('active');

      if (btn.dataset.tab === 'map') {
        loadTrackingData();
      }
    });
  });
}


// ─────────────────────────────────────────────────────────────────────────────
// 3. HEALTH & DB STATUS
// ─────────────────────────────────────────────────────────────────────────────
async function loadHealth() {
  const dot  = document.getElementById('pulse-dot');
  const text = document.getElementById('db-badge-text');
  try {
    const h = await API.health();
    if (h.database?.connected) {
      dot.style.background = 'var(--green)';
      dot.style.boxShadow  = '0 0 6px var(--green)';
      text.textContent = `PostgreSQL · ${h.database.host}`;
    } else {
      dot.style.background = 'var(--amber)';
      text.textContent = 'Demo Mode';
    }
  } catch {
    dot.style.background = 'var(--red)';
    text.textContent = 'Offline';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. STATS BAR
// ─────────────────────────────────────────────────────────────────────────────
async function loadStats() {
  try {
    const d = await API.stats();
    const f = d.flights || {};
    const g = d.gates   || {};
    document.getElementById('stat-total').textContent    = f.total_flights ?? '—';
    document.getElementById('stat-airborne').textContent = f.airborne       ?? '—';
    document.getElementById('stat-boarding').textContent = f.boarding        ?? '—';
    document.getElementById('stat-delayed').textContent  = f.delayed         ?? '—';
    document.getElementById('stat-sched').textContent    = f.scheduled       ?? '—';
    document.getElementById('stat-gates').textContent    = g.occupied_gates != null
      ? `${g.occupied_gates}/${g.total_gates}` : '—';
  } catch (e) {
    console.warn('[Stats]', e.message);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. FIDS — LIVE FLIGHT BOARD
// ─────────────────────────────────────────────────────────────────────────────
async function loadFlights() {
  const tbody  = document.getElementById('fids-body');
  const status = document.getElementById('filter-status')?.value;
  const search = document.getElementById('search-fids')?.value?.trim().toLowerCase();
  if (!tbody) return;

  try {
    const data = await API.liveBoard({ status });
    let rows = data.flights || [];

    if (search) {
      rows = rows.filter(f =>
        (f.flight_number || '').toLowerCase().includes(search) ||
        (f.airline_name || '').toLowerCase().includes(search) ||
        (f.origin_iata || '').toLowerCase().includes(search) ||
        (f.destination_iata || '').toLowerCase().includes(search) ||
        (f.origin_city || '').toLowerCase().includes(search) ||
        (f.destination_city || '').toLowerCase().includes(search)
      );
    }

    if (!rows.length) {
      tbody.innerHTML = `<tr><td colspan="8" style="text-align:center;padding:2rem;color:var(--text-muted);">No flights match the current search or filter.</td></tr>`;
      return;
    }
    tbody.innerHTML = rows.map(f => {
      const delay = f.delay_minutes > 0
        ? `<span style="color:var(--amber);font-family:var(--font-mono);font-size:0.78rem;">+${f.delay_minutes}m</span>`
        : '<span style="color:var(--text-muted);">—</span>';
      const gate = f.departure_gate
        ? `<span style="font-family:var(--font-mono);color:var(--cyan);">${f.departure_gate}</span>`
        : '<span style="color:var(--text-muted);">TBD</span>';
      return `<tr>
        <td><span class="flt-code">${f.flight_number}</span></td>
        <td style="color:var(--text-secondary);font-size:0.78rem;">${f.airline_name}</td>
        <td>
          <div class="airport-pair">
            <span class="iata">${f.origin_iata}</span>
            <span class="arrow">→</span>
            <span class="iata">${f.destination_iata}</span>
          </div>
          <div style="font-size:0.7rem;color:var(--text-muted);">${f.origin_city} → ${f.destination_city}</div>
        </td>
        <td class="time-cell">${(f.scheduled_departure || '').slice(11,16) || '—'}</td>
        <td class="time-cell">${(f.scheduled_arrival   || '').slice(11,16) || '—'}</td>
        <td><span class="badge badge-${f.flight_status}">${f.flight_status}</span></td>
        <td>${gate}</td>
        <td>${delay}</td>
      </tr>`;
    }).join('');
  } catch (e) {
    tbody.innerHTML = `<tr><td colspan="8" style="color:var(--red);text-align:center;padding:2rem;">${e.message}</td></tr>`;
  }
}

document.getElementById('filter-status')?.addEventListener('change', loadFlights);
document.getElementById('search-fids')?.addEventListener('input', loadFlights);
document.getElementById('btn-refresh-fids')?.addEventListener('click', loadFlights);

// ─────────────────────────────────────────────────────────────────────────────
// 6. GATE MANAGEMENT
// ─────────────────────────────────────────────────────────────────────────────
async function loadGates() {
  const container = document.getElementById('gate-grid');
  if (!container) return;
  try {
    const data = await API.gates();
    const gates = data.gates || [];
    if (!gates.length) {
      container.innerHTML = `<div class="empty-state"><div class="empty-icon">🚪</div><div class="empty-text">No gate data available.</div></div>`;
      return;
    }
    container.innerHTML = gates.map(g => {
      const cls = g.status === 'OCCUPIED' ? 'occupied' : 'available';
      const flt = g.current_flight_number
        ? `<div class="gate-flight" style="font-weight:700;color:var(--cyan);margin-top:6px;">✈ ${g.current_flight_number} · ${g.origin_iata || 'DEL'} ➔ ${g.destination_iata || ''}</div>
           <div style="font-size:0.72rem;color:var(--text-muted);margin-top:2px;">${g.airline_name || ''} · <span class="badge badge-${g.flight_status || 'BOARDING'}">${g.flight_status || 'BOARDING'}</span></div>`
        : `<div style="font-size:0.75rem;color:var(--text-muted);margin-top:6px;">No flight stationed</div>`;

      return `<div class="gate-card ${cls}">
        <div class="gate-num">${g.gate_number}</div>
        <div class="gate-info">${g.terminal_name || g.terminal_code || ''} · ${g.gate_type || ''}</div>
        <div style="margin-top:5px;"><span class="badge badge-${g.status}" style="font-size:0.65rem;">${g.status}</span></div>
        ${flt}
      </div>`;
    }).join('');
  } catch (e) {
    container.innerHTML = `<div class="empty-state"><div class="empty-text" style="color:var(--red)">${e.message}</div></div>`;
  }
}


document.getElementById('btn-refresh-gates')?.addEventListener('click', loadGates);

// ─────────────────────────────────────────────────────────────────────────────
// 7. POPULATE FLIGHT DROPDOWNS
// ─────────────────────────────────────────────────────────────────────────────
async function populateFlightSelects() {
  try {
    const data = await API.liveBoard({});
    const flights = data.flights || [];
    const opts = flights.map(f =>
      `<option value="${f.flight_instance_id}">${f.flight_number} — ${f.origin_iata}→${f.destination_iata} (${(f.scheduled_departure||'').slice(11,16)})</option>`
    ).join('');

    const selects = ['book-flight-id', 'assign-flight-id', 'delay-flight-id'];
    selects.forEach(id => {
      const el = document.getElementById(id);
      if (el) {
        el.innerHTML = `<option value="">Select flight…</option>` + opts;
      }
    });

    // Populate gate select for assign form
    const gateData = await API.gates();
    const gates = gateData.gates || [];
    const gateOpts = gates.map(g =>
      `<option value="${g.gate_id}">${g.gate_number} — ${g.terminal_name || ''} (${g.status})</option>`
    ).join('');
    const gateEl = document.getElementById('assign-gate-id');
    if (gateEl) gateEl.innerHTML = `<option value="">Select gate…</option>` + gateOpts;
  } catch (e) {
    console.warn('[Populate selects]', e.message);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 7B. FLIGHT DELAY MANAGEMENT FORM
// ─────────────────────────────────────────────────────────────────────────────
function initDelayForm() {
  const form = document.getElementById('form-delay-flight');
  const result = document.getElementById('delay-result');
  if (!form) return;

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const btn = document.getElementById('btn-delay-submit');
    const fId = parseInt(document.getElementById('delay-flight-id').value);
    const mins = parseInt(document.getElementById('delay-mins').value);
    const reason = document.getElementById('delay-reason').value.trim();

    if (!fId) {
      if (result) result.innerHTML = `<div class="alert alert-error">Please select a flight.</div>`;
      return;
    }

    btn.disabled = true;
    btn.innerHTML = '<span class="spin">⟳</span> Updating…';
    if (result) result.innerHTML = '';

    try {
      const data = await API.delayFlight(fId, {
        delay_minutes: mins,
        delay_reason: reason
      });
      result.innerHTML = `<div class="alert alert-success">✓ ${data.message || 'Flight delay updated successfully!'}</div>`;
      loadFlights();
      loadStats();
      loadOTP();
    } catch (err) {
      result.innerHTML = `<div class="alert alert-error">✗ ${err.message}</div>`;
    } finally {
      btn.disabled = false;
      btn.textContent = 'Update Delay';
    }
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 8. GATE ASSIGNMENT FORM
// ─────────────────────────────────────────────────────────────────────────────
function initGateForm() {
  const form = document.getElementById('form-assign-gate');
  const result = document.getElementById('gate-assign-result');
  if (!form) return;

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const btn = form.querySelector('button[type=submit]');
    btn.disabled = true;
    btn.innerHTML = '<span class="spin">⟳</span> Assigning…';
    if (result) result.innerHTML = '';
    try {
      const data = await API.assignGate({
        flight_instance_id: parseInt(document.getElementById('assign-flight-id').value),
        gate_id: parseInt(document.getElementById('assign-gate-id').value),
        assignment_type: document.getElementById('assign-type').value,
      });
      result.innerHTML = `<div class="alert alert-success">✓ ${data.message || 'Gate assigned successfully!'}</div>`;
      loadGates();
    } catch (err) {
      result.innerHTML = `<div class="alert alert-error">✗ ${err.message}</div>`;
    } finally {
      btn.disabled = false;
      btn.textContent = 'Assign Gate';
    }
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 9. BOOKING FORM
// ─────────────────────────────────────────────────────────────────────────────
const PRICES = { ECONOMY: 450, PREMIUM_ECONOMY: 750, BUSINESS: 1450, FIRST: 2500 };

function initBooking() {
  const form   = document.getElementById('form-book-seat');
  const result = document.getElementById('book-result');
  if (!form) return;

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const btn = document.getElementById('btn-book-submit');
    btn.disabled = true;
    btn.innerHTML = '<span class="spin">⟳</span> Processing…';
    if (result) result.innerHTML = '';

    const cls = document.getElementById('book-class').value;
    try {
      const data = await API.createBooking({
        flight_instance_id: parseInt(document.getElementById('book-flight-id').value),
        first_name:         document.getElementById('book-fname').value.trim(),
        last_name:          document.getElementById('book-lname').value.trim(),
        passport_number:    document.getElementById('book-passport').value.trim(),
        email:              document.getElementById('book-email').value.trim(),
        seat_number:        document.getElementById('book-seat').value.trim().toUpperCase(),
        seat_class:         cls,
        ticket_price:       PRICES[cls] || 450,
      });

      result.innerHTML = `<div class="alert alert-success">
        <div>✓ Seat Confirmed! PNR: <strong style="font-family:var(--font-mono);color:var(--amber)">${data.booking_reference}</strong> — Seat <strong>${data.seat_number}</strong> (${data.seat_class})</div>
        ${data.baggage_tag ? `<div style="margin-top:6px;font-size:0.8rem;">🧳 Checked Baggage Tag: <strong style="font-family:var(--font-mono);color:var(--cyan)">${data.baggage_tag}</strong>
          <button type="button" class="btn btn-secondary btn-sm" style="margin-left:8px;padding:2px 8px;font-size:0.72rem;" onclick="window.trackBag('${data.baggage_tag}')">Track Luggage ➔</button>
        </div>` : ''}
      </div>`;
      form.reset();
      loadBaggageList();
    } catch (err) {
      result.innerHTML = `<div class="alert alert-error">✗ ${err.message}</div>`;
    } finally {
      btn.disabled = false;
      btn.textContent = 'Book Seat';
    }
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 10. PNR LOOKUP & BOARDING PASS
// ─────────────────────────────────────────────────────────────────────────────
function initPnrLookup() {
  const form = document.getElementById('form-lookup-pnr');
  if (!form) return;
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const pnr = document.getElementById('lookup-pnr-input').value.trim().toUpperCase();
    const container = document.getElementById('boarding-pass-container');
    if (!pnr || !container) return;
    container.innerHTML = `<div class="empty-state"><div class="spin" style="font-size:1.5rem;">⟳</div></div>`;
    try {
      const data = await API.getBooking(pnr);
      const b = data.booking || data;
      container.innerHTML = renderBoardingPass(b);
    } catch (err) {
      container.innerHTML = `<div class="alert alert-error" style="margin-top:0.75rem;">✗ ${err.message}</div>`;
    }
  });

  window.lookupPnr = (pnr) => {
    const input = document.getElementById('lookup-pnr-input');
    if (input) input.value = pnr;
    const form = document.getElementById('form-lookup-pnr');
    if (form) form.dispatchEvent(new Event('submit'));
  };
}

function renderBoardingPass(b) {
  return `
  <div class="boarding-pass" style="margin-top:0.9rem;">
    <div class="bp-top">
      <div>
        <div class="bp-airline">${b.airline_name || 'Flight'}</div>
        <div class="bp-flight-num">${b.flight_number || '—'}</div>
      </div>
      <div style="text-align:right;">
        <div class="bp-pnr-label">PNR</div>
        <div class="bp-pnr">${b.booking_reference}</div>
      </div>
    </div>
    <div class="bp-route">
      <div>
        <div class="bp-airport-code">${b.origin_iata || '—'}</div>
        <div class="bp-city">${b.origin_city || ''}</div>
      </div>
      <div class="bp-plane-icon">✈</div>
      <div style="text-align:right;">
        <div class="bp-airport-code">${b.destination_iata || '—'}</div>
        <div class="bp-city">${b.destination_city || ''}</div>
      </div>
    </div>
    <div class="bp-bottom">
      <div>
        <div class="bp-field-label">Passenger</div>
        <div class="bp-field-val" style="font-size:0.95rem;">${b.passenger_name || '—'}</div>
      </div>
      <div>
        <div class="bp-field-label">Seat</div>
        <div class="bp-field-val" style="color:var(--cyan);font-family:var(--font-mono);">${b.seat_number}</div>
      </div>
      <div>
        <div class="bp-field-label">Class</div>
        <div class="bp-field-val" style="font-size:0.85rem;">${b.seat_class}</div>
      </div>
      <div>
        <div class="bp-field-label">Group</div>
        <div class="bp-field-val" style="color:var(--cyan);font-family:var(--font-mono);">${b.boarding_group || '—'}</div>
      </div>
    </div>
    <div class="bp-barcode">
      ▌▌▌▌▌▌▌ ${b.barcode_token || b.booking_reference} ▌▌▌▌▌▌▌
    </div>
  </div>`;
}

// ─────────────────────────────────────────────────────────────────────────────
// 11. BAGGAGE TRACKING
// ─────────────────────────────────────────────────────────────────────────────
function initBaggage() {
  const form = document.getElementById('form-baggage');
  const input = document.getElementById('input-bag-tag');
  const result = document.getElementById('baggage-result');

  async function performTrack(query) {
    if (!query || !result) return;
    if (input) input.value = query;
    result.innerHTML = `<div class="empty-state"><div class="spin" style="font-size:1.5rem;">⟳</div><div class="empty-text">Tracking luggage across checkpoints…</div></div>`;

    try {
      const data = await API.trackBaggage(query);
      const scans = data.timeline || data.scans || [];

      result.innerHTML = `
        <div class="card" style="margin-top:1rem;background:rgba(255,255,255,0.02);border-color:rgba(56,189,248,0.3);">
          <div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:0.5rem;margin-bottom:0.85rem;">
            <div>
              <span style="font-family:var(--font-mono);font-size:1.15rem;font-weight:700;color:var(--cyan);">${data.tag_number}</span>
              <span class="badge badge-${data.current_status === 'LOADED' ? 'AIRBORNE' : data.current_status === 'CHECKED_IN' ? 'BOARDING' : 'SCHEDULED'}" style="margin-left:8px;">
                ${data.current_status}
              </span>
            </div>
            <div style="font-family:var(--font-mono);font-size:0.85rem;color:var(--amber);font-weight:700;">
              PNR: ${data.booking_reference}
            </div>
          </div>
          <div style="display:grid;grid-template-columns:repeat(auto-fit, minmax(150px, 1fr));gap:0.75rem;font-size:0.8rem;margin-bottom:1.25rem;background:rgba(0,0,0,0.25);padding:0.75rem;border-radius:var(--radius);">
            <div><span style="color:var(--text-muted);display:block;font-size:0.7rem;">PASSENGER</span><strong>${data.passenger_name}</strong></div>
            <div><span style="color:var(--text-muted);display:block;font-size:0.7rem;">FLIGHT</span><strong style="color:var(--cyan);font-family:var(--font-mono);">${data.flight_number}</strong> (${data.airline_name || ''})</div>
            <div><span style="color:var(--text-muted);display:block;font-size:0.7rem;">ROUTING</span><strong>${data.route}</strong></div>
            <div><span style="color:var(--text-muted);display:block;font-size:0.7rem;">WEIGHT</span><strong style="font-family:var(--font-mono);">${data.weight_kg} kg</strong></div>
          </div>

          <div style="font-size:0.75rem;font-weight:700;color:var(--text-muted);text-transform:uppercase;margin-bottom:0.75rem;letter-spacing:0.05em;">
            Milestone Tracking Scan Events:
          </div>
          ${!scans.length ? `<div style="color:var(--text-muted);font-size:0.8rem;">Initial check-in scan logged. Awaiting next security transit checkpoint.</div>` : `
          <div class="timeline">
            ${scans.map((s, i) => `
              <div class="timeline-item">
                <div class="timeline-dot ${i < scans.length - 1 ? 'past' : ''}"></div>
                <div class="timeline-time">${s.scanned_at || s.time || ''}</div>
                <div class="timeline-event">${s.event || s.scan_event || ''}</div>
                <div class="timeline-loc">${s.location || ''} ${s.scanned_by ? `· <span style="color:var(--text-muted);font-size:0.72rem;">[${s.scanned_by}]</span>` : ''}</div>
              </div>
            `).join('')}
          </div>`}

          ${(() => {
            const nextSteps = {
              'CHECKED_IN': { status: 'SECURITY_CLEARED', loc: 'T3 Main Explosive Detection System X-Ray 2' },
              'SECURITY_CLEARED': { status: 'RAMP_LOADED', loc: 'Apron Baggage Conveyor Tug Cart' },
              'RAMP_LOADED': { status: 'LOADED', loc: 'Aircraft Cargo Hold Section 2' },
              'LOADED': { status: 'UNLOADED', loc: 'Arrival Tarmac Unloading Belt' },
              'UNLOADED': { status: 'CAROUSEL_ARRIVED', loc: 'Terminal Arrival Baggage Belt 04' },
              'CAROUSEL_ARRIVED': { status: 'CLAIMED', loc: 'Passenger Exit Baggage Turnstile' },
            };
            const next = nextSteps[data.current_status];
            if (!next) return `<div style="margin-top:0.75rem;font-size:0.75rem;color:var(--green);">✓ All transit checkpoints completed (Luggage Claimed).</div>`;
            return `
              <div style="margin-top:1rem;display:flex;justify-content:flex-end;">
                <button type="button" class="btn btn-secondary btn-sm"
                        style="font-family:var(--font-mono);font-size:0.75rem;"
                        onclick="window.advanceBagScan('${data.tag_number}', '${next.status}', '${next.loc}')">
                  ⏩ Advance Checkpoint: ${next.status} ➔
                </button>
              </div>`;
          })()}
        </div>
      `;
    } catch (err) {
      result.innerHTML = `<div class="alert alert-error" style="margin-top:0.75rem;">✗ ${err.message}</div>`;
    }
  }

  // Global helper to advance baggage scan
  window.advanceBagScan = async (tag, nextStatus, nextLoc) => {
    try {
      await API.scanBaggage(tag, {
        event_status: nextStatus,
        checkpoint_location: nextLoc,
        scanned_by: 'Airport Operations Agent'
      });
      loadBaggageList();
      performTrack(tag);
    } catch (err) {
      alert('Checkpoint scan error: ' + err.message);
    }
  };

  // Global helper to switch to baggage tab and track
  window.trackBag = (tag) => {
    document.querySelectorAll('.tab-btn').forEach(b => b.classList.toggle('active', b.dataset.tab === 'baggage'));
    document.querySelectorAll('.tab-pane').forEach(p => p.classList.toggle('active', p.id === 'tab-baggage'));
    performTrack(tag);
  };

  if (form) {
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      performTrack(input.value.trim());
    });
  }

  document.getElementById('btn-refresh-baggage-list')?.addEventListener('click', loadBaggageList);
  loadBaggageList();
}

async function loadBaggageList() {
  const container = document.getElementById('baggage-chips-container');
  if (!container) return;
  try {
    const data = await API.allBaggage();
    const bags = data.baggage_list || [];
    if (!bags.length) {
      container.innerHTML = `<span style="font-size:0.75rem;color:var(--text-muted);">No baggage checked in yet.</span>`;
      return;
    }
    container.innerHTML = bags.map(b => `
      <button type="button" class="btn btn-secondary btn-sm"
              style="font-family:var(--font-mono);font-size:0.72rem;padding:4px 9px;"
              onclick="window.trackBag('${b.tag_number}')">
        🧳 ${b.tag_number} <span style="color:var(--text-muted);">(${b.passenger_name.split(' ')[0]} · ${b.flight_number})</span>
      </button>
    `).join('');
  } catch (e) {
    container.innerHTML = `<span style="font-size:0.75rem;color:var(--amber);">Could not load baggage list.</span>`;
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// 12. ROUTE PATHFINDER
// ─────────────────────────────────────────────────────────────────────────────
function initRouteForm() {
  const form = document.getElementById('form-route');
  if (!form) return;
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const orig = document.getElementById('route-origin').value.trim().toUpperCase();
    const dest = document.getElementById('route-dest').value.trim().toUpperCase();
    const btn  = form.querySelector('button[type=submit]');
    const out  = document.getElementById('route-results');
    if (!orig || !dest || !out) return;

    btn.disabled = true;
    btn.innerHTML = '<span class="spin">⟳</span> Searching…';
    out.innerHTML = '';

    try {
      const data = await API.searchRoutes(orig, dest);
      const itins = data.itineraries || data.results || [];
      if (!itins.length) {
        out.innerHTML = `<div class="empty-state"><div class="empty-icon">🚫</div><div class="empty-text">No routes found from ${orig} to ${dest}.</div></div>`;
      } else {
        out.innerHTML = itins.map(it => {
          const route   = it.route_path || (Array.isArray(it.full_route) ? it.full_route.join(' → ') : it.full_route) || `${orig} → ${dest}`;
          const legs    = it.total_legs === 1 ? 'Direct' : `${it.total_legs} legs`;
          const layover = it.total_layover_mins > 0 ? `· ${Math.round(it.total_layover_mins / 60)}h layover` : '';
          const hrs     = Math.floor(it.total_flight_mins / 60);
          const mins    = it.total_flight_mins % 60;
          return `<div class="itinerary-card">
            <div class="itin-route">${route}</div>
            <div>
              <div class="itin-meta">${legs} ${layover}</div>
              <div class="itin-meta">✈ ${hrs}h ${mins}m flight time</div>
            </div>
            <div><span class="badge badge-${it.total_legs === 1 ? 'BOARDING' : 'SCHEDULED'} itin-badge">${it.total_legs === 1 ? 'DIRECT' : 'CONNECTING'}</span></div>
          </div>`;
        }).join('');
      }
    } catch (err) {
      out.innerHTML = `<div class="alert alert-error">✗ ${err.message}</div>`;
    } finally {
      btn.disabled = false;
      btn.textContent = 'Find Routes';
    }
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 13. ANALYTICS (TURNAROUND + OTP + GATE UTILIZATION)
// ─────────────────────────────────────────────────────────────────────────────
function initAnalyticsButtons() {
  document.getElementById('btn-refresh-analytics')?.addEventListener('click', loadTurnaround);
  document.getElementById('btn-refresh-otp')?.addEventListener('click', loadOTP);
  document.getElementById('btn-refresh-gate-analytics')?.addEventListener('click', loadGateUtilization);

  // Initial load
  loadOTP();
  loadTurnaround();
  loadGateUtilization();
}

async function loadTurnaround() {
  const tbody = document.getElementById('turnaround-body');
  if (!tbody) return;
  tbody.innerHTML = `<tr><td colspan="6" style="text-align:center;padding:1.5rem;color:var(--text-muted);"><span class="spin">⟳</span> Loading…</td></tr>`;
  try {
    const data = await API.turnaround();
    const rows = data.turnaround || [];
    if (!rows.length) {
      tbody.innerHTML = `<tr><td colspan="6" style="text-align:center;padding:2rem;color:var(--text-muted);">No data available.</td></tr>`;
      return;
    }
    tbody.innerHTML = rows.map(r => {
      const critical = r.turnaround_minutes < 45 || r.assessment === 'CRITICAL';
      return `<tr>
        <td><span style="font-family:var(--font-mono);color:var(--cyan);">${r.tail_number}</span></td>
        <td style="color:var(--text-secondary);font-size:0.78rem;">${r.model_name}</td>
        <td><span class="flt-code">${r.flight_number}</span></td>
        <td><div class="airport-pair"><span class="iata">${r.origin}</span><span class="arrow">→</span><span class="iata">${r.destination}</span></div></td>
        <td style="font-family:var(--font-mono);font-weight:700;color:${critical ? 'var(--red)' : 'var(--green)'};">${r.turnaround_minutes} min</td>
        <td><span class="badge badge-${critical ? 'DELAYED' : 'BOARDING'}">${r.assessment}</span></td>
      </tr>`;
    }).join('');
  } catch (err) {
    tbody.innerHTML = `<tr><td colspan="6" style="color:var(--red);text-align:center;padding:1.5rem;">${err.message}</td></tr>`;
  }
}

async function loadOTP() {
  const tbody = document.getElementById('otp-body');
  if (!tbody) return;
  tbody.innerHTML = `<tr><td colspan="7" style="text-align:center;padding:1.5rem;color:var(--text-muted);"><span class="spin">⟳</span> Querying materialized view…</td></tr>`;
  try {
    const data = await API.performance();
    const rows = data.performance || [];
    tbody.innerHTML = rows.map(r => {
      const pct = parseFloat(r.on_time_performance_pct) || 0;
      const color = pct >= 90 ? 'var(--green)' : pct >= 80 ? 'var(--amber)' : 'var(--red)';
      return `<tr>
        <td><strong>${r.airline_name}</strong></td>
        <td><span style="font-family:var(--font-mono);color:var(--cyan);font-weight:700;">${r.airline_iata}</span></td>
        <td style="font-family:var(--font-mono);">${r.total_scheduled_flights}</td>
        <td style="font-family:var(--font-mono);color:var(--green);">${r.on_time_flights}</td>
        <td style="font-family:var(--font-mono);color:var(--amber);">${r.delayed_flights}</td>
        <td style="font-family:var(--font-mono);color:var(--text-secondary);">${r.avg_delay_minutes ?? '—'} min</td>
        <td style="font-family:var(--font-mono);font-weight:700;color:${color};">${pct.toFixed(1)}%</td>
      </tr>`;
    }).join('');
  } catch (err) {
    tbody.innerHTML = `<tr><td colspan="7" style="color:var(--red);text-align:center;padding:1.5rem;">${err.message}</td></tr>`;
  }
}

async function loadGateUtilization() {
  const tbody = document.getElementById('gate-analytics-body');
  if (!tbody) return;
  tbody.innerHTML = `<tr><td colspan="7" style="text-align:center;padding:1.5rem;color:var(--text-muted);"><span class="spin">⟳</span> Aggregating terminal gate utilization…</td></tr>`;
  try {
    const data = await API.gateUtilization();
    const rows = data.terminals || [];
    if (!rows.length) {
      tbody.innerHTML = `<tr><td colspan="7" style="text-align:center;padding:2rem;color:var(--text-muted);">No terminal capacity metrics available.</td></tr>`;
      return;
    }
    tbody.innerHTML = rows.map(t => {
      const occ = parseFloat(t.occupancy_pct) || 0;
      const occColor = occ > 70 ? 'var(--red)' : occ > 30 ? 'var(--amber)' : 'var(--green)';
      return `<tr>
        <td><strong>${t.terminal_name}</strong></td>
        <td><span style="font-family:var(--font-mono);color:var(--cyan);font-weight:700;">${t.terminal_code}</span></td>
        <td style="font-family:var(--font-mono);font-weight:700;">${t.total_gates}</td>
        <td style="font-family:var(--font-mono);color:var(--red);">${t.occupied_gates}</td>
        <td style="font-family:var(--font-mono);color:var(--amber);">${t.reserved_gates}</td>
        <td style="font-family:var(--font-mono);color:var(--green);">${t.available_gates}</td>
        <td><span style="font-family:var(--font-mono);font-weight:700;color:${occColor};">${occ}%</span></td>
      </tr>`;
    }).join('');
  } catch (err) {
    tbody.innerHTML = `<tr><td colspan="7" style="color:var(--red);text-align:center;padding:1.5rem;">${err.message}</td></tr>`;
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// 15. LIVE FLIGHT LOCATIONS, SCHEMATIC MAP & OPENSKY ADS-B RADAR
// ─────────────────────────────────────────────────────────────────────────────
function projX(lon) {
  // Projects longitude (-80 to +110) into SVG canvas width (50 to 950)
  return Math.max(40, Math.min(960, ((lon - (-80)) / 190) * 880 + 60));
}

function projY(lat) {
  // Projects latitude (-5 to +60) into SVG canvas height (430 to 50)
  return Math.max(40, Math.min(440, 420 - ((lat - (-5)) / 65) * 370));
}

async function loadTrackingData() {
  const tbody = document.getElementById('tracking-table-body');
  const pingEl = document.getElementById('tracking-last-ping');
  const counterEl = document.getElementById('map-airborne-counter');

  try {
    const data = await API.tracking();
    const aircraft = data.aircraft || [];

    // 1. Render Table
    if (tbody) {
      if (!aircraft.length) {
        tbody.innerHTML = `<tr><td colspan="9" style="text-align:center;padding:2rem;color:var(--text-muted);">No active flight records found.</td></tr>`;
      } else {
        tbody.innerHTML = aircraft.map(a => {
          return `<tr>
            <td>
              <span class="flt-code">${a.flight_number}</span>
              <div style="font-size:0.75rem;color:var(--text-secondary);">${a.airline_name} · ${a.aircraft_model}</div>
            </td>
            <td>
              <div class="airport-pair">
                <span class="iata">${a.origin_iata}</span>
                <span class="arrow">➔</span>
                <span class="iata">${a.dest_iata}</span>
              </div>
              <div style="font-size:0.7rem;color:var(--text-muted);">${a.origin_city} ➔ ${a.dest_city}</div>
            </td>
            <td><span class="badge badge-${a.status}">${a.status}</span></td>
            <td><span class="coord-tag">${a.coord_formatted}</span></td>
            <td><span class="location-tag">${a.location_text}</span></td>
            <td>
              <div style="font-family:var(--font-mono);font-size:0.8rem;color:var(--cyan);">${a.altitude_formatted}</div>
              <div style="font-size:0.7rem;color:var(--text-muted);">${a.speed_formatted}</div>
            </td>
            <td><span style="font-family:var(--font-mono);font-size:0.8rem;color:var(--text-primary);">${a.compass_dir}</span></td>
            <td><span class="text-prog-bar">${a.progress_bar_text}</span></td>
            <td class="time-cell">${a.dep_utc} ➔ ${a.arr_utc}</td>
          </tr>`;
        }).join('');
      }
    }

    // 2. Count airborne flights
    const airborneCount = aircraft.filter(a => a.status === 'AIRBORNE').length;
    if (counterEl) {
      counterEl.textContent = `● ${airborneCount} Airborne Flights`;
    }

    // 3. Render Schematic SVG Map
    renderSchematicSvgMap(aircraft);

    // 4. Update timestamp
    if (pingEl) {
      pingEl.textContent = `Updated: ${new Date().toUTCString().replace(' GMT', ' UTC')} · ${aircraft.length} flights tracked`;
    }

  } catch (err) {
    if (tbody) {
      tbody.innerHTML = `<tr><td colspan="9" style="color:var(--red);text-align:center;padding:2rem;">${err.message}</td></tr>`;
    }
  }
}

function renderSchematicSvgMap(aircraft) {
  const routesLayer = document.getElementById('svg-routes-layer');
  const aptsLayer = document.getElementById('svg-airports-layer');
  const aircraftLayer = document.getElementById('svg-aircraft-layer');
  if (!routesLayer || !aptsLayer || !aircraftLayer) return;

  // Clear previous SVG content
  routesLayer.innerHTML = '';
  aptsLayer.innerHTML = '';
  aircraftLayer.innerHTML = '';

  const hubs = new Map();

  // 1. Draw Flight Routes
  aircraft.forEach(a => {
    if (!a.orig_lat || !a.dest_lat) return;
    const x1 = projX(a.orig_lon);
    const y1 = projY(a.orig_lat);
    const x2 = projX(a.dest_lon);
    const y2 = projY(a.dest_lat);

    // Track hubs for labels
    if (!hubs.has(a.origin_iata)) hubs.set(a.origin_iata, { iata: a.origin_iata, city: a.origin_city, x: x1, y: y1 });
    if (!hubs.has(a.dest_iata)) hubs.set(a.dest_iata, { iata: a.dest_iata, city: a.dest_city, x: x2, y: y2 });

    const isAirborne = a.status === 'AIRBORNE';
    const midX = (x1 + x2) / 2;
    const midY = Math.min(y1, y2) - 25;

    const pathD = `M ${x1} ${y1} Q ${midX} ${midY} ${x2} ${y2}`;
    const pathClass = isAirborne ? 'svg-route-active' : 'svg-route-line';
    routesLayer.innerHTML += `<path d="${pathD}" class="${pathClass}"/>`;

    // 2. Plot Aircraft on Map if Airborne
    if (isAirborne && a.lat && a.lon) {
      const px = projX(a.lon);
      const py = projY(a.lat);

      aircraftLayer.innerHTML += `
        <g class="svg-plane-marker" transform="translate(${px}, ${py})">
          <!-- Pulse animation ring -->
          <circle cx="0" cy="0" r="10" fill="none" stroke="#a855f7" stroke-width="1.5" opacity="0.4">
            <animate attributeName="r" values="6;16;6" dur="2s" repeatCount="indefinite"/>
            <animate attributeName="opacity" values="0.8;0;0.8" dur="2s" repeatCount="indefinite"/>
          </circle>
          <circle cx="0" cy="0" r="5" fill="#c084fc" stroke="#ffffff" stroke-width="1.5"/>
          <text x="8" y="-3" fill="#f8fafc" font-family="var(--font-mono)" font-size="11" font-weight="700">✈ ${a.flight_number}</text>
          <text x="8" y="9" fill="#38bdf8" font-family="var(--font-mono)" font-size="9">${a.progress_pct}% · ${a.location_text}</text>
        </g>
      `;
    }
  });

  // 3. Draw Airport Hub Nodes
  hubs.forEach(h => {
    aptsLayer.innerHTML += `
      <g transform="translate(${h.x}, ${h.y})">
        <circle cx="0" cy="0" r="4.5" class="svg-apt-node"/>
        <text x="7" y="4" class="svg-apt-text">${h.iata}</text>
      </g>
    `;
  });
}

function initOpenSkyButton() {
  const btn = document.getElementById('btn-fetch-opensky');
  const msg = document.getElementById('opensky-status-msg');
  const wrap = document.getElementById('opensky-table-wrap');
  const tbody = document.getElementById('opensky-table-body');
  if (!btn) return;

  btn.addEventListener('click', async () => {
    btn.disabled = true;
    btn.innerHTML = '<span class="spin">⟳</span> Connecting to OpenSky Network…';
    if (msg) msg.textContent = 'Querying live ADS-B receiver satellites & transponder packets…';

    try {
      const data = await API.opensky();
      const aircraft = data.aircraft || [];

      if (data.error && !aircraft.length) {
        if (msg) msg.innerHTML = `<span style="color:var(--amber);">Notice: ${data.error} (OpenSky free servers rate-limit requests to once every 10s. Try again shortly).</span>`;
        return;
      }

      if (!aircraft.length) {
        if (msg) msg.innerHTML = `No live aircraft reported by OpenSky in this airspace bounding box right now. Try again in 10s.`;
        return;
      }

      if (msg) {
        msg.innerHTML = `<span style="color:var(--green)">✓ Successfully captured ${data.count} live aircraft ADS-B transponders! (${data.authenticated ? 'Authenticated Account' : 'Public Network'})</span>`;
      }

      if (wrap) wrap.style.display = 'block';
      if (tbody) {
        tbody.innerHTML = aircraft.map(p => `
          <tr>
            <td><strong style="color:var(--cyan);font-family:var(--font-mono);">${p.callsign}</strong></td>
            <td style="color:var(--text-secondary);">${p.country}</td>
            <td><span class="coord-tag">${p.coord_formatted}</span></td>
            <td style="font-family:var(--font-mono);color:var(--purple);">${p.altitude_formatted}</td>
            <td style="font-family:var(--font-mono);">${p.speed_formatted}</td>
            <td style="font-family:var(--font-mono);">${p.compass_dir}</td>
            <td><span class="badge badge-${p.status === 'AIRBORNE' ? 'AIRBORNE' : 'BOARDING'}">${p.status}</span></td>
          </tr>
        `).join('');
      }

    } catch (err) {
      if (msg) msg.innerHTML = `<span style="color:var(--red);">✗ ${err.message}</span>`;
    } finally {
      btn.disabled = false;
      btn.textContent = '⚡ Fetch OpenSky Live ADS-B';
    }
  });

  document.getElementById('btn-map-refresh')?.addEventListener('click', loadTrackingData);
}

