-- 50- and 200-session moving averages on split-adjusted closes, and every golden cross
-- (50 crosses above 200) or death cross (50 crosses below 200) since 2024.
-- A split's ratio is pushed back onto every earlier bar with a frame over the LATER rows.

WITH ratios AS (
    SELECT p.security_id,
           p.trade_date,
           p.close,
           coalesce(ca.ratio, 1) AS ratio
    FROM daily_prices p
    LEFT JOIN corporate_actions ca
           ON ca.security_id = p.security_id
          AND ca.ex_date     = p.trade_date
          AND ca.action_type = 'split'
), adjusted AS (
    SELECT security_id,
           trade_date,
           close / coalesce(exp(sum(ln(ratio)) OVER later), 1) AS adj_close
    FROM ratios
    WINDOW later AS (PARTITION BY security_id ORDER BY trade_date DESC
                     ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)
), averages AS (
    SELECT security_id,
           trade_date,
           adj_close,
           avg(adj_close) OVER w50  AS ma50,
           avg(adj_close) OVER w200 AS ma200,
           count(*)       OVER w200 AS n200
    FROM adjusted
    WINDOW w50  AS (PARTITION BY security_id ORDER BY trade_date ROWS 49 PRECEDING),
           w200 AS (PARTITION BY security_id ORDER BY trade_date ROWS 199 PRECEDING)
), signals AS (
    SELECT security_id,
           trade_date,
           adj_close,
           ma50,
           ma200,
           sign(ma50 - ma200)                                                      AS side,
           lag(sign(ma50 - ma200)) OVER (PARTITION BY security_id ORDER BY trade_date) AS prev_side
    FROM averages
    WHERE n200 = 200
)
SELECT s.ticker,
       g.trade_date,
       CASE WHEN g.side > 0 THEN 'golden cross' ELSE 'death cross' END AS signal,
       round(g.adj_close, 2) AS close,
       round(g.ma50, 2)      AS ma50,
       round(g.ma200, 2)     AS ma200
FROM signals g
JOIN securities s USING (security_id)
WHERE g.trade_date >= '2024-01-01'
  AND g.side <> g.prev_side
  AND g.side <> 0
ORDER BY s.ticker, g.trade_date;
