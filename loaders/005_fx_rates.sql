-- 005_fx_rates.sql
--
-- Loads the ECB euro reference rates written by scripts/fetch_fx.py.
-- Each row of data/fx_rates.csv means: on <date>, 1 EUR = <rate> <currency>.

DELETE FROM staging.rejects WHERE loader = '005_fx_rates';

DROP TABLE IF EXISTS staging.raw_fx;
CREATE TABLE staging.raw_fx
(
    date          text,
    currency      text,
    rate          text,
    reject_reason text          -- NULL means the row is good
);

COPY staging.raw_fx (date, currency, rate)
    FROM '/data/fx_rates.csv' WITH (FORMAT csv, HEADER true);

UPDATE staging.raw_fx
SET reject_reason =
        CASE
            WHEN date     !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
              OR NOT pg_input_is_valid(date, 'date')        THEN 'bad date'   -- regex = format, this = a real date
            WHEN currency !~ '^[A-Z]{3}$'                   THEN 'bad currency code'
            WHEN currency = 'EUR'                           THEN 'quote equals base'
            WHEN rate     !~ '^[0-9]+(\.[0-9]+)?$'          THEN 'bad rate'
            WHEN rate::numeric <= 0                         THEN 'non-positive rate'
        END;

-- Currencies our currencies table doesn't know. Mostly ones that no longer
-- exist: the ECB still publishes history for e.g. CYP (Cyprus pound, replaced by
-- the euro in 2008) and TRL (old Turkish lira, replaced by TRY in 2005), but
-- migration 003 only loaded currencies that are still in use.
--
-- NOT EXISTS is the other way to write an anti-join (compare the
-- LEFT JOIN ... IS NULL form in the other loaders). Same result, usually the same plan.
UPDATE staging.raw_fx r
SET reject_reason = 'unknown currency'
WHERE r.reject_reason IS NULL
  AND NOT EXISTS (SELECT 1 FROM currencies c WHERE c.code = r.currency);

WITH good AS MATERIALIZED (
    SELECT r.currency,
           r.date::date     AS rate_date,
           r.rate::numeric  AS rate
    FROM staging.raw_fx r
    WHERE r.reject_reason IS NULL
)
INSERT INTO fx_rates (base_currency, quote_currency, rate_date, rate)
SELECT 'EUR', currency, rate_date, round(rate, 10)
FROM good
ON CONFLICT (base_currency, quote_currency, rate_date) DO UPDATE
    SET rate = excluded.rate
    WHERE fx_rates.rate IS DISTINCT FROM excluded.rate;

INSERT INTO staging.rejects (loader, reason, raw_row)
SELECT '005_fx_rates', r.reject_reason, to_jsonb(r)
FROM staging.raw_fx r
WHERE r.reject_reason IS NOT NULL;

DROP TABLE staging.raw_fx;
