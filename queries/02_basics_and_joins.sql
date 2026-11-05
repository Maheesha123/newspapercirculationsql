-- ============================================================
-- 02_basics_and_joins.sql
-- Skills: SELECT, JOIN, GROUP BY, HAVING, date functions
-- Database: newspaper_db (run schema/01_schema_and_data.sql first)
-- Each query starts with the business question it answers.
-- ============================================================


-- Q1. Which regions sell the most, and which return the most unsold copies?
-- Approach: join distribution -> agents -> regions, then summarise per region.
SELECT r.region_name,
       SUM(d.copies_sent)                        AS copies_sent,
       SUM(d.copies_returned)                    AS copies_returned,
       SUM(d.copies_sent - d.copies_returned)    AS net_copies,
       ROUND(100.0 * SUM(d.copies_returned) / SUM(d.copies_sent), 1) AS return_pct
FROM distribution d
JOIN agents  a ON a.agent_id  = d.agent_id
JOIN regions r ON r.region_id = a.region_id
GROUP BY r.region_name
ORDER BY net_copies DESC;


-- Q2. How do sales and returns move month by month?
-- Approach: DATE_TRUNC rolls daily rows up to months.
SELECT DATE_TRUNC('month', dist_date)::DATE AS month_start,
       SUM(copies_sent)                     AS copies_sent,
       SUM(copies_returned)                 AS copies_returned,
       ROUND(100.0 * SUM(copies_returned) / SUM(copies_sent), 1) AS return_pct
FROM distribution
GROUP BY DATE_TRUNC('month', dist_date)
ORDER BY month_start;


-- Q3. Which title earns the most each year (net copies x cover price)?
-- Approach: join to titles for the price; EXTRACT pulls the year out of the date.
SELECT EXTRACT(YEAR FROM d.dist_date)::INT AS year,
       t.title_name,
       ROUND(SUM((d.copies_sent - d.copies_returned) * t.cover_price)) AS net_sales_value
FROM distribution d
JOIN titles t ON t.title_id = d.title_id
GROUP BY EXTRACT(YEAR FROM d.dist_date), t.title_name
ORDER BY year, net_sales_value DESC;


-- Q4. Monthly review: which agents returned more than 25% of their copies in January 2025?
-- Approach: WHERE limits the rows to one month; HAVING filters agents after totals are worked out.
SELECT agent_id,
       SUM(copies_sent)     AS copies_sent,
       SUM(copies_returned) AS copies_returned,
       ROUND(100.0 * SUM(copies_returned) / SUM(copies_sent), 1) AS return_pct
FROM distribution
WHERE dist_date >= DATE '2025-01-01'
  AND dist_date <  DATE '2025-02-01'
GROUP BY agent_id
HAVING 100.0 * SUM(copies_returned) / SUM(copies_sent) > 25
ORDER BY return_pct DESC;
