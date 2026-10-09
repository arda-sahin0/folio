DELETE FROM staging.rejects WHERE loader = '002_corporate_actions';


-- ===========================================================================
-- 1. SPLITS
-- ===========================================================================
DROP TABLE IF EXISTS staging.raw_splits;
CREATE TABLE staging.raw_splits
(
    symbol        text,
    ex_date       text,
    ratio         text,
    reject_reason text
);

COPY staging.raw_splits (symbol, ex_date, ratio)
    FROM '/data/splits.csv' WITH (FORMAT csv, HEADER true);

UPDATE staging.raw_splits
SET reject_reason =
        CASE
            WHEN ex_date !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN 'bad date'
            WHEN ratio   !~ '^[0-9]+(\.[0-9]+)?$'          THEN 'bad ratio'
            WHEN ratio::numeric <= 0                       THEN 'non-positive ratio'
        END;


WITH good AS MATERIALIZED (
    SELECT ss.security_id,
           r.ex_date::date    AS ex_date,
           r.ratio::numeric   AS ratio
    FROM staging.raw_splits r
    JOIN security_sources ss ON ss.source = 'yfinance' AND ss.symbol = r.symbol
    WHERE r.reject_reason IS NULL
)
INSERT INTO corporate_actions (security_id, ex_date, action_type, ratio)
SELECT security_id,
       ex_date,
       'split',
       round(exp(sum(ln(ratio))), 6)
FROM good
GROUP BY security_id, ex_date
ON CONFLICT (ex_date, security_id, action_type) DO UPDATE
    SET ratio = excluded.ratio
    WHERE corporate_actions.ratio IS DISTINCT FROM excluded.ratio;

INSERT INTO staging.rejects (loader, reason, raw_row)
SELECT '002_corporate_actions', r.reject_reason, to_jsonb(r)
FROM staging.raw_splits r
WHERE r.reject_reason IS NOT NULL;

INSERT INTO staging.rejects (loader, reason, raw_row)
SELECT '002_corporate_actions', 'no symbol mapping', to_jsonb(r)
FROM staging.raw_splits r
LEFT JOIN security_sources ss ON ss.source = 'yfinance' AND ss.symbol = r.symbol
WHERE r.reject_reason IS NULL
  AND ss.security_id IS NULL;

DROP TABLE staging.raw_splits;


-- ===========================================================================
-- 2. DIVIDENDS  (de-adjusted using the splits loaded above)
-- ===========================================================================
DROP TABLE IF EXISTS staging.raw_dividends;
CREATE TABLE staging.raw_dividends
(
    symbol        text,
    ex_date       text,
    amount        text,
    reject_reason text
);

COPY staging.raw_dividends (symbol, ex_date, amount)
    FROM '/data/dividends.csv' WITH (FORMAT csv, HEADER true);

UPDATE staging.raw_dividends
SET reject_reason =
        CASE
            WHEN ex_date !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN 'bad date'
            WHEN amount  !~ '^[0-9]+(\.[0-9]+)?$'          THEN 'bad amount'
            WHEN amount::numeric <= 0                      THEN 'non-positive amount'
        END;

WITH good AS MATERIALIZED (
    SELECT ss.security_id,
           r.ex_date::date    AS ex_date,
           r.amount::numeric  AS amount
    FROM staging.raw_dividends r
    JOIN security_sources ss ON ss.source = 'yfinance' AND ss.symbol = r.symbol
    WHERE r.reject_reason IS NULL
)
INSERT INTO corporate_actions (security_id, ex_date, action_type, amount)
SELECT g.security_id,
       g.ex_date,
       'dividend',
       round(sum(g.amount * f.factor), 4)
FROM good g

CROSS JOIN LATERAL (
    SELECT round(coalesce(exp(sum(ln(ca.ratio))), 1), 6) AS factor
    FROM corporate_actions ca
    WHERE ca.security_id = g.security_id
      AND ca.action_type = 'split'
      AND ca.ex_date > g.ex_date
) f
GROUP BY g.security_id, g.ex_date
ON CONFLICT (ex_date, security_id, action_type) DO UPDATE
    SET amount = excluded.amount
    WHERE corporate_actions.amount IS DISTINCT FROM excluded.amount;

INSERT INTO staging.rejects (loader, reason, raw_row)
SELECT '002_corporate_actions', r.reject_reason, to_jsonb(r)
FROM staging.raw_dividends r
WHERE r.reject_reason IS NOT NULL;

INSERT INTO staging.rejects (loader, reason, raw_row)
SELECT '002_corporate_actions', 'no symbol mapping', to_jsonb(r)
FROM staging.raw_dividends r
LEFT JOIN security_sources ss ON ss.source = 'yfinance' AND ss.symbol = r.symbol
WHERE r.reject_reason IS NULL
  AND ss.security_id IS NULL;

DROP TABLE staging.raw_dividends;
