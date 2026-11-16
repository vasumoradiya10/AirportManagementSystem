-- ============================================================================
-- AIRPORT MANAGEMENT SYSTEM (AMS) - REAL-WORLD GLOBAL AVIATION DATASET
-- PostgreSQL 14+ / 16+ Compatible
-- Description: Real-world international airports, airlines, aircraft fleet,
--              authentic commercial flight schedules, passengers, and operations.
-- ============================================================================

-- 1. Truncate existing sample data cleanly
TRUNCATE TABLE 
    flight_status_audit,
    gate_occupancy_log,
    baggage_tracking_events,
    baggage,
    boarding_passes,
    bookings,
    flight_crew_assignments,
    crew_members,
    flight_instances,
    flight_routes,
    aircraft,
    aircraft_models,
    runways,
    gates,
    terminals,
    airlines,
    airports,
    passengers
RESTART IDENTITY CASCADE;

-- ============================================================================
-- 2. MAJOR REAL-WORLD GLOBAL AIRPORTS
-- ============================================================================
INSERT INTO airports (iata_code, icao_code, name, city, country, latitude, longitude, elevation_ft, timezone, is_international)
VALUES 
('DEL', 'VIDP', 'Indira Gandhi International Airport', 'New Delhi', 'India', 28.556200, 77.100000, 777, 'Asia/Kolkata', TRUE),
('BOM', 'VABB', 'Chhatrapati Shivaji Maharaj International Airport', 'Mumbai', 'India', 19.089600, 72.865600, 39, 'Asia/Kolkata', TRUE),
('BLR', 'VOBL', 'Kempegowda International Airport', 'Bengaluru', 'India', 13.198600, 77.706600, 3000, 'Asia/Kolkata', TRUE),
('DXB', 'OMDB', 'Dubai International Airport', 'Dubai', 'United Arab Emirates', 25.253200, 55.365700, 62, 'Asia/Dubai', TRUE),
('DOH', 'OTHH', 'Hamad International Airport', 'Doha', 'Qatar', 25.273100, 51.608100, 13, 'Asia/Qatar', TRUE),
('SIN', 'WSSS', 'Singapore Changi Airport', 'Singapore', 'Singapore', 1.364400, 103.991500, 22, 'Asia/Singapore', TRUE),
('LHR', 'EGLL', 'London Heathrow Airport', 'London', 'United Kingdom', 51.470000, -0.454300, 83, 'Europe/London', TRUE),
('CDG', 'LFPG', 'Paris Charles de Gaulle Airport', 'Paris', 'France', 49.009700, 2.547900, 392, 'Europe/Paris', TRUE),
('FRA', 'EDDF', 'Frankfurt am Main Airport', 'Frankfurt', 'Germany', 50.037900, 8.562200, 364, 'Europe/Berlin', TRUE),
('JFK', 'KJFK', 'John F. Kennedy International Airport', 'New York', 'United States', 40.641300, -73.778100, 13, 'America/New_York', TRUE),
('SFO', 'KSFO', 'San Francisco International Airport', 'San Francisco', 'United States', 37.621300, -122.379000, 13, 'America/Los_Angeles', TRUE),
('ORD', 'KORD', 'O''Hare International Airport', 'Chicago', 'United States', 41.974200, -87.907300, 672, 'America/Chicago', TRUE),
('LAX', 'KLAX', 'Los Angeles International Airport', 'Los Angeles', 'United States', 33.941600, -118.408500, 128, 'America/Los_Angeles', TRUE),
('HND', 'RJTT', 'Tokyo Haneda Airport', 'Tokyo', 'Japan', 35.549400, 139.779800, 21, 'Asia/Tokyo', TRUE),
('SYD', 'YSSY', 'Sydney Kingsford Smith Airport', 'Sydney', 'Australia', -33.939900, 151.175300, 21, 'Australia/Sydney', TRUE)
ON CONFLICT (iata_code) DO NOTHING;

