-- Loads daily OHLCV bars from yfinance. Yahoo adjusts prices for splits, so every bar is
-- multiplied back by the ratios of all later splits (volume divided) to store what actually traded.

DELETE FROM staging.rejects WHERE loader = '003_prices';

DROP TABLE IF EXISTS staging.raw_prices;
CREATE TABLE staging.raw_prices
(
    symbol        text,
    date          text,
    open          text,
    high          text,
    low           text,
    close         text,
    volume        text,
    reject_reason text
);

COPY staging.raw_prices (symbol, date, open, high, low, close, volume)
    FROM '/data/prices.csv' WITH (FORMAT csv, HEADER true);


UPDATE staging.raw_prices
SET reject_reason =
        CASE
            WHEN date   !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
              OR NOT pg_input_is_valid(date, 'date')        THEN 'bad date'
            WHEN open   !~ '^[0-9]+(\.[0-9]+)?$'           THEN 'bad open'
            WHEN high   !~ '^[0-9]+(\.[0-9]+)?$'           THEN 'bad high'
            WHEN low    !~ '^[0-9]+(\.[0-9]+)?$'           THEN 'bad low'
            WHEN close  !~ '^[0-9]+(\.[0-9]+)?$'           THEN 'bad close'
            WHEN volume <> '' AND volume !~ '^[0-9]+$'     THEN 'bad volume'
            WHEN low::numeric <= 0                         THEN 'non-positive price'
            WHEN high::numeric <> greatest(open::numeric, high::numeric, low::numeric, close::numeric)
              OR low::numeric  <> least(open::numeric, high::numeric, low::numeric, close::numeric)
                                                           THEN 'ohlc inconsistent'
            WHEN volume = '0'
                AND open::numeric = high::numeric
                AND high::numeric = low::numeric
                AND low::numeric  = close::numeric      THEN 'placeholder bar (no trading)'
        END;


UPDATE staging.raw_prices r
SET reject_reason = 'before trusted_from'
FROM security_sources ss
JOIN securities s USING (security_id)
WHERE r.reject_reason IS NULL
  AND ss.source = 'yfinance'
  AND ss.symbol = r.symbol
  AND s.trusted_from IS NOT NULL
  AND r.date < s.trusted_from::text;


WITH good AS MATERIALIZED (
    SELECT ss.security_id,
           r.date::date                   AS trade_date,
           r.open::numeric                AS open,
           r.high::numeric                AS high,
           r.low::numeric                 AS low,
           r.close::numeric               AS close,
           nullif(nullif(r.volume, ''), '0')::numeric  AS volume
    FROM staging.raw_prices r
    JOIN security_sources ss ON ss.source = 'yfinance' AND ss.symbol = r.symbol
    WHERE r.reject_reason IS NULL
)
INSERT INTO daily_prices (security_id, trade_date, open, high, low, close, volume)
SELECT g.security_id,
       g.trade_date,
       round(g.open  * f.factor, 4),
       round(g.high  * f.factor, 4),
       round(g.low   * f.factor, 4),
       round(g.close * f.factor, 4),
       round(g.volume / f.factor)::bigint
FROM good g
CROSS JOIN LATERAL (
    SELECT round(coalesce(exp(sum(ln(ca.ratio))), 1), 6) AS factor
    FROM corporate_actions ca
    WHERE ca.security_id = g.security_id
      AND ca.action_type = 'split'
      AND ca.ex_date > g.trade_date
) f
ON CONFLICT (security_id, trade_date) DO UPDATE
    SET open   = excluded.open,
        high   = excluded.high,
        low    = excluded.low,
        close  = excluded.close,
        volume = excluded.volume
    WHERE (daily_prices.open, daily_prices.high, daily_prices.low, daily_prices.close, daily_prices.volume)
          IS DISTINCT FROM
          (excluded.open, excluded.high, excluded.low, excluded.close, excluded.volume);

INSERT INTO staging.rejects (loader, reason, raw_row)
SELECT '003_prices', r.reject_reason, to_jsonb(r)
FROM staging.raw_prices r
WHERE r.reject_reason IS NOT NULL;

INSERT INTO staging.rejects (loader, reason, raw_row)
SELECT '003_prices', 'no symbol mapping', to_jsonb(r)
FROM staging.raw_prices r
LEFT JOIN security_sources ss ON ss.source = 'yfinance' AND ss.symbol = r.symbol
WHERE r.reject_reason IS NULL
  AND ss.security_id IS NULL;

DROP TABLE staging.raw_prices;
