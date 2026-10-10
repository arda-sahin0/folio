WITH nyse AS (
    SELECT session_date FROM trading_calendar
    WHERE mic_code = 'XNYS' AND session_date >= '2025-01-01' AND session_date < '2026-01-01'
), xetra AS (
    SELECT session_date FROM trading_calendar
    WHERE mic_code = 'XETR' AND session_date >= '2025-01-01' AND session_date < '2026-01-01'
)
SELECT session_date, 'NYSE only' AS open_on
FROM (SELECT session_date FROM nyse EXCEPT SELECT session_date FROM xetra) a
UNION ALL
SELECT session_date, 'Xetra only'
FROM (SELECT session_date FROM xetra EXCEPT SELECT session_date FROM nyse) b
ORDER BY session_date;

SELECT count(*) AS both_open
FROM (SELECT session_date FROM trading_calendar WHERE mic_code = 'XNYS'
                                                  AND session_date >= '2025-01-01' AND session_date < '2026-01-01'
      INTERSECT
      SELECT session_date FROM trading_calendar WHERE mic_code = 'XETR'
                                                  AND session_date >= '2025-01-01' AND session_date < '2026-01-01') t;

SELECT coalesce(n.session_date, x.session_date) AS day,
       n.session_date IS NOT NULL AS nyse_open,
       x.session_date IS NOT NULL AS xetra_open
FROM (SELECT session_date FROM trading_calendar WHERE mic_code = 'XNYS'
                                                  AND session_date >= '2025-01-01' AND session_date < '2026-01-01') n
         FULL JOIN
     (SELECT session_date FROM trading_calendar WHERE mic_code = 'XETR'
                                                  AND session_date >= '2025-01-01' AND session_date < '2026-01-01') x
     ON x.session_date = n.session_date
WHERE n.session_date IS NULL OR x.session_date IS NULL
ORDER BY day;