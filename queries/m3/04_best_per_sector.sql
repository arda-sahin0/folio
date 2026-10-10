WITH bounds AS (
    SELECT security_id, min(trade_date) AS first_day, max(trade_date) AS last_day
    FROM daily_prices
    WHERE trade_date >= '2025-01-01' AND trade_date < '2026-01-01'
    GROUP BY security_id
), perf AS (
    SELECT s.sector, s.ticker, l.close / f.close - 1 AS ret
    FROM bounds b
             JOIN securities s   ON s.security_id = b.security_id
             JOIN daily_prices f ON f.security_id = b.security_id AND f.trade_date = b.first_day
             JOIN daily_prices l ON l.security_id = b.security_id AND l.trade_date = b.last_day
)
SELECT DISTINCT ON (sector) sector, ticker, round(100 * ret, 2) AS return_pct
FROM perf
ORDER BY sector, ret DESC;

SELECT s.ticker, ca.ex_date, ca.ratio
FROM corporate_actions ca
         JOIN securities s USING (security_id)
WHERE ca.action_type = 'split'
  AND ca.ex_date >= '2025-01-01' AND ca.ex_date < '2026-01-01';