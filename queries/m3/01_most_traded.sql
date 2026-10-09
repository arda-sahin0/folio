-- Q1: In 2025, which security had the highest average daily traded value (close × volume)?

SELECT s.ticker, ROUND(AVG(p.close * p.volume), 0) AS average_traded_value, count(*), count(p.volume)
FROM daily_prices p
JOIN securities s USING (security_id)
WHERE p.trade_date >= '2025-01-01' AND p.trade_date < '2026-01-01'
GROUP BY s.security_id
ORDER BY average_traded_value DESC;

SELECT s.ticker, ROUND(AVG(CASE
                       WHEN s.currency <> 'EUR' THEN p.close*p.volume / f.rate
                       ELSE p.close*p.volume
                       END), 0) AS average_traded_value,
       count(*) AS bars,
       count(f.rate) AS bars_with_rate
FROM daily_prices p
JOIN securities s USING (security_id)
LEFT JOIN fx_rates f ON f.rate_date = p.trade_date AND s.currency = f.quote_currency
WHERE p.trade_date >= '2025-01-01' AND p.trade_date < '2026-01-01'
GROUP BY s.security_id
ORDER BY average_traded_value DESC;


-- Which US trading days had no ECB rate?

SELECT p.trade_date
FROM daily_prices p
         JOIN securities s USING (security_id)
         LEFT JOIN fx_rates f
                   ON f.rate_date = p.trade_date
                       AND f.quote_currency = s.currency
WHERE s.ticker = 'AAPL'
  AND p.trade_date >= '2025-01-01' AND p.trade_date < '2026-01-01'
  AND f.rate_date IS NULL
ORDER BY p.trade_date;

-- Answer: NVDA, ~€28.9bn/day; 3 US sessions lacked an ECB rate