SELECT p.trade_date,
       count(*)                                    AS traded,
       count(*) FILTER (WHERE p.close < p.open)    AS fell,
       round(100.0 * count(*) FILTER (WHERE p.close < p.open) / count(*), 1) AS fell_pct
FROM daily_prices p
GROUP BY p.trade_date
HAVING count(*) FILTER (WHERE p.close < p.open) > 0.8 * count(*)
   AND count(*) >= 10
ORDER BY fell_pct DESC, p.trade_date;

WITH breadth AS (
    SELECT p.trade_date
    FROM daily_prices p
    GROUP BY p.trade_date
    HAVING count(*) FILTER (WHERE p.close < p.open) > 0.8 * count(*)
       AND count(*) >= 10
)
SELECT extract(year FROM trade_date)::int AS year, count(*) AS days
FROM breadth
GROUP BY year
ORDER BY year;