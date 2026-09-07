\set ON_ERROR_STOP off

BEGIN;

-- valid rows

INSERT INTO securities (ticker, name, mic_code, currency, sector)
VALUES ('TEST', 'Test Corporation', 'XNAS', 'USD', 'Technology');

INSERT INTO accounts (name, base_currency, opening_date)
VALUES ('Test Account', 'EUR', DATE '2020-01-01');


-- currencies


--lowercase code violates currency_format
SAVEPOINT s; INSERT INTO currencies (code) VALUES ('usd'); ROLLBACK TO s;

-- two letters
SAVEPOINT s; INSERT INTO currencies (code) VALUES ('US'); ROLLBACK TO s;

-- duplicate primary key
SAVEPOINT s; INSERT INTO currencies (code) VALUES ('USD'); ROLLBACK TO s;


-- exchanges

-- five-character MIC
SAVEPOINT s;
INSERT INTO exchanges (mic_code, name, country, timezone, currency)
VALUES ('XNASD', 'Too Long', 'US', 'America/New_York', 'USD');
ROLLBACK TO s;

-- three-letter country code
SAVEPOINT s;
INSERT INTO exchanges (mic_code, name, country, timezone, currency)
VALUES ('XTST', 'Bad Country', 'USA', 'America/New_York', 'USD');
ROLLBACK TO s;

-- currency not present in currencies
SAVEPOINT s;
INSERT INTO exchanges (mic_code, name, country, timezone, currency)
VALUES ('XTST', 'Bad Currency', 'US', 'America/New_York', 'ZZZ');
ROLLBACK TO s;

-- valid
SAVEPOINT s;
INSERT INTO exchanges (mic_code, name, country, timezone, currency)
VALUES ('XTST', 'Test Exchange', 'US', 'America/New_York', 'USD');
ROLLBACK TO s;


-- securities

-- empty ticker
SAVEPOINT s;
INSERT INTO securities (ticker, name, mic_code, currency)
VALUES ('', 'Empty Ticker', 'XNAS', 'USD');
ROLLBACK TO s;

-- exchange does not exist
SAVEPOINT s;
INSERT INTO securities (ticker, name, mic_code, currency)
VALUES ('GHOST', 'Ghost Corp', 'ZZZZ', 'USD');
ROLLBACK TO s;

-- same ticker twice on the same exchange
SAVEPOINT s;
INSERT INTO securities (ticker, name, mic_code, currency)
VALUES ('TEST', 'Duplicate', 'XNAS', 'USD');
ROLLBACK TO s;

-- same ticker on a different exchange
SAVEPOINT s;
INSERT INTO securities (ticker, name, mic_code, currency)
VALUES ('TEST', 'Test Corporation', 'XETR', 'EUR');
ROLLBACK TO s;

-- delisted before listed
SAVEPOINT s;
INSERT INTO securities (ticker, name, mic_code, currency, listed_on, delisted_on)
VALUES ('DEAD', 'Dead Corp', 'XNAS', 'USD', DATE '2020-01-01', DATE '2019-01-01');
ROLLBACK TO s;

-- insert into GENERATED ALWAYS
SAVEPOINT s;
INSERT INTO securities (security_id, ticker, name, mic_code, currency)
VALUES (999, 'FORCE', 'Forced Id', 'XNAS', 'USD');
ROLLBACK TO s;


-- daily_prices

-- high is not the highest
SAVEPOINT s;
INSERT INTO daily_prices (security_id, trade_date, open, high, low, close, volume)
SELECT security_id, DATE '2025-10-03', 300, 200, 100, 150, 1000
FROM securities WHERE ticker = 'TEST' AND mic_code = 'XNAS';
ROLLBACK TO s;

-- low is not the lowest
SAVEPOINT s;
INSERT INTO daily_prices (security_id, trade_date, open, high, low, close, volume)
SELECT security_id, DATE '2025-10-03', 100, 300, 200, 150, 1000
FROM securities WHERE ticker = 'TEST' AND mic_code = 'XNAS';
ROLLBACK TO s;

-- negative volume
SAVEPOINT s;
INSERT INTO daily_prices (security_id, trade_date, open, high, low, close, volume)
SELECT security_id, DATE '2025-10-03', 100, 110, 90, 105, -1
FROM securities WHERE ticker = 'TEST' AND mic_code = 'XNAS';
ROLLBACK TO s;

-- zero price violates the price domain
SAVEPOINT s;
INSERT INTO daily_prices (security_id, trade_date, open, high, low, close, volume)
SELECT security_id, DATE '2025-10-03', 0, 110, 0, 105, 1000
FROM securities WHERE ticker = 'TEST' AND mic_code = 'XNAS';
ROLLBACK TO s;

-- valid first duplicate later
SAVEPOINT s;
INSERT INTO daily_prices (security_id, trade_date, open, high, low, close, volume)
SELECT security_id, DATE '2025-10-03', 100, 110, 90, 105, 1000
FROM securities WHERE ticker = 'TEST' AND mic_code = 'XNAS';

INSERT INTO daily_prices (security_id, trade_date, open, high, low, close, volume)
SELECT security_id, DATE '2025-10-03', 101, 111, 91, 106, 2000
FROM securities WHERE ticker = 'TEST' AND mic_code = 'XNAS';
ROLLBACK TO s;


-- corporate_actions

-- split with a cash amount
SAVEPOINT s;
INSERT INTO corporate_actions (security_id, ex_date, action_type, ratio, amount)
SELECT security_id, DATE '2025-10-03', 'split', 4, 0.24
FROM securities WHERE ticker = 'TEST' AND mic_code = 'XNAS';
ROLLBACK TO s;

