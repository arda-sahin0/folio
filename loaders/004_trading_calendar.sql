-- Rebuilds the trading calendar from the loaded prices: one row per exchange per session.

TRUNCATE trading_calendar;

INSERT INTO trading_calendar (mic_code, session_date)
SELECT DISTINCT s.mic_code, p.trade_date
FROM daily_prices p
         JOIN securities s USING (security_id);