-- ============================================================================
-- 3. TERMINALS
-- ============================================================================
INSERT INTO terminals (airport_id, terminal_code, name, total_gates, is_international)
SELECT a.airport_id, t.code, t.name, t.gates, t.intl
FROM airports a
CROSS JOIN (VALUES 
    ('DEL', 'T3', 'Terminal 3 Integrated International & Domestic', 48, TRUE),
    ('DEL', 'T2', 'Terminal 2 Domestic Low-Cost', 24, FALSE),
    ('BOM', 'T2', 'Chhatrapati Shivaji Terminal 2', 40, TRUE),
    ('DXB', 'T3', 'Emirates Mega Terminal 3', 65, TRUE),
    ('DOH', 'T1', 'Hamad Passenger Terminal Complex', 45, TRUE),
    ('LHR', 'T5', 'British Airways Terminal 5', 52, TRUE),
    ('LHR', 'T2', 'The Queen''s Terminal Star Alliance', 36, TRUE),
    ('JFK', 'T4', 'JFK Terminal 4 International Arrivals', 38, TRUE),
    ('JFK', 'T8', 'American Airlines & Oneworld Terminal 8', 29, TRUE),
    ('SIN', 'T3', 'Changi Terminal 3 Premium', 32, TRUE),
    ('FRA', 'T1', 'Frankfurt Lufthansa Hub Terminal 1', 50, TRUE),
    ('HND', 'T3', 'Tokyo Haneda International Terminal 3', 30, TRUE)
) AS t(iata, code, name, gates, intl)
WHERE a.iata_code = t.iata
ON CONFLICT (airport_id, terminal_code) DO NOTHING;

-- ============================================================================
-- 4. GATES
-- ============================================================================
INSERT INTO gates (terminal_id, gate_number, gate_type, status, is_jetbridge_equipped)
SELECT t.terminal_id, g.num, g.type::VARCHAR, g.stat::gate_status_enum, TRUE
FROM terminals t
CROSS JOIN (VALUES 
    ('10A', 'WIDE_BODY',   'AVAILABLE'),
    ('10B', 'WIDE_BODY',   'AVAILABLE'),
    ('12A', 'WIDE_BODY',   'AVAILABLE'),
    ('14',  'NARROW_BODY', 'AVAILABLE'),
    ('16',  'NARROW_BODY', 'AVAILABLE'),
    ('18A', 'WIDE_BODY',   'AVAILABLE'),
    ('20',  'NARROW_BODY', 'AVAILABLE'),
    ('22',  'REGIONAL',    'AVAILABLE')
) AS g(num, type, stat)
ON CONFLICT (terminal_id, gate_number) DO NOTHING;

-- ============================================================================
-- 5. RUNWAYS
-- ============================================================================
INSERT INTO runways (airport_id, runway_identifier, length_meters, width_meters, surface_type, is_active)
SELECT a.airport_id, r.ident, r.len, r.wid, 'ASPHALT', TRUE
FROM airports a
CROSS JOIN (VALUES 
    ('DEL', '11/29',   4430.00, 60.00),
    ('DEL', '10/28',   3810.00, 45.00),
    ('DEL', '09/27',   2816.00, 45.00),
    ('BOM', '09/27',   3660.00, 60.00),
    ('DXB', '12L/30R', 4000.00, 60.00),
    ('DXB', '12R/30L', 4450.00, 60.00),
    ('LHR', '09L/27R', 3902.00, 50.00),
    ('LHR', '09R/27L', 3660.00, 50.00),
    ('JFK', '13R/31L', 4423.00, 60.00),
    ('JFK', '04L/22R', 3682.00, 60.00),
    ('SIN', '02L/20R', 4000.00, 60.00),
    ('HND', '16L/34R', 3360.00, 60.00)
) AS r(iata, ident, len, wid)
WHERE a.iata_code = r.iata
ON CONFLICT (airport_id, runway_identifier) DO NOTHING;

