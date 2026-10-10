WITH positions AS (
    SELECT security_id,
           sum(CASE txn_type WHEN 'buy' THEN quantity ELSE -quantity END) AS qty
    FROM transactions
    WHERE txn_type IN ('buy', 'sell')
    GROUP BY security_id
    HAVING sum(CASE txn_type WHEN 'buy' THEN quantity ELSE -quantity END) <> 0
), latest_price AS (
    SELECT DISTINCT ON (security_id) security_id, trade_date, close
    FROM daily_prices
    WHERE security_id IN (SELECT security_id FROM positions)
    ORDER BY security_id, trade_date DESC
), latest_fx AS (
    SELECT DISTINCT ON (quote_currency) quote_currency, rate
    FROM fx_rates
    ORDER BY quote_currency, rate_date DESC
), valued AS (
    SELECT e.country,
           s.ticker,
           CASE WHEN s.currency = 'EUR' THEN pos.qty * lp.close
                ELSE pos.qty * lp.close / fx.rate
               END AS value_eur
    FROM positions pos
             JOIN securities s     ON s.security_id = pos.security_id
             JOIN exchanges e      ON e.mic_code = s.mic_code
             JOIN latest_price lp  ON lp.security_id = pos.security_id
             LEFT JOIN latest_fx fx ON fx.quote_currency = s.currency
)
SELECT country,
       round(sum(value_eur), 2)                                          AS value_eur,
       round(100 * sum(value_eur) / (SELECT sum(value_eur) FROM valued), 1) AS share_pct
FROM valued
GROUP BY country
ORDER BY value_eur DESC;