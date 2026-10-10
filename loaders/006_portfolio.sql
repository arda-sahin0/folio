-- Loads the demo account and its append-only ledger. A booked transaction never changes:
-- a CSV row that differs from it is rejected, and a malformed row fails the txn_shape constraint.

DELETE FROM staging.rejects WHERE loader = '006_portfolio';


-- ===========================================================================
-- 1. ACCOUNTS
-- ===========================================================================
DROP TABLE IF EXISTS staging.raw_accounts;
CREATE TABLE staging.raw_accounts
(
    name          text,
    base_currency text,
    opening_date  text
);

COPY staging.raw_accounts FROM '/data/accounts.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO accounts (name, base_currency, opening_date)
SELECT name, base_currency, opening_date::date
FROM staging.raw_accounts
ON CONFLICT (name) DO UPDATE
    SET base_currency = excluded.base_currency,
        opening_date  = excluded.opening_date
    WHERE (accounts.base_currency, accounts.opening_date)
          IS DISTINCT FROM
          (excluded.base_currency, excluded.opening_date);

DROP TABLE staging.raw_accounts;


-- ===========================================================================
-- 2. TRANSACTIONS
-- ===========================================================================
DROP TABLE IF EXISTS staging.raw_transactions;
CREATE TABLE staging.raw_transactions
(
    external_ref  text,
    account       text,
    txn_type      text,
    trade_date    text,
    mic_code      text,
    ticker        text,
    quantity      text,
    price         text,
    amount        text,
    reject_reason text
);

COPY staging.raw_transactions
     (external_ref, account, txn_type, trade_date, mic_code, ticker, quantity, price, amount)
    FROM '/data/transactions.csv' WITH (FORMAT csv, HEADER true);


UPDATE staging.raw_transactions
SET reject_reason =
        CASE
            WHEN coalesce(external_ref, '') = ''                  THEN 'missing external_ref'
            WHEN coalesce(trade_date, '') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
              OR NOT pg_input_is_valid(trade_date, 'date')          THEN 'bad date'
            WHEN coalesce(quantity, '') !~ '^([0-9]+(\.[0-9]+)?)?$' THEN 'bad quantity'
            WHEN coalesce(price,    '') !~ '^([0-9]+(\.[0-9]+)?)?$' THEN 'bad price'
            WHEN coalesce(amount,   '') !~ '^([0-9]+(\.[0-9]+)?)?$' THEN 'bad amount'
        END;

UPDATE staging.raw_transactions r
SET reject_reason = 'duplicate external_ref in file'
FROM (SELECT external_ref
      FROM staging.raw_transactions
      GROUP BY external_ref
      HAVING count(*) > 1) d
WHERE r.external_ref = d.external_ref
  AND r.reject_reason IS NULL;

UPDATE staging.raw_transactions r
SET reject_reason = 'unknown account'
WHERE r.reject_reason IS NULL
  AND NOT EXISTS (SELECT 1 FROM accounts a WHERE a.name = r.account);

UPDATE staging.raw_transactions r
SET reject_reason = 'unknown txn_type'
WHERE r.reject_reason IS NULL
  AND NOT EXISTS (SELECT 1 FROM txn_types t WHERE t.code = r.txn_type);

UPDATE staging.raw_transactions r
SET reject_reason = 'unknown security'
WHERE r.reject_reason IS NULL
  AND coalesce(r.ticker, '') <> ''
  AND NOT EXISTS (SELECT 1 FROM securities s
                  WHERE s.mic_code = r.mic_code AND s.ticker = r.ticker);


CREATE TEMP TABLE parsed AS
SELECT r.external_ref,
       a.account_id,
       r.txn_type,
       r.trade_date::date         AS trade_date,
       s.security_id,
       nullif(r.quantity, '')::numeric AS quantity,
       nullif(r.price,    '')::numeric AS price,
       nullif(r.amount,   '')::numeric AS amount
FROM staging.raw_transactions r
JOIN accounts a ON a.name = r.account
LEFT JOIN securities s ON s.mic_code = r.mic_code AND s.ticker = r.ticker
WHERE r.reject_reason IS NULL;

UPDATE staging.raw_transactions r
SET reject_reason = 'differs from booked transaction'
FROM parsed p
JOIN transactions t ON t.external_ref = p.external_ref
WHERE r.external_ref = p.external_ref
  AND (t.account_id, t.txn_type, t.trade_date, t.security_id, t.quantity, t.price, t.amount)
      IS DISTINCT FROM
      (p.account_id, p.txn_type, p.trade_date, p.security_id, p.quantity, p.price, p.amount);

INSERT INTO transactions
       (external_ref, account_id, txn_type, trade_date, security_id, quantity, price, amount)
SELECT p.external_ref, p.account_id, p.txn_type, p.trade_date,
       p.security_id, p.quantity, p.price, p.amount
FROM parsed p
JOIN staging.raw_transactions r ON r.external_ref = p.external_ref
WHERE r.reject_reason IS NULL
ON CONFLICT (external_ref) DO NOTHING;
INSERT INTO staging.rejects (loader, reason, raw_row)
SELECT '006_portfolio', r.reject_reason, to_jsonb(r)
FROM staging.raw_transactions r
WHERE r.reject_reason IS NOT NULL;

DROP TABLE parsed;
DROP TABLE staging.raw_transactions;
