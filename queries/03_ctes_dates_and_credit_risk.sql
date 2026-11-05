-- ============================================================
-- 03_ctes_dates_and_credit_risk.sql
-- Skills: CTEs (WITH), CASE, date arithmetic, LEFT JOIN, ageing analysis
-- ============================================================


-- Q5. Which agents keep returning too many copies (more than 25% in at least 3 months of 2025)?
-- Approach: a CTE works out each agent's monthly return rate; the main query counts bad months.
WITH monthly AS (
    SELECT agent_id,
           DATE_TRUNC('month', dist_date)::DATE AS month_start,
           100.0 * SUM(copies_returned) / SUM(copies_sent) AS return_pct
    FROM distribution
    WHERE dist_date >= DATE '2025-01-01'
    GROUP BY agent_id, DATE_TRUNC('month', dist_date)
)
SELECT agent_id,
       COUNT(*)                   AS months_above_25pct,
       ROUND(AVG(return_pct), 1)  AS avg_return_pct_in_those_months
FROM monthly
WHERE return_pct > 25
GROUP BY agent_id
HAVING COUNT(*) >= 3
ORDER BY months_above_25pct DESC, agent_id;


-- Q5b. What does the high-return group cost? Their 2025 returns above the normal rate
-- (the rate of all other agents), valued at cover price.
-- Approach: chained CTEs: monthly rates -> flagged agents -> benchmark rate -> cost.
WITH monthly AS (
    SELECT agent_id,
           100.0 * SUM(copies_returned) / SUM(copies_sent) AS return_pct
    FROM distribution
    WHERE dist_date >= DATE '2025-01-01'
    GROUP BY agent_id, DATE_TRUNC('month', dist_date)
),
flagged AS (
    SELECT agent_id
    FROM monthly
    WHERE return_pct > 25
    GROUP BY agent_id
    HAVING COUNT(*) >= 3
),
benchmark AS (
    SELECT 1.0 * SUM(copies_returned) / SUM(copies_sent) AS normal_rate
    FROM distribution
    WHERE dist_date >= DATE '2025-01-01'
      AND agent_id NOT IN (SELECT agent_id FROM flagged)
)
SELECT COUNT(DISTINCT d.agent_id)                                        AS flagged_agents,
       SUM(d.copies_sent)                                                AS copies_sent,
       SUM(d.copies_returned)                                            AS copies_returned,
       ROUND(100.0 * SUM(d.copies_returned) / SUM(d.copies_sent), 1)     AS their_return_pct,
       ROUND(100 * (SELECT normal_rate FROM benchmark), 1)               AS other_agents_return_pct,
       ROUND(SUM(d.copies_returned)
             - SUM(d.copies_sent) * (SELECT normal_rate FROM benchmark)) AS excess_returned_copies,
       ROUND(SUM((d.copies_returned - d.copies_sent * (SELECT normal_rate FROM benchmark))
                 * t.cover_price))                                       AS excess_value_at_cover_price
FROM distribution d
JOIN titles t ON t.title_id = d.title_id
WHERE d.dist_date >= DATE '2025-01-01'
  AND d.agent_id IN (SELECT agent_id FROM flagged);


-- Q6a. Which agents pay latest? (average days between due date and payment date)
-- Approach: paid_date - due_date gives days late (negative = early).
WITH agent_delay AS (
    SELECT i.agent_id,
           ROUND(AVG(p.paid_date - i.due_date), 1) AS avg_days_late,
           COUNT(*)                                AS paid_invoices
    FROM invoices i
    JOIN payments p ON p.invoice_id = i.invoice_id
    GROUP BY i.agent_id
)
SELECT agent_id, avg_days_late, paid_invoices
FROM agent_delay
ORDER BY avg_days_late DESC
LIMIT 10;

-- Q6b. How many agents are slow payers (average more than 15 days late)?
WITH agent_delay AS (
    SELECT i.agent_id,
           AVG(p.paid_date - i.due_date) AS avg_days_late
    FROM invoices i
    JOIN payments p ON p.invoice_id = i.invoice_id
    GROUP BY i.agent_id
)
SELECT COUNT(*) FILTER (WHERE avg_days_late > 15)  AS slow_payers,
       COUNT(*)                                    AS total_agents,
       ROUND(100.0 * COUNT(*) FILTER (WHERE avg_days_late > 15) / COUNT(*), 1) AS slow_payer_pct
FROM agent_delay;


-- Q7. Ageing report: how much is outstanding, and how overdue is it, as of 31 January 2026?
-- Approach: LEFT JOIN keeps invoices with no payment; only payments made on or before
-- the report date count; CASE puts each open balance into an ageing bucket.
WITH params AS (
    SELECT DATE '2026-01-31' AS as_of
),
open_items AS (
    SELECT i.invoice_id,
           i.amount_billed - COALESCE(p.amount_paid, 0) AS outstanding,
           params.as_of - i.due_date                    AS days_past_due
    FROM invoices i
    CROSS JOIN params
    LEFT JOIN payments p
           ON p.invoice_id = i.invoice_id
          AND p.paid_date <= params.as_of
)
SELECT CASE WHEN days_past_due <= 0  THEN '0. Not yet due'
            WHEN days_past_due <= 30 THEN '1. 1-30 days'
            WHEN days_past_due <= 60 THEN '2. 31-60 days'
            WHEN days_past_due <= 90 THEN '3. 61-90 days'
            ELSE                          '4. Over 90 days' END AS ageing_bucket,
       COUNT(*)                   AS open_invoices,
       ROUND(SUM(outstanding))    AS outstanding_value
FROM open_items
WHERE outstanding > 0
GROUP BY 1
ORDER BY 1;


-- Q8. How many invoices are unpaid, part-paid, or paid in full, and what is the shortfall?
SELECT CASE WHEN p.invoice_id IS NULL             THEN 'Unpaid'
            WHEN p.amount_paid < i.amount_billed  THEN 'Part-paid'
            ELSE                                       'Paid in full' END AS payment_status,
       COUNT(*)                                                  AS invoices,
       ROUND(SUM(i.amount_billed))                               AS billed_value,
       ROUND(SUM(i.amount_billed - COALESCE(p.amount_paid, 0)))  AS shortfall_value
FROM invoices i
LEFT JOIN payments p ON p.invoice_id = i.invoice_id
GROUP BY 1
ORDER BY 1;