-- ============================================================================
-- 6. MAJOR REAL-WORLD AIRLINES
-- ============================================================================
INSERT INTO airlines (iata_code, icao_code, name, callsign, country, headquarters)
VALUES 
('AI', 'AIC', 'Air India', 'AIRINDIA', 'India', 'Gurugram, India'),
('6E', 'IGO', 'IndiGo', 'IFLY', 'India', 'Gurugram, India'),
('EK', 'UAE', 'Emirates', 'EMIRATES', 'United Arab Emirates', 'Dubai, UAE'),
('QR', 'QTR', 'Qatar Airways', 'QATARI', 'Qatar', 'Doha, Qatar'),
('SQ', 'SIA', 'Singapore Airlines', 'SINGAPORE', 'Singapore', 'Singapore'),
('BA', 'BAW', 'British Airways', 'SPEEDBIRD', 'United Kingdom', 'London, UK'),
('LH', 'DLH', 'Lufthansa', 'LUFTHANSA', 'Germany', 'Cologne, Germany'),
('AF', 'AFR', 'Air France', 'AIRFRANS', 'France', 'Paris, France'),
('UA', 'UAL', 'United Airlines', 'UNITED', 'United States', 'Chicago, USA'),
('DL', 'DAL', 'Delta Air Lines', 'DELTA', 'United States', 'Atlanta, USA')
ON CONFLICT (iata_code) DO NOTHING;

-- ============================================================================
-- 7. REAL-WORLD AIRCRAFT MODELS
-- ============================================================================
INSERT INTO aircraft_models (model_code, manufacturer, model_name, max_passenger_capacity, max_cargo_capacity_kg, max_range_km, cruising_speed_kmh, required_runway_meters)
VALUES 
('B777-300ER', 'Boeing',  'Boeing 777-300ER Extended Range', 396, 26000.00, 13650, 905, 3200),
('B787-9',     'Boeing',  'Boeing 787-9 Dreamliner',         290, 18500.00, 14140, 903, 2800),
('B787-8',     'Boeing',  'Boeing 787-8 Dreamliner',         256, 16000.00, 13620, 903, 2600),
('B737-MAX8',  'Boeing',  'Boeing 737 MAX 8',                189,  5200.00,  6570, 839, 2100),
('A350-900',   'Airbus',  'Airbus A350-900 XWB',             350, 22000.00, 15000, 903, 2600),
('A380-800',   'Airbus',  'Airbus A380-800 Superjumbo',      525, 38000.00, 14800, 903, 3000),
('B747-8',     'Boeing',  'Boeing 747-8 Intercontinental',   467, 34000.00, 14320, 917, 3100),
('A321neo',    'Airbus',  'Airbus A321neo ACF',              222,  6800.00,  7400, 833, 2200),
('A320neo',    'Airbus',  'Airbus A320neo',                  186,  5400.00,  6300, 828, 2100)
ON CONFLICT (model_code) DO NOTHING;

-- ============================================================================
-- 8. REAL-WORLD AIRCRAFT FLEET (AUTHENTIC TAIL NUMBERS)
-- ============================================================================
INSERT INTO aircraft (registration_number, airline_id, model_code, manufacture_date, total_flight_hours, is_airworthy)
SELECT fleet.reg, al.airline_id, fleet.model, fleet.mfg_date::DATE, fleet.hours, TRUE
FROM airlines al
CROSS JOIN (VALUES 
    -- Air India Fleet
    ('AI', 'VT-EXG', 'A350-900',   '2023-11-15',  2140.50),
    ('AI', 'VT-JRH', 'A350-900',   '2024-02-10',   980.25),
    ('AI', 'VT-ALQ', 'B777-300ER', '2018-04-10', 16420.00),
    ('AI', 'VT-ANX', 'B787-8',     '2016-09-22', 22100.80),
    -- IndiGo Fleet
    ('6E', 'VT-IZK', 'A321neo',    '2021-06-14',  7800.40),
    ('6E', 'VT-IMB', 'A320neo',    '2022-08-30',  5430.00),
    ('6E', 'VT-IBP', 'A321neo',    '2023-01-18',  3890.10),
    -- Emirates Fleet
    ('EK', 'A6-EPG', 'B777-300ER', '2019-08-20', 14950.20),
    ('EK', 'A6-EOA', 'A380-800',   '2018-01-12', 18340.00),
    ('EK', 'A6-EUV', 'A380-800',   '2020-11-05', 11200.50),
    -- Qatar Airways Fleet
    ('QR', 'A7-BAL', 'B777-300ER', '2017-05-19', 19450.00),
    ('QR', 'A7-ANA', 'A350-900',   '2022-04-12',  6300.00),
    -- Singapore Airlines Fleet
    ('SQ', '9V-SMA', 'A350-900',   '2021-03-25',  8100.00),
    ('SQ', '9V-SGB', 'A350-900',   '2020-07-14', 10400.00),
    -- British Airways Fleet
    ('BA', 'G-XWBA', 'A350-900',   '2020-06-18', 11400.00),
    ('BA', 'G-STBC', 'B777-300ER', '2015-10-02', 28900.00),
    -- Lufthansa Fleet
    ('LH', 'D-AIXP', 'A350-900',   '2022-12-01',  4900.00),
    ('LH', 'D-ABYM', 'B747-8',     '2014-04-20', 31200.00),
    -- United Airlines Fleet
    ('UA', 'N78060', 'B777-300ER', '2017-08-11', 19800.00),
    ('UA', 'N2749U', 'B787-9',     '2019-03-15', 13500.00)
) AS fleet(airline_code, reg, model, mfg_date, hours)
WHERE al.iata_code = fleet.airline_code
ON CONFLICT (registration_number) DO NOTHING;

