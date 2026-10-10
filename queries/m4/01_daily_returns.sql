-- Close-to-close daily returns with lag(). Raw prices turn every split into a fake crash,
-- so the second version scales the close on an ex-date by that day's split ratio.

WITH returns AS (
    SELECT s.ticker,
           p.trade_date,
           p.close / lag(p.close) OVER w - 1 AS ret
    FROM daily_prices p
    JOIN securities s USING (security_id)
    WINDOW w AS (PARTITION BY p.security_id ORDER BY p.trade_date)
)
SELECT ticker, trade_date, round(100 * ret, 2) AS return_pct
FROM returns
WHERE ret IS NOT NULL
ORDER BY ret
LIMIT 10;


WITH returns AS (
    SELECT s.ticker,
           p.trade_date,
           p.close * coalesce(ca.ratio, 1) / lag(p.close) OVER w - 1 AS ret
    FROM daily_prices p
    JOIN securities s USING (security_id)
    LEFT JOIN corporate_actions ca
           ON ca.security_id = p.security_id
          AND ca.ex_date     = p.trade_date
          AND ca.action_type = 'split'
    WINDOW w AS (PARTITION BY p.security_id ORDER BY p.trade_date)
)
SELECT ticker, trade_date, round(100 * ret, 2) AS return_pct
FROM returns
WHERE ret IS NOT NULL
ORDER BY ret
LIMIT 10;
