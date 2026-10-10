BEGIN;

INSERT INTO securities (ticker, name, mic_code, currency, sector)
VALUES ('TEST', 'Test Corporation', 'XNAS', 'USD', 'Information Technology');

INSERT INTO accounts (name, base_currency, opening_date)
VALUES ('Test Account', 'EUR', DATE '2020-01-01');


SELECT pg_temp.must_fail('lowercase currency code', $$
    INSERT INTO currencies (code) VALUES ('usd') $$);

SELECT pg_temp.must_fail('two-letter currency code', $$
    INSERT INTO currencies (code) VALUES ('US') $$);

SELECT pg_temp.must_fail('duplicate currency', $$
    INSERT INTO currencies (code) VALUES ('USD') $$);


SELECT pg_temp.must_fail('five-character MIC', $$
    INSERT INTO exchanges (mic_code, name, country, timezone, currency)
    VALUES ('XNASD', 'Too Long', 'US', 'America/New_York', 'USD') $$);

SELECT pg_temp.must_fail('three-letter country code', $$
    INSERT INTO exchanges (mic_code, name, country, timezone, currency)
    VALUES ('XTST', 'Bad Country', 'USA', 'America/New_York', 'USD') $$);

SELECT pg_temp.must_fail('exchange currency not in currencies', $$
    INSERT INTO exchanges (mic_code, name, country, timezone, currency)
    VALUES ('XTST', 'Bad Currency', 'US', 'America/New_York', 'ZZZ') $$);

SELECT pg_temp.must_pass('valid exchange', $$
    INSERT INTO exchanges (mic_code, name, country, timezone, currency)
    VALUES ('XTST', 'Test Exchange', 'US', 'America/New_York', 'USD') $$);


SELECT pg_temp.must_fail('empty ticker', $$
    INSERT INTO securities (ticker, name, mic_code, currency)
    VALUES ('', 'Empty Ticker', 'XNAS', 'USD') $$);

SELECT pg_temp.must_fail('exchange does not exist', $$
    INSERT INTO securities (ticker, name, mic_code, currency)
    VALUES ('GHOST', 'Ghost Corp', 'ZZZZ', 'USD') $$);

SELECT pg_temp.must_fail('same ticker twice on one exchange', $$
    INSERT INTO securities (ticker, name, mic_code, currency)
    VALUES ('TEST', 'Duplicate', 'XNAS', 'USD') $$);

SELECT pg_temp.must_pass('same ticker on another exchange', $$
    INSERT INTO securities (ticker, name, mic_code, currency)
    VALUES ('TEST', 'Test Corporation', 'XETR', 'EUR') $$);

SELECT pg_temp.must_fail('unknown sector', $$
    INSERT INTO securities (ticker, name, mic_code, currency, sector)
    VALUES ('SECT', 'Bad Sector', 'XNAS', 'USD', 'Technology') $$);

SELECT pg_temp.must_fail('delisted before listed', $$
    INSERT INTO securities (ticker, name, mic_code, currency, listed_on, delisted_on)
    VALUES ('DEAD', 'Dead Corp', 'XNAS', 'USD', DATE '2020-01-01', DATE '2019-01-01') $$);

SELECT pg_temp.must_fail('explicit value for a GENERATED ALWAYS id', $$
    INSERT INTO securities (security_id, ticker, name, mic_code, currency)
    VALUES (999, 'FORCE', 'Forced Id', 'XNAS', 'USD') $$);


SELECT pg_temp.must_fail('high is not the highest', $$
    INSERT INTO daily_prices (security_id, trade_date, open, high, low, close, volume)
    SELECT security_id, DATE '2025-10-03', 300, 200, 100, 150, 1000
    FROM securities WHERE ticker = 'TEST' AND mic_code = 'XNAS' $$);

SELECT pg_temp.must_fail('low is not the lowest', $$
    INSERT INTO daily_prices (security_id, trade_date, open, high, low, close, volume)
    SELECT security_id, DATE '2025-10-03', 100, 300, 200, 150, 1000
    FROM securities WHERE ticker = 'TEST' AND mic_code = 'XNAS' $$);

