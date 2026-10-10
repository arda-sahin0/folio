WITH span AS (
    SELECT security_id, min(trade_date) AS first_day, max(trade_date) AS last_day, count(*) AS bars
    FROM daily_prices
    GROUP BY security_id
), cmp AS (
    SELECT s.ticker, sp.first_day, sp.last_day, sp.bars,
           (SELECT count(*)
            FROM trading_calendar c
            WHERE c.mic_code = s.mic_code
              AND c.session_date BETWEEN sp.first_day AND sp.last_day) AS sessions
    FROM span sp
             JOIN securities s ON s.security_id = sp.security_id
)
SELECT ticker, first_day, last_day, sessions, bars, sessions - bars AS missing
FROM cmp
ORDER BY missing DESC, ticker;