-- Q2: What was each security's best and worst single day?

SELECT s.name, ROUND(100*MAX((d.close - d.open) / d.open), 2) AS best, ROUND(100*MIN((d.close - d.open) / d.open),2) AS worst
FROM daily_prices d
JOIN securities s on d.security_id = s.security_id
GROUP BY d.security_id, s.name
ORDER BY best DESC, worst;


-- on which dates?

WITH extremes AS (
    SELECT d.security_id,
           s.name,
           max((d.close - d.open) / d.open) AS best,
           min((d.close - d.open) / d.open) AS worst
    FROM daily_prices d
             JOIN securities s USING (security_id)
    GROUP BY d.security_id, s.name
)
SELECT e.name,
       CASE WHEN (p.close - p.open) / p.open = e.best THEN 'best'
            ELSE 'worst'
           END                                       AS day_type,
       p.trade_date,
       round(100 * (p.close - p.open) / p.open, 2) AS return_pct
FROM extremes e
         JOIN daily_prices p
              ON p.security_id = e.security_id
                  AND (   (p.close - p.open) / p.open = e.best
                      OR (p.close - p.open) / p.open = e.worst)
ORDER BY e.name, day_type, p.trade_date;