-- ============================================================================
-- 9. AUTHENTIC REAL-WORLD FLIGHT ROUTES
-- ============================================================================
INSERT INTO flight_routes (airline_id, flight_number, origin_airport_id, destination_airport_id, scheduled_duration_mins, distance_km)
SELECT 
    al.airline_id, r.flt_num, o.airport_id, d.airport_id, r.duration, r.dist
FROM airlines al
CROSS JOIN (VALUES 
    -- Air India Major Flagship Routes
    ('AI', 'AI101',  'DEL', 'JFK', 960, 11750),
    ('AI', 'AI102',  'JFK', 'DEL', 870, 11750),
    ('AI', 'AI161',  'DEL', 'LHR', 550,  6710),
    ('AI', 'AI162',  'LHR', 'DEL', 510,  6710),
    ('AI', 'AI173',  'DEL', 'SFO', 950, 12380),
    ('AI', 'AI191',  'BOM', 'EWR', 975, 11740),
    -- IndiGo High-Density Routes
    ('6E', '6E202',  'DEL', 'BOM', 130,  1140),
    ('6E', '6E5314', 'DEL', 'BLR', 165,  1700),
    ('6E', '6E11',   'DEL', 'DXB', 240,  2185),
    ('6E', '6E53',   'BOM', 'SIN', 320,  3900),
    -- Emirates Gateway Routes
    ('EK', 'EK511',  'DEL', 'DXB', 235,  2185),
    ('EK', 'EK500',  'BOM', 'DXB', 190,  1925),
    ('EK', 'EK201',  'DXB', 'JFK', 860, 11010),
    ('EK', 'EK001',  'DXB', 'LHR', 475,  5500),
    ('EK', 'EK412',  'DXB', 'SYD', 835, 12040),
    -- Qatar Airways Global Hub Routes
    ('QR', 'QR571',  'DEL', 'DOH', 260,  2550),
    ('QR', 'QR701',  'DOH', 'JFK', 840, 10770),
    ('QR', 'QR007',  'DOH', 'LHR', 450,  5240),
    -- Singapore Airlines Premium Corridors
    ('SQ', 'SQ401',  'DEL', 'SIN', 340,  4150),
    ('SQ', 'SQ421',  'BOM', 'SIN', 325,  3900),
    ('SQ', 'SQ22',   'SIN', 'EWR', 1110, 15345),
    ('SQ', 'SQ322',  'SIN', 'LHR', 805, 10880),
    -- British Airways Transatlantic & Asian Flights
    ('BA', 'BA142',  'DEL', 'LHR', 560,  6710),
    ('BA', 'BA177',  'LHR', 'JFK', 480,  5540),
    ('BA', 'BA117',  'LHR', 'JFK', 475,  5540),
    -- Lufthansa European & Intercontinental
    ('LH', 'LH761',  'DEL', 'FRA', 525,  6120),
    ('LH', 'LH400',  'FRA', 'JFK', 530,  6200),
    -- Air France
    ('AF', 'AF225',  'DEL', 'CDG', 545,  6580),
    ('AF', 'AF022',  'CDG', 'JFK', 495,  5830),
    -- United Airlines
    ('UA', 'UA82',   'DEL', 'EWR', 955, 11740),
    ('UA', 'UA867',  'SFO', 'DEL', 980, 12380)
) AS r(airline_code, flt_num, orig_code, dest_code, duration, dist)
JOIN airports o ON o.iata_code = r.orig_code
JOIN airports d ON d.iata_code = r.dest_code
WHERE al.iata_code = r.airline_code
ON CONFLICT (airline_id, flight_number) DO NOTHING;

