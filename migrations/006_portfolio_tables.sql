CREATE TABLE IF NOT EXISTS txn_types
(
    code             text PRIMARY KEY,
    description      text     NOT NULL,
    cash_sign        smallint NOT NULL,
    affects_position boolean  NOT NULL,
    CONSTRAINT cash_sign_valid CHECK ( cash_sign IN (-1, 0, 1))
);

INSERT INTO txn_types (code, description, cash_sign, affects_position) VALUES
                       ('buy',        'Purchase of securities',  -1, true),
                       ('sell',       'Sale of securities',       1, true),
                       ('dividend',   'Cash dividend received',   1, false),
                       ('deposit',    'Cash paid into account',   1, false),
                       ('withdrawal', 'Cash taken out',          -1, false),
                       ('fee',        'Custody or platform fee', -1, false);

CREATE TABLE IF NOT EXISTS accounts
(
    name          text NOT NULL,
    account_id    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    base_currency text NOT NULL,
    opening_date  date NOT NULL,
    FOREIGN KEY (base_currency) REFERENCES currencies (code)
);

CREATE TABLE IF NOT EXISTS transactions
(
    txn_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    txn_type    text    NOT NULL REFERENCES txn_types (code),
    trade_date  date    NOT NULL,
    account_id  integer NOT NULL,
    security_id integer,
    quantity    numeric(24, 8),
    price       numeric(24, 8),
    amount      numeric(24, 8),

    FOREIGN KEY (account_id) REFERENCES accounts (account_id),
    FOREIGN KEY (security_id) REFERENCES securities (security_id),

    CONSTRAINT quantity_positive CHECK (quantity > 0),
    CONSTRAINT price_positive CHECK (price > 0),
    CONSTRAINT amount_positive CHECK (amount > 0),

    CONSTRAINT txn_shape CHECK (
        (txn_type in ('buy', 'sell')
            AND security_id IS NOT NULL
            AND quantity IS NOT NULL
            AND price IS NOT NULL
            AND amount IS NULL)

        OR (txn_type in ('withdrawal', 'deposit', 'fee')
            AND security_id IS NULL
            AND quantity IS NULL
            AND price IS NULL
            AND amount IS NOT NULL
            )

        OR (txn_type = 'dividend'
            AND security_id IS NOT NULL
            AND amount IS NOT NULL
            AND quantity IS NULL
            AND price IS NULL
        )
)
);