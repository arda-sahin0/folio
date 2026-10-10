SELECT s.ticker FROM securities s
WHERE NOT EXISTS (SELECT 1 FROM daily_prices p WHERE p.security_id = s.security_id);

SELECT s.ticker FROM securities s
                         LEFT JOIN daily_prices p ON p.security_id = s.security_id
WHERE p.security_id IS NULL;

SELECT s.ticker FROM securities s
WHERE s.security_id NOT IN (SELECT p.security_id FROM daily_prices p);

SELECT 'returned' WHERE 3 NOT IN (1, 2, NULL);

BEGIN;
INSERT INTO securities (ticker, name, mic_code, currency, sector)
VALUES ('ZZZZ', 'Test Security', 'XETR', 'EUR', 'Industrials');
ROLLBACK;