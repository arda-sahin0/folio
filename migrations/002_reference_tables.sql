CREATE TABLE IF NOT EXISTS currencies(
    code text PRIMARY KEY,
    CONSTRAINT currency_format CHECK (code ~'^[A-Z]{3}$')
);

CREATE TABLE IF NOT EXISTS exchanges(
    mic_code text PRIMARY KEY,
    name text NOT NULL,
    country text NOT NULL,
    timezone text NOT NULL,
    currency text NOT NULL REFERENCES currencies (code),
    CONSTRAINT mic_format CHECK (mic_code ~ '^[A-Z0-9]{4}$'),
    CONSTRAINT country_format CHECK (country ~ '^[A-Z]{2}$')
);


CREATE TABLE IF NOT EXISTS securities(
    security_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY ,
    ticker text NOT NULL,
    name text NOT NULL,
    mic_code text NOT NULL,
    sector text,
    currency text NOT NULL,
    listed_on date,
    delisted_on date,
    isin text,
    CONSTRAINT date_error CHECK ( delisted_on > listed_on ),
    CONSTRAINT isin_format CHECK (isin ~ '^[A-Z]{2}[A-Z0-9]{9}[0-9]$'),
    CONSTRAINT securities_exchange_fk FOREIGN KEY(mic_code) REFERENCES exchanges (mic_code),
    CONSTRAINT securities_currency_fk FOREIGN KEY(currency) REFERENCES currencies (code),
    CONSTRAINT unique_mic_ticker UNIQUE (mic_code, ticker),
    CONSTRAINT ticker_present CHECK (ticker <> '')
);
