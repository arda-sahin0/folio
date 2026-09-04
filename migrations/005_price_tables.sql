CREATE DOMAIN price AS numeric(18, 6) CHECK (VALUE > 0);

CREATE TABLE IF NOT EXISTS fx_rates
(
    base_currency  text            NOT NULL REFERENCES currencies (code),
    quote_currency text            NOT NULL REFERENCES currencies (code),
    rate_date      date            NOT NULL,
    rate           numeric(20, 10) NOT NULL,

    CONSTRAINT fx_rates_pk PRIMARY KEY (base_currency, quote_currency, rate_date),
    CONSTRAINT fx_rate_positive CHECK ( rate > 0 ),
    CONSTRAINT fx_currencies_differ CHECK ( base_currency <> quote_currency )
);

CREATE TABLE IF NOT EXISTS corporate_actions
(
    action_type text NOT NULL,
    ex_date     date NOT NULL,
    security_id integer,
    ratio       numeric(12, 6),
    amount      numeric(18, 6),

    FOREIGN KEY (security_id) REFERENCES securities (security_id),
    PRIMARY KEY (ex_date, security_id, action_type),
    CONSTRAINT ratio_positive CHECK (ratio > 0),
    CONSTRAINT amount_positive CHECK (amount > 0),
    CONSTRAINT action_value_matches_type CHECK ((action_type = 'split' AND ratio IS NOT NULL AND amount IS NULL) OR
                                                (action_type = 'dividend' AND amount IS NOT NULL AND ratio IS NULL))
);

CREATE TABLE IF NOT EXISTS trading_calendar
(
    mic_code     text NOT NULL,
    session_date date NOT NULL,
    FOREIGN KEY (mic_code) REFERENCES exchanges (mic_code),
    PRIMARY KEY (mic_code, session_date)
);


CREATE TABLE IF NOT EXISTS daily_prices
(
    security_id integer,
    trade_date  date  NOT NULL,
    open        price NOT NULL,
    high        price NOT NULL,
    low         price NOT NULL,
    close       price NOT NULL,
    volume      bigint,
    FOREIGN KEY (security_id) REFERENCES securities (security_id),
    PRIMARY KEY (security_id, trade_date),
    CONSTRAINT positive_volume CHECK (volume >= 0),
    CONSTRAINT high_is_highest CHECK (high = greatest(open, high, low, close)),
    CONSTRAINT low_is_lowest CHECK (low = least(open, high, low, close))
);