-- dividend with a split ratio
SAVEPOINT s;
INSERT INTO corporate_actions (security_id, ex_date, action_type, ratio, amount)
SELECT security_id, DATE '2025-10-03', 'dividend', 4, 0.24
FROM securities WHERE ticker = 'TEST' AND mic_code = 'XNAS';
ROLLBACK TO s;

-- unknown action type
SAVEPOINT s;
INSERT INTO corporate_actions (security_id, ex_date, action_type, ratio)
SELECT security_id, DATE '2025-10-03', 'merger', 1
FROM securities WHERE ticker = 'TEST' AND mic_code = 'XNAS';
ROLLBACK TO s;

-- negative split ratio
SAVEPOINT s;
INSERT INTO corporate_actions (security_id, ex_date, action_type, ratio)
SELECT security_id, DATE '2025-10-03', 'split', -4
FROM securities WHERE ticker = 'TEST' AND mic_code = 'XNAS';
ROLLBACK TO s;

-- valid
SAVEPOINT s;
INSERT INTO corporate_actions (security_id, ex_date, action_type, ratio)
SELECT security_id, DATE '2025-10-03', 'split', 4
FROM securities WHERE ticker = 'TEST' AND mic_code = 'XNAS';
ROLLBACK TO s;


-- fx_rates

-- base and quote are the same currency
SAVEPOINT s;
INSERT INTO fx_rates (base_currency, quote_currency, rate_date, rate)
VALUES ('USD', 'USD', DATE '2025-10-03', 1);
ROLLBACK TO s;

-- negative rate
SAVEPOINT s;
INSERT INTO fx_rates (base_currency, quote_currency, rate_date, rate)
VALUES ('EUR', 'USD', DATE '2025-10-03', -1.08);
ROLLBACK TO s;

-- valid
SAVEPOINT s;
INSERT INTO fx_rates (base_currency, quote_currency, rate_date, rate)
VALUES ('EUR', 'USD', DATE '2025-10-03', 1.08);
ROLLBACK TO s;



-- txn_types


-- cash_sign outside {-1, 0, 1}
SAVEPOINT s;
INSERT INTO txn_types (code, description, cash_sign, affects_position)
VALUES ('bogus', 'Bad sign', 2, false);
ROLLBACK TO s;



-- transactions


-- buy with no price
SAVEPOINT s;
INSERT INTO transactions (txn_type, trade_date, account_id, security_id, quantity)
SELECT 'buy', DATE '2025-10-03', a.account_id, s.security_id, 100
FROM accounts a, securities s
WHERE a.name = 'Test Account' AND s.ticker = 'TEST' AND s.mic_code = 'XNAS';
ROLLBACK TO s;

-- buy carrying an amount
SAVEPOINT s;
INSERT INTO transactions (txn_type, trade_date, account_id, security_id, quantity, price, amount)
SELECT 'buy', DATE '2025-10-03', a.account_id, s.security_id, 100, 120.50, 12050
FROM accounts a, securities s
WHERE a.name = 'Test Account' AND s.ticker = 'TEST' AND s.mic_code = 'XNAS';
ROLLBACK TO s;

-- deposit referencing a security
SAVEPOINT s;
INSERT INTO transactions (txn_type, trade_date, account_id, security_id, amount)
SELECT 'deposit', DATE '2025-10-03', a.account_id, s.security_id, 5000
FROM accounts a, securities s
WHERE a.name = 'Test Account' AND s.ticker = 'TEST' AND s.mic_code = 'XNAS';
ROLLBACK TO s;

-- dividend with a quantity
SAVEPOINT s;
INSERT INTO transactions (txn_type, trade_date, account_id, security_id, quantity, amount)
SELECT 'dividend', DATE '2025-10-03', a.account_id, s.security_id, 100, 24
FROM accounts a, securities s
WHERE a.name = 'Test Account' AND s.ticker = 'TEST' AND s.mic_code = 'XNAS';
ROLLBACK TO s;

-- unknown transaction type
SAVEPOINT s;
INSERT INTO transactions (txn_type, trade_date, account_id, amount)
SELECT 'gift', DATE '2025-10-03', account_id, 100 FROM accounts WHERE name = 'Test Account';
ROLLBACK TO s;

-- transaction on an account that does not exist
SAVEPOINT s;
INSERT INTO transactions (txn_type, trade_date, account_id, amount)
VALUES ('deposit', DATE '2025-10-03', 99999, 5000);
ROLLBACK TO s;

-- valid
SAVEPOINT s;
INSERT INTO transactions (txn_type, trade_date, account_id, security_id, quantity, price)
SELECT 'buy', DATE '2025-10-03', a.account_id, s.security_id, 100, 120.50
FROM accounts a, securities s
WHERE a.name = 'Test Account' AND s.ticker = 'TEST' AND s.mic_code = 'XNAS';
ROLLBACK TO s;

-- valid
SAVEPOINT s;
INSERT INTO transactions (txn_type, trade_date, account_id, amount)
SELECT 'deposit', DATE '2025-10-03', account_id, 5000 FROM accounts WHERE name = 'Test Account';
ROLLBACK TO s;


ROLLBACK;

SELECT count(*) AS leftover_test_securities FROM securities WHERE ticker = 'TEST';
SELECT count(*) AS leftover_test_accounts   FROM accounts   WHERE name   = 'Test Account';