SELECT pg_temp.must_fail('negative volume', $$
    INSERT INTO daily_prices (security_id, trade_date, open, high, low, close, volume)
    SELECT security_id, DATE '2025-10-03', 100, 110, 90, 105, -1
    FROM securities WHERE ticker = 'TEST' AND mic_code = 'XNAS' $$);

SELECT pg_temp.must_fail('zero price', $$
    INSERT INTO daily_prices (security_id, trade_date, open, high, low, close, volume)
    SELECT security_id, DATE '2025-10-03', 0, 110, 0, 105, 1000
    FROM securities WHERE ticker = 'TEST' AND mic_code = 'XNAS' $$);

SELECT pg_temp.must_fail('price for a security that does not exist', $$
    INSERT INTO daily_prices (security_id, trade_date, open, high, low, close, volume)
    VALUES (999999, DATE '2025-10-03', 100, 110, 90, 105, 1000) $$);

SELECT pg_temp.must_fail('two bars for the same security and day', $$
    INSERT INTO daily_prices (security_id, trade_date, open, high, low, close, volume)
    SELECT security_id, d, 100, 110, 90, 105, 1000
    FROM securities, (VALUES (DATE '2025-10-03'), (DATE '2025-10-03')) v(d)
    WHERE ticker = 'TEST' AND mic_code = 'XNAS' $$);


SELECT pg_temp.must_fail('split with a cash amount', $$
    INSERT INTO corporate_actions (security_id, ex_date, action_type, ratio, amount)
    SELECT security_id, DATE '2025-10-03', 'split', 4, 0.24
    FROM securities WHERE ticker = 'TEST' AND mic_code = 'XNAS' $$);

SELECT pg_temp.must_fail('dividend with a split ratio', $$
    INSERT INTO corporate_actions (security_id, ex_date, action_type, ratio, amount)
    SELECT security_id, DATE '2025-10-03', 'dividend', 4, 0.24
    FROM securities WHERE ticker = 'TEST' AND mic_code = 'XNAS' $$);

SELECT pg_temp.must_fail('unknown action type', $$
    INSERT INTO corporate_actions (security_id, ex_date, action_type, ratio)
    SELECT security_id, DATE '2025-10-03', 'merger', 1
    FROM securities WHERE ticker = 'TEST' AND mic_code = 'XNAS' $$);

SELECT pg_temp.must_fail('negative split ratio', $$
    INSERT INTO corporate_actions (security_id, ex_date, action_type, ratio)
    SELECT security_id, DATE '2025-10-03', 'split', -4
    FROM securities WHERE ticker = 'TEST' AND mic_code = 'XNAS' $$);

SELECT pg_temp.must_pass('valid split', $$
    INSERT INTO corporate_actions (security_id, ex_date, action_type, ratio)
    SELECT security_id, DATE '2025-10-03', 'split', 4
    FROM securities WHERE ticker = 'TEST' AND mic_code = 'XNAS' $$);


SELECT pg_temp.must_fail('rate between a currency and itself', $$
    INSERT INTO fx_rates (base_currency, quote_currency, rate_date, rate)
    VALUES ('USD', 'USD', DATE '2025-10-03', 1) $$);

SELECT pg_temp.must_fail('base currency other than EUR', $$
    INSERT INTO fx_rates (base_currency, quote_currency, rate_date, rate)
    VALUES ('USD', 'JPY', DATE '2025-10-03', 150) $$);

SELECT pg_temp.must_fail('negative rate', $$
    INSERT INTO fx_rates (base_currency, quote_currency, rate_date, rate)
    VALUES ('EUR', 'USD', DATE '2025-10-03', -1.08) $$);

SELECT pg_temp.must_pass('valid rate', $$
    INSERT INTO fx_rates (base_currency, quote_currency, rate_date, rate)
    VALUES ('EUR', 'USD', DATE '2030-10-03', 1.08) $$);


