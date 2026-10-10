-- Maximum drawdown per security: the worst fall from a previous peak, with the peak date,
-- the trough date and the date the old peak was regained (NULL if it never was).
-- Growth is rebuilt from split-adjusted daily returns as exp(sum(ln(1 + r))).

WITH returns AS (
    SELECT p.security_id,
           p.trade_date,
           p.close * coalesce(ca.ratio, 1) / lag(p.close) OVER w - 1 AS ret
    FROM daily_prices p
    LEFT JOIN corporate_actions ca
           ON ca.security_id = p.security_id
          AND ca.ex_date     = p.trade_date
          AND ca.action_type = 'split'
    WINDOW w AS (PARTITION BY p.security_id ORDER BY p.trade_date)
), growth AS (
    SELECT security_id,
           trade_date,
           exp(sum(ln(1 + coalesce(ret, 0)::float8)) OVER w) AS growth
    FROM returns
    WINDOW w AS (PARTITION BY security_id ORDER BY trade_date ROWS UNBOUNDED PRECEDING)
), peaks AS (
    SELECT security_id,
           trade_date,
           growth,
           max(growth) OVER w AS peak
    FROM growth
    WINDOW w AS (PARTITION BY security_id ORDER BY trade_date ROWS UNBOUNDED PRECEDING)
), drawdowns AS (
    SELECT security_id,
           trade_date,
           growth,
           peak,
           growth / peak - 1 AS drawdown,
           max(CASE WHEN growth = peak THEN trade_date END) OVER w AS peak_date
    FROM peaks
    WINDOW w AS (PARTITION BY security_id ORDER BY trade_date ROWS UNBOUNDED PRECEDING)
), worst AS (
    SELECT DISTINCT ON (security_id) *
    FROM drawdowns
    ORDER BY security_id, drawdown, trade_date
)
SELECT s.ticker,
       round(100 * w.drawdown::numeric, 1) AS max_drawdown_pct,
       w.peak_date,
       w.trade_date                        AS trough_date,
       r.recovered_on
FROM worst w
JOIN securities s USING (security_id)
CROSS JOIN LATERAL (
    SELECT min(d.trade_date) AS recovered_on
    FROM drawdowns d
    WHERE d.security_id = w.security_id
      AND d.trade_date  > w.trade_date
      AND d.growth     >= w.peak
) r
ORDER BY w.drawdown;
