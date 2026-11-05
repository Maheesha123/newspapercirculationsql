-- ============================================================
-- Newspaper circulation and credit risk: schema + SYNTHETIC data
-- All data below is randomly generated for demonstration only.
-- It does not represent any real company, agent or payment.
-- Safe to re-run: it drops and rebuilds the tables each time.
-- A fixed random seed makes the data identical on every run,
-- so the results in the README can be reproduced exactly.
-- Total run time: about 10 to 60 seconds.
-- ============================================================

-- 0. RESET AND SEED -----------------------------------------
DROP VIEW  IF EXISTS v_agent_risk;
DROP TABLE IF EXISTS payments, invoices, distribution, agents, titles, regions CASCADE;
SELECT setseed(0.42);

-- 1. REGIONS ------------------------------------------------
CREATE TABLE regions (
    region_id   SERIAL PRIMARY KEY,
    region_name TEXT NOT NULL
);

INSERT INTO regions (region_name) VALUES
('Colombo'), ('Gampaha'), ('Kandy'), ('Galle'),
('Matara'), ('Jaffna'), ('Kurunegala'), ('Anuradhapura');

-- 2. TITLES (newspaper products) ----------------------------
CREATE TABLE titles (
    title_id    SERIAL PRIMARY KEY,
    title_name  TEXT NOT NULL,
    cover_price NUMERIC NOT NULL
);

INSERT INTO titles (title_name, cover_price) VALUES
('Daily News A', 80),
('Weekend Edition B', 120),
('Sports Weekly C', 100);

-- 3. AGENTS (150 fake agents) -------------------------------
CREATE TABLE agents (
    agent_id     SERIAL PRIMARY KEY,
    agent_name   TEXT NOT NULL,
    region_id    INT REFERENCES regions(region_id),
    start_date   DATE,
    credit_limit NUMERIC
);

INSERT INTO agents (agent_name, region_id, start_date, credit_limit)
SELECT 'Agent ' || g,
       1 + (g % 8),
       DATE '2022-01-01' + (random() * 700)::INT,
       (50 + (random() * 20)::INT * 10) * 1000
FROM generate_series(1, 150) AS g;

-- 4. DISTRIBUTION (daily copies sent and returned, 2024-2025) -
CREATE TABLE distribution (
    dist_id         SERIAL PRIMARY KEY,
    dist_date       DATE NOT NULL,
    agent_id        INT REFERENCES agents(agent_id),
    title_id        INT REFERENCES titles(title_id),
    copies_sent     INT NOT NULL,
    copies_returned INT NOT NULL
);

INSERT INTO distribution (dist_date, agent_id, title_id, copies_sent, copies_returned)
SELECT d::DATE,
       a.agent_id,
       t.title_id,
       50 + (a.agent_id % 40) + (random() * 20)::INT,
       0
FROM generate_series(DATE '2024-01-01', DATE '2025-12-31', INTERVAL '1 day') AS d
CROSS JOIN agents a
CROSS JOIN titles t;

-- normal returns: 5% to 25% of copies sent
UPDATE distribution
SET copies_returned = (copies_sent * (0.05 + random() * 0.20))::INT;

-- hidden pattern 1: every 10th agent has much higher returns in 2025
UPDATE distribution
SET copies_returned = (copies_sent * (0.25 + random() * 0.20))::INT
WHERE agent_id % 10 = 0
  AND dist_date >= DATE '2025-01-01';

-- 5. INVOICES (one per agent per month) ---------------------
CREATE TABLE invoices (
    invoice_id    SERIAL PRIMARY KEY,
    agent_id      INT REFERENCES agents(agent_id),
    invoice_month DATE NOT NULL,
    amount_billed NUMERIC NOT NULL,
    due_date      DATE NOT NULL
);

INSERT INTO invoices (agent_id, invoice_month, amount_billed, due_date)
SELECT d.agent_id,
       DATE_TRUNC('month', d.dist_date)::DATE,
       ROUND(SUM((d.copies_sent - d.copies_returned) * t.cover_price * 0.7), 2),
       (DATE_TRUNC('month', d.dist_date) + INTERVAL '1 month' + INTERVAL '14 days')::DATE
FROM distribution d
JOIN titles t ON t.title_id = d.title_id
GROUP BY d.agent_id, DATE_TRUNC('month', d.dist_date);

-- 6. PAYMENTS ------------------------------------------------
CREATE TABLE payments (
    payment_id  SERIAL PRIMARY KEY,
    invoice_id  INT REFERENCES invoices(invoice_id),
    paid_date   DATE NOT NULL,
    amount_paid NUMERIC NOT NULL
);

-- hidden pattern 2: every 7th agent pays 20 to 80 days late;
-- other agents pay around the due date;
-- about 3% of invoices stay unpaid, about 5% are only partly paid
INSERT INTO payments (invoice_id, paid_date, amount_paid)
SELECT invoice_id,
       due_date + CASE WHEN agent_id % 7 = 0
                       THEN (20 + random() * 60)::INT
                       ELSE (random() * 20 - 8)::INT END,
       CASE WHEN random() < 0.05 THEN ROUND(amount_billed * 0.6, 2)
            ELSE amount_billed END
FROM invoices
WHERE random() > 0.03;

-- 7. CHECK THE ROW COUNTS -----------------------------------
SELECT 'regions' AS table_name, COUNT(*) AS row_count FROM regions            -- expect 8
UNION ALL SELECT 'titles',       COUNT(*) FROM titles                          -- expect 3
UNION ALL SELECT 'agents',       COUNT(*) FROM agents                          -- expect 150
UNION ALL SELECT 'distribution', COUNT(*) FROM distribution                    -- expect 328,950
UNION ALL SELECT 'invoices',     COUNT(*) FROM invoices                        -- expect 3,600
UNION ALL SELECT 'payments',     COUNT(*) FROM payments;                       -- about 3,490