SELECT pg_temp.must_fail('cash_sign outside -1, 0, 1', $$
    INSERT INTO txn_types (code, description, cash_sign, affects_position)
    VALUES ('bogus', 'Bad sign', 2, false) $$);


SELECT pg_temp.must_fail('buy with no price', $$
    INSERT INTO transactions (txn_type, trade_date, account_id, security_id, quantity)
    SELECT 'buy', DATE '2025-10-03', a.account_id, s.security_id, 100
    FROM accounts a, securities s
    WHERE a.name = 'Test Account' AND s.ticker = 'TEST' AND s.mic_code = 'XNAS' $$);

SELECT pg_temp.must_fail('buy carrying an amount', $$
    INSERT INTO transactions (txn_type, trade_date, account_id, security_id, quantity, price, amount)
    SELECT 'buy', DATE '2025-10-03', a.account_id, s.security_id, 100, 120.50, 12050
    FROM accounts a, securities s
    WHERE a.name = 'Test Account' AND s.ticker = 'TEST' AND s.mic_code = 'XNAS' $$);

SELECT pg_temp.must_fail('sell with a negative quantity', $$
    INSERT INTO transactions (txn_type, trade_date, account_id, security_id, quantity, price)
    SELECT 'sell', DATE '2025-10-03', a.account_id, s.security_id, -100, 120.50
    FROM accounts a, securities s
    WHERE a.name = 'Test Account' AND s.ticker = 'TEST' AND s.mic_code = 'XNAS' $$);

SELECT pg_temp.must_fail('deposit referencing a security', $$
    INSERT INTO transactions (txn_type, trade_date, account_id, security_id, amount)
    SELECT 'deposit', DATE '2025-10-03', a.account_id, s.security_id, 5000
    FROM accounts a, securities s
    WHERE a.name = 'Test Account' AND s.ticker = 'TEST' AND s.mic_code = 'XNAS' $$);

SELECT pg_temp.must_fail('dividend with a quantity', $$
    INSERT INTO transactions (txn_type, trade_date, account_id, security_id, quantity, amount)
    SELECT 'dividend', DATE '2025-10-03', a.account_id, s.security_id, 100, 24
    FROM accounts a, securities s
    WHERE a.name = 'Test Account' AND s.ticker = 'TEST' AND s.mic_code = 'XNAS' $$);

SELECT pg_temp.must_fail('unknown transaction type', $$
    INSERT INTO transactions (txn_type, trade_date, account_id, amount)
    SELECT 'gift', DATE '2025-10-03', account_id, 100 FROM accounts WHERE name = 'Test Account' $$);

SELECT pg_temp.must_fail('account that does not exist', $$
    INSERT INTO transactions (txn_type, trade_date, account_id, amount)
    VALUES ('deposit', DATE '2025-10-03', 99999, 5000) $$);

SELECT pg_temp.must_fail('empty external_ref', $$
    INSERT INTO transactions (txn_type, trade_date, account_id, amount, external_ref)
    SELECT 'deposit', DATE '2025-10-03', account_id, 5000, '' FROM accounts WHERE name = 'Test Account' $$);

SELECT pg_temp.must_pass('valid buy', $$
    INSERT INTO transactions (txn_type, trade_date, account_id, security_id, quantity, price)
    SELECT 'buy', DATE '2025-10-03', a.account_id, s.security_id, 100, 120.50
    FROM accounts a, securities s
    WHERE a.name = 'Test Account' AND s.ticker = 'TEST' AND s.mic_code = 'XNAS' $$);

SELECT pg_temp.must_pass('valid deposit', $$
    INSERT INTO transactions (txn_type, trade_date, account_id, amount)
    SELECT 'deposit', DATE '2025-10-03', account_id, 5000 FROM accounts WHERE name = 'Test Account' $$);

ROLLBACK;

SELECT pg_temp.eq('no test rows left behind',
                  (SELECT count(*) FROM securities WHERE ticker = 'TEST')
                + (SELECT count(*) FROM accounts WHERE name = 'Test Account'), 0::bigint);