-- ============================================================================
-- 10. REAL-WORLD FLIGHT INSTANCES (TODAY'S LIVE TIMETABLE)
-- ============================================================================
DO $$
DECLARE
    v_now TIMESTAMPTZ := CURRENT_TIMESTAMP;
    v_today DATE := CURRENT_DATE;
BEGIN

    -- 1. AI101: Delhi to New York JFK (Wide-body A350-900, Boarding at Gate 10A)
    INSERT INTO flight_instances (route_id, aircraft_id, departure_gate_id, scheduled_departure, scheduled_arrival, status, delay_minutes)
    SELECT fr.route_id, ac.aircraft_id, g.gate_id, 
           v_today + TIME '02:20:00', v_today + TIME '07:35:00', 'BOARDING'::flight_status_enum, 0
    FROM flight_routes fr
    JOIN aircraft ac ON ac.registration_number = 'VT-EXG'
    JOIN gates g ON g.gate_number = '10A'
    WHERE fr.flight_number = 'AI101' LIMIT 1;

    -- 2. EK511: Delhi to Dubai (Boeing 777-300ER, Delayed by 35 mins due to ATC flow management)
    INSERT INTO flight_instances (route_id, aircraft_id, departure_gate_id, scheduled_departure, scheduled_arrival, status, delay_minutes, delay_reason)
    SELECT fr.route_id, ac.aircraft_id, g.gate_id, 
           v_today + TIME '04:15:00', v_today + TIME '06:50:00', 'DELAYED'::flight_status_enum, 35, 'Air Traffic Control airspace slot restriction over Oman'
    FROM flight_routes fr
    JOIN aircraft ac ON ac.registration_number = 'A6-EPG'
    JOIN gates g ON g.gate_number = '12A'
    WHERE fr.flight_number = 'EK511' LIMIT 1;

    -- 3. 6E202: Delhi to Mumbai (Airbus A321neo, Airborne in flight)
    INSERT INTO flight_instances (route_id, aircraft_id, departure_gate_id, scheduled_departure, scheduled_arrival, actual_departure, status, delay_minutes)
    SELECT fr.route_id, ac.aircraft_id, g.gate_id, 
           v_today + TIME '01:10:00', v_today + TIME '03:20:00', v_today + TIME '01:15:00', 'AIRBORNE'::flight_status_enum, 5
    FROM flight_routes fr
    JOIN aircraft ac ON ac.registration_number = 'VT-IZK'
    JOIN gates g ON g.gate_number = '14'
    WHERE fr.flight_number = '6E202' LIMIT 1;

    -- 4. BA142: Delhi to London Heathrow (A350-900, Gate Closed)
    INSERT INTO flight_instances (route_id, aircraft_id, departure_gate_id, scheduled_departure, scheduled_arrival, status, delay_minutes)
    SELECT fr.route_id, ac.aircraft_id, g.gate_id, 
           v_today + TIME '03:40:00', v_today + TIME '08:35:00', 'GATE_CLOSED'::flight_status_enum, 0
    FROM flight_routes fr
    JOIN aircraft ac ON ac.registration_number = 'G-XWBA'
    JOIN gates g ON g.gate_number = '10B'
    WHERE fr.flight_number = 'BA142' LIMIT 1;

    -- 5. SQ401: Delhi to Singapore Changi (A350-900, Scheduled)
    INSERT INTO flight_instances (route_id, aircraft_id, departure_gate_id, scheduled_departure, scheduled_arrival, status, delay_minutes)
    SELECT fr.route_id, ac.aircraft_id, g.gate_id, 
           v_today + TIME '09:55:00', v_today + TIME '18:10:00', 'SCHEDULED'::flight_status_enum, 0
    FROM flight_routes fr
    JOIN aircraft ac ON ac.registration_number = '9V-SMA'
    JOIN gates g ON g.gate_number = '16'
    WHERE fr.flight_number = 'SQ401' LIMIT 1;

    -- 6. QR571: Delhi to Doha Hamad (A350-900, Scheduled)
    INSERT INTO flight_instances (route_id, aircraft_id, departure_gate_id, scheduled_departure, scheduled_arrival, status, delay_minutes)
    SELECT fr.route_id, ac.aircraft_id, g.gate_id, 
           v_today + TIME '10:15:00', v_today + TIME '12:05:00', 'SCHEDULED'::flight_status_enum, 0
    FROM flight_routes fr
    JOIN aircraft ac ON ac.registration_number = 'A7-ANA'
    JOIN gates g ON g.gate_number = '18A'
    WHERE fr.flight_number = 'QR571' LIMIT 1;

    -- 7. LH761: Delhi to Frankfurt (A350-900, Scheduled)
    INSERT INTO flight_instances (route_id, aircraft_id, departure_gate_id, scheduled_departure, scheduled_arrival, status, delay_minutes)
    SELECT fr.route_id, ac.aircraft_id, g.gate_id, 
           v_today + TIME '03:10:00', v_today + TIME '07:45:00', 'SCHEDULED'::flight_status_enum, 0
    FROM flight_routes fr
    JOIN aircraft ac ON ac.registration_number = 'D-AIXP'
    JOIN gates g ON g.gate_number = '20'
    WHERE fr.flight_number = 'LH761' LIMIT 1;

    -- 8. 6E5314: Delhi to Bengaluru Kempegowda (A320neo, Scheduled)
    INSERT INTO flight_instances (route_id, aircraft_id, departure_gate_id, scheduled_departure, scheduled_arrival, status, delay_minutes)
    SELECT fr.route_id, ac.aircraft_id, g.gate_id, 
           v_today + TIME '06:30:00', v_today + TIME '09:15:00', 'SCHEDULED'::flight_status_enum, 0
    FROM flight_routes fr
    JOIN aircraft ac ON ac.registration_number = 'VT-IMB'
    JOIN gates g ON g.gate_number = '14'
    WHERE fr.flight_number = '6E5314' LIMIT 1;

    -- 9. EK201: Connecting leg Dubai to New York JFK (A380-800, Scheduled for transit passengers)
    INSERT INTO flight_instances (route_id, aircraft_id, scheduled_departure, scheduled_arrival, status, delay_minutes)
    SELECT fr.route_id, ac.aircraft_id, 
           v_today + TIME '08:30:00', v_today + TIME '14:25:00', 'SCHEDULED'::flight_status_enum, 0
    FROM flight_routes fr
    JOIN aircraft ac ON ac.registration_number = 'A6-EOA'
    WHERE fr.flight_number = 'EK201' LIMIT 1;

    -- 10. QR701: Connecting leg Doha to New York JFK (B777-300ER, Scheduled for transit)
    INSERT INTO flight_instances (route_id, aircraft_id, scheduled_departure, scheduled_arrival, status, delay_minutes)
    SELECT fr.route_id, ac.aircraft_id, 
           v_today + TIME '14:15:00', v_today + TIME '21:05:00', 'SCHEDULED'::flight_status_enum, 0
    FROM flight_routes fr
    JOIN aircraft ac ON ac.registration_number = 'A7-BAL'
    WHERE fr.flight_number = 'QR701' LIMIT 1;

    -- 11. BA177: Connecting leg London Heathrow to New York JFK (B777-300ER, Scheduled for transit)
    INSERT INTO flight_instances (route_id, aircraft_id, scheduled_departure, scheduled_arrival, status, delay_minutes)
    SELECT fr.route_id, ac.aircraft_id, 
           v_today + TIME '12:45:00', v_today + TIME '15:45:00', 'SCHEDULED'::flight_status_enum, 0
    FROM flight_routes fr
    JOIN aircraft ac ON ac.registration_number = 'G-STBC'
    WHERE fr.flight_number = 'BA177' LIMIT 1;

END $$;

-- Update gate statuses according to assigned active flights
UPDATE gates g
SET status = 'OCCUPIED'::gate_status_enum
WHERE g.gate_id IN (
    SELECT departure_gate_id FROM flight_instances 
    WHERE status IN ('BOARDING', 'GATE_CLOSED') AND departure_gate_id IS NOT NULL
);

UPDATE gates g
SET status = 'RESERVED'::gate_status_enum
WHERE g.gate_id IN (
    SELECT departure_gate_id FROM flight_instances 
    WHERE status IN ('SCHEDULED', 'DELAYED') AND departure_gate_id IS NOT NULL
) AND g.status <> 'OCCUPIED'::gate_status_enum;

-- ============================================================================
-- 11. REAL-WORLD PASSENGERS
-- ============================================================================
INSERT INTO passengers (first_name, last_name, passport_number, nationality, date_of_birth, email, phone_number, frequent_flyer_number)
VALUES 
('Aditya', 'Mehta',       'M8492019', 'Indian',    '1989-04-12', 'aditya.mehta@outlook.com',    '+919820123456', 'AI-FF-982104'),
('Charlotte', 'Harrison', 'GB882190', 'British',   '1992-09-28', 'c.harrison@oxford.ac.uk',    '+447700900123', 'BA-EXEC-4491'),
('Siddharth', 'Nair',     'K4920183', 'Indian',    '1995-12-05', 'sid.nair@techcorp.io',        '+919845012345', '6E-SUPER-01'),
('Alexander', 'Becker',   'DE891048', 'German',    '1984-07-19', 'a.becker@berlin-aviation.de', '+491701234567', 'LH-M&M-88219'),
('Wei', 'Zhang',          'CN772910', 'Singaporean','1990-03-15', 'wei.zhang@changi-invest.sg', '+6591234567',  'SQ-KRIS-77102'),
('Jessica', 'Miller',     'US910283', 'American',  '1998-11-04', 'jessica.m@nyu.edu',           '+12125559810',  'UA-MILES-5542')
ON CONFLICT (passport_number) DO NOTHING;

-- ============================================================================
-- 12. REAL-WORLD PASSENGER BOOKINGS, SEATS & BOARDING PASSES
-- ============================================================================
DO $$
DECLARE
    v_flt_ai101 BIGINT;
    v_flt_ek511 BIGINT;
    v_flt_ba142 BIGINT;
    v_flt_6e5314 BIGINT;

    v_p_aditya BIGINT;
    v_p_charlotte BIGINT;
    v_p_siddharth BIGINT;
    v_p_alexander BIGINT;

    v_ref_1 CHAR(6);
    v_bid_1 BIGINT;
    v_ref_2 CHAR(6);
    v_bid_2 BIGINT;
    v_ref_3 CHAR(6);
    v_bid_3 BIGINT;
    v_ref_4 CHAR(6);
    v_bid_4 BIGINT;
BEGIN
    SELECT flight_instance_id INTO v_flt_ai101 FROM flight_instances fi 
    JOIN flight_routes fr ON fi.route_id = fr.route_id WHERE fr.flight_number = 'AI101' LIMIT 1;

    SELECT flight_instance_id INTO v_flt_ek511 FROM flight_instances fi 
    JOIN flight_routes fr ON fi.route_id = fr.route_id WHERE fr.flight_number = 'EK511' LIMIT 1;

    SELECT flight_instance_id INTO v_flt_ba142 FROM flight_instances fi 
    JOIN flight_routes fr ON fi.route_id = fr.route_id WHERE fr.flight_number = 'BA142' LIMIT 1;

    SELECT flight_instance_id INTO v_flt_6e5314 FROM flight_instances fi 
    JOIN flight_routes fr ON fi.route_id = fr.route_id WHERE fr.flight_number = '6E5314' LIMIT 1;

    SELECT passenger_id INTO v_p_aditya FROM passengers WHERE passport_number = 'M8492019';
    SELECT passenger_id INTO v_p_charlotte FROM passengers WHERE passport_number = 'GB882190';
    SELECT passenger_id INTO v_p_siddharth FROM passengers WHERE passport_number = 'K4920183';
    SELECT passenger_id INTO v_p_alexander FROM passengers WHERE passport_number = 'DE891048';

    -- 1. Booking for Aditya on AI101 (Business Class 11A)
    IF v_flt_ai101 IS NOT NULL AND v_p_aditya IS NOT NULL THEN
        CALL sp_process_seat_reservation(v_flt_ai101, v_p_aditya, '11A', 'BUSINESS', 1850.00, v_ref_1, v_bid_1);
        IF v_bid_1 IS NOT NULL THEN
            INSERT INTO baggage (tag_number, booking_id, flight_instance_id, weight_kg, status)
            VALUES ('BAG-AI-88910', v_bid_1, v_flt_ai101, 28.50, 'LOADED');

            INSERT INTO baggage_tracking_events (baggage_id, event_status, checkpoint_location, scanned_by)
            SELECT baggage_id, 'CHECKED_IN', 'Terminal 3 International Counter J4', 'AI Ground Staff'
            FROM baggage WHERE tag_number = 'BAG-AI-88910';

            INSERT INTO baggage_tracking_events (baggage_id, event_status, checkpoint_location, scanned_by)
            SELECT baggage_id, 'SECURITY_CLEARED', 'Inline Explosive Detection System Level 3', 'BCAS Automated Sorter'
            FROM baggage WHERE tag_number = 'BAG-AI-88910';

            INSERT INTO baggage_tracking_events (baggage_id, event_status, checkpoint_location, scanned_by)
            SELECT baggage_id, 'LOADED', 'Ramp Bay 10A Forward Cargo Hold', 'Ramp Ops Loader 04'
            FROM baggage WHERE tag_number = 'BAG-AI-88910';
        END IF;
    END IF;

    -- 2. Booking for Charlotte on BA142 (Club World Business 04E)
    IF v_flt_ba142 IS NOT NULL AND v_p_charlotte IS NOT NULL THEN
        CALL sp_process_seat_reservation(v_flt_ba142, v_p_charlotte, '04E', 'BUSINESS', 1620.00, v_ref_2, v_bid_2);
        IF v_bid_2 IS NOT NULL THEN
            INSERT INTO baggage (tag_number, booking_id, flight_instance_id, weight_kg, status)
            VALUES ('BAG-BA-44102', v_bid_2, v_flt_ba142, 22.00, 'SECURITY_CLEARED');

            INSERT INTO baggage_tracking_events (baggage_id, event_status, checkpoint_location, scanned_by)
            SELECT baggage_id, 'CHECKED_IN', 'Terminal 3 Premium Desk 02', 'BA Agent'
            FROM baggage WHERE tag_number = 'BAG-BA-44102';

            INSERT INTO baggage_tracking_events (baggage_id, event_status, checkpoint_location, scanned_by)
            SELECT baggage_id, 'SECURITY_CLEARED', 'Security Screening Belt 4', 'Automated EDS'
            FROM baggage WHERE tag_number = 'BAG-BA-44102';
        END IF;
    END IF;

    -- 3. Booking for Siddharth on 6E5314 (Economy 12F)
    IF v_flt_6e5314 IS NOT NULL AND v_p_siddharth IS NOT NULL THEN
        CALL sp_process_seat_reservation(v_flt_6e5314, v_p_siddharth, '12F', 'ECONOMY', 95.00, v_ref_3, v_bid_3);
    END IF;

    -- 4. Booking for Alexander on EK511 (First Class 01A)
    IF v_flt_ek511 IS NOT NULL AND v_p_alexander IS NOT NULL THEN
        CALL sp_process_seat_reservation(v_flt_ek511, v_p_alexander, '01A', 'FIRST', 2850.00, v_ref_4, v_bid_4);
        IF v_bid_4 IS NOT NULL THEN
            INSERT INTO baggage (tag_number, booking_id, flight_instance_id, weight_kg, status)
            VALUES ('BAG-EK-99201', v_bid_4, v_flt_ek511, 31.00, 'CHECKED_IN');

            INSERT INTO baggage_tracking_events (baggage_id, event_status, checkpoint_location, scanned_by)
            SELECT baggage_id, 'CHECKED_IN', 'First Class Dedicated Suite Counter', 'Emirates Concierge'
            FROM baggage WHERE tag_number = 'BAG-EK-99201';
        END IF;
    END IF;

END $$;

-- Refresh Materialized View for Airline Performance
REFRESH MATERIALIZED VIEW mv_airline_performance;
