WITH years AS (
    SELECT generate_series(
                   (SELECT extract(year FROM min(opening_date))::int FROM accounts),
                   extract(year FROM current_date)::int) AS year
), held AS (
    SELECT DISTINCT security_id FROM transactions WHERE security_id IS NOT NULL
), divs AS (
    SELECT security_id, extract(year FROM trade_date)::int AS year, sum(amount) AS income
    FROM transactions
    WHERE txn_type = 'dividend'
    GROUP BY security_id, year
)
SELECT y.year, s.ticker, s.currency, coalesce(d.income, 0) AS dividend_income
FROM years y
         CROSS JOIN held h
         JOIN securities s ON s.security_id = h.security_id
         LEFT JOIN divs d ON d.security_id = h.security_id AND d.year = y.year
ORDER BY y.year, s.ticker;