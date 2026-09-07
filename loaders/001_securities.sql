DROP TABLE IF EXISTS staging.raw_securities;
CREATE TABLE staging.raw_securities
(
    ticker          text,
    name            text,
    mic_code        text,
    currency        text,
    sector          text,
    yfinance_symbol text
);

COPY staging.raw_securities FROM '/data/securities.csv' WITH (FORMAT csv, HEADER true);
INSERT INTO securities (ticker, name, mic_code, currency, sector)
SELECT ticker, name, mic_code, currency, sector
FROM staging.raw_securities
ON CONFLICT (mic_code, ticker) DO UPDATE SET name     = excluded.name,
                                             currency = excluded.currency,
                                             sector   = excluded.sector;

INSERT INTO security_sources(security_id, source, symbol)
SELECT s.security_id, 'yfinance', r.yfinance_symbol
FROM staging.raw_securities r
         JOIN securities s
              ON s.mic_code = r.mic_code AND s.ticker = r.ticker
WHERE coalesce(r.yfinance_symbol, '') <> ''
ON CONFLICT (security_id, source) DO UPDATE
    SET symbol = excluded.symbol;