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

COPY staging.raw_prices (symbol, date, open, high, low, close, volume) FROM '/data/prices.csv' WITH (FORMAT csv, HEADER true);

UPDATE staging.raw_prices
SET reject_reason =
        CASE
            WHEN date !~ '^\d{4}-\d{2}-\d{2}$' THEN 'bad date'
            WHEN open !~ '^[0-9]+(\.[0-9]+)?$' THEN 'bad open'
            WHEN high !~ '^[0-9]+(\.[0-9]+)?$' THEN 'bad high'
            WHEN low !~ '^[0-9]+(\.[0-9]+)?$' THEN 'bad low'
            WHEN close !~ '^[0-9]+(\.[0-9]+)?$' THEN 'bad close'
            WHEN volume <> '' AND volume !~ '^[0-9]+$' THEN 'bad volume'
            WHEN low::numeric <= 0 THEN 'non-positive price'
            WHEN high::numeric <> greatest(open::numeric, high::numeric, low::numeric, close::numeric)
                OR low::numeric <> least(open::numeric, high::numeric, low::numeric, close::numeric)
                THEN 'ohlc inconsistent'
            END;

INSERT INTO public.daily_prices (security_id, trade_date, open, high, low, close, volume)
SELECT ss.security_id,
       r.date::date,
       r.open::numeric,
       r.high::numeric,
       r.low::numeric,
       r.close::numeric,
       nullif(r.volume, '')::bigint
FROM staging.raw_prices r
         JOIN security_sources ss ON ss.source = 'yfinance' AND ss.symbol = r.symbol
WHERE r.reject_reason IS NULL
ON CONFLICT (security_id, trade_date) DO UPDATE SET open   = excluded.open,
                                                    high   = excluded.high,
                                                    low    = excluded.low,
                                                    close  = excluded.close,
                                                    volume = excluded.volume
WHERE daily_prices.close IS DISTINCT FROM excluded.close
   OR daily_prices.volume IS DISTINCT FROM excluded.volume;


