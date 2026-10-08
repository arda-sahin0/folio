DROP TABLE IF EXISTS staging.raw_securities;
CREATE TABLE staging.raw_securities
(
    ticker          text,
    name            text,
    mic_code        text,
    currency        text,
    sector          text,
    yfinance_symbol text,
    trusted_from    text
);

COPY staging.raw_securities FROM '/data/securities.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO securities (ticker, name, mic_code, currency, sector, trusted_from)
SELECT ticker, name, mic_code, currency, sector, nullif(trusted_from, '')::date
FROM staging.raw_securities
ON CONFLICT (mic_code, ticker) DO UPDATE
    SET name         = excluded.name,
        currency     = excluded.currency,
        sector       = excluded.sector,
        trusted_from = excluded.trusted_from
    WHERE (securities.name, securities.currency, securities.sector, securities.trusted_from)
          IS DISTINCT FROM
          (excluded.name, excluded.currency, excluded.sector, excluded.trusted_from);

INSERT INTO security_sources (security_id, source, symbol)
SELECT s.security_id, 'yfinance', r.yfinance_symbol
FROM staging.raw_securities r
JOIN securities s
  ON s.mic_code = r.mic_code
 AND s.ticker   = r.ticker
WHERE coalesce(r.yfinance_symbol, '') <> ''
ON CONFLICT (security_id, source) DO UPDATE
    SET symbol = excluded.symbol
    WHERE security_sources.symbol IS DISTINCT FROM excluded.symbol;

DROP TABLE staging.raw_securities;
