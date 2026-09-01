CREATE TABLE IF NOT EXISTS fx_rates (
    base_currency   text NOT NULL REFERENCES currencies (code),
    quote_currency  text NOT NULL REFERENCES currencies (code),
    rate_date       date NOT NULL,
    rate            numeric(20,10) NOT NULL,

    CONSTRAINT fx_rates_pk              PRIMARY KEY (base_currency, quote_currency, rate_date),
    CONSTRAINT fx_rate_positive         CHECK ( rate > 0 ),
    CONSTRAINT fx_currencies_differ     CHECK ( base_currency <> quote_currency )
);


