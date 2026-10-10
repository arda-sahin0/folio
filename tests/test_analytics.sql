SELECT pg_temp.eq('EUR needs no rate', eur_rate('EUR', DATE '1990-01-01'), 1::numeric);
SELECT pg_temp.eq('weekend uses the Friday rate', eur_rate('USD', DATE '2020-08-30'), 1.1915::numeric);
SELECT pg_temp.eq('latest rate within a week', eur_rate('USD', DATE '2020-09-07'), 1.1969::numeric);
SELECT pg_temp.eq('rate a week old counts as missing', eur_rate('USD', DATE '2020-09-08'), NULL::numeric);

SELECT pg_temp.eq('whatif by shares, through two splits',
                  (SELECT (buy_date, buy_price, cost, split_factor, shares_now, value, dividends, profit, return_pct)::text
                   FROM whatif('AAPL', DATE '2014-06-01', p_shares => 10, p_end => DATE '2020-09-10')),
                  '(2014-06-06,651.000000,6510.00,28.000000,280.000000,32480.00,57.40,26027.40,399.81)');

SELECT pg_temp.eq('whatif without ECB rates has no EUR figures',
                  (SELECT (cost_eur, value_eur, return_eur_pct)::text
                   FROM whatif('aapl', DATE '2014-06-06', p_shares => 10, p_end => DATE '2020-09-08')),
                  '(,,)');

SELECT pg_temp.eq('whatif risk figures',
                  (SELECT (max_drawdown_pct, drawdown_peak, drawdown_trough, best_day, best_day_pct, worst_day, worst_day_pct)::text
                   FROM whatif('AAPL', DATE '2014-06-06', p_shares => 10)),
                  '(-13.43,2020-09-01,2020-09-08,2020-08-28,430.53,2020-09-08,-13.43)');

SELECT pg_temp.eq('whatif by EUR amount, converted at the ECB rate',
                  (SELECT (shares_bought, cost, cost_eur, shares_now, value, value_eur, profit_eur, return_eur_pct)::text
                   FROM whatif('AAPL', DATE '2020-08-28', p_amount => 1000, p_end => DATE '2020-09-01')),
                  '(2.364087,1191.50,1000.00,9.456348,1267.15,1058.69,58.69,5.87)');

SELECT pg_temp.eq('buying at the close of an ex-date gets no split',
                  (SELECT (split_factor, shares_now)::text
                   FROM whatif('AAPL', DATE '2020-08-31', p_shares => 1, p_end => DATE '2020-09-01')),
                  '(1.000000,1.000000)');

SELECT pg_temp.eq('whatif in the stock''s own currency needs no rate',
                  (SELECT shares_bought FROM whatif('SAP', DATE '2004-01-02', p_amount => 505)),
                  5.000000::numeric);

SELECT pg_temp.must_raise('unknown ticker', $$ SELECT * FROM whatif('ZZZZ', DATE '2020-01-01', p_shares => 1) $$, 'unknown ticker');
SELECT pg_temp.must_raise('neither shares nor amount', $$ SELECT * FROM whatif('AAPL', DATE '2020-01-01') $$, 'exactly one');
SELECT pg_temp.must_raise('shares and amount', $$ SELECT * FROM whatif('AAPL', DATE '2020-01-01', 1, 1) $$, 'exactly one');
SELECT pg_temp.must_raise('negative shares', $$ SELECT * FROM whatif('AAPL', DATE '2020-01-01', p_shares => -1) $$, 'positive');
SELECT pg_temp.must_raise('no prices after start', $$ SELECT * FROM whatif('AAPL', DATE '2030-01-01', p_shares => 1) $$, 'no AAPL prices');
SELECT pg_temp.must_raise('end before start', $$ SELECT * FROM whatif('AAPL', DATE '2020-09-01', p_shares => 1, p_end => DATE '2020-08-01') $$, 'after the buy date');
SELECT pg_temp.must_raise('amount with no ECB rate', $$ SELECT * FROM whatif('AAPL', DATE '2014-06-06', p_amount => 100) $$, 'no ECB rate');
SELECT pg_temp.must_raise('unknown account', $$ SELECT * FROM portfolio_summary('Nobody', DATE '2020-01-01') $$, 'unknown account');

BEGIN;

INSERT INTO accounts (name, base_currency, opening_date) VALUES ('Test EUR', 'EUR', DATE '2004-01-02');
INSERT INTO transactions (account_id, txn_type, trade_date, security_id, quantity, price, amount)
SELECT a.account_id, v.txn_type, v.d, s.security_id, v.q, v.p, v.amt
FROM accounts a
CROSS JOIN (VALUES ('deposit',  DATE '2004-01-02', NULL, NULL::numeric, NULL::numeric, 1000::numeric),
                   ('buy',      DATE '2004-01-02', 'SAP', 5, 101, NULL),
                   ('dividend', DATE '2004-01-05', 'SAP', NULL, NULL, 10),
                   ('fee',      DATE '2004-01-05', NULL, NULL, NULL, 5)) v(txn_type, d, ticker, q, p, amt)
LEFT JOIN securities s ON s.ticker = v.ticker
WHERE a.name = 'Test EUR';

SELECT pg_temp.eq('EUR position',
                  (SELECT (ticker, shares, price, value_eur, weight_pct, bought_eur, dividends_eur, profit_eur)::text
                   FROM portfolio_positions('Test EUR', DATE '2004-01-05')),
                  '(SAP,5.000000,102.000000,510.00,100.00,505.00,10.00,15.00)');

SELECT pg_temp.eq('EUR summary',
                  (SELECT (deposits_eur, fees_eur, net_invested_eur, cash_eur, holdings_eur, total_value_eur, profit_eur, return_pct)::text
                   FROM portfolio_summary('Test EUR', DATE '2004-01-05')),
                  '(1000.00,5.00,1000.00,500.00,510.00,1010.00,10.00,1.00)');

SELECT pg_temp.eq('nothing booked before the first transaction',
                  (SELECT (cash_eur, holdings_eur, profit_eur)::text FROM portfolio_summary('Test EUR', DATE '2003-12-31')),
                  '(0.00,0.00,0.00)');

INSERT INTO accounts (name, base_currency, opening_date) VALUES ('Test USD', 'EUR', DATE '2020-08-28');
INSERT INTO transactions (account_id, txn_type, trade_date, security_id, quantity, price, amount)
SELECT a.account_id, v.txn_type, DATE '2020-08-28', s.security_id, v.q, v.p, v.amt
FROM accounts a
CROSS JOIN (VALUES ('deposit', NULL, NULL::numeric, NULL::numeric, 1000::numeric),
                   ('buy',     'AAPL', 2, 504, NULL)) v(txn_type, ticker, q, p, amt)
LEFT JOIN securities s ON s.ticker = v.ticker
WHERE a.name = 'Test USD';

SELECT pg_temp.eq('USD position after a 4:1 split',
                  (SELECT (shares, price, value, value_eur, bought_eur, profit_eur)::text
                   FROM portfolio_positions('Test USD', DATE '2020-09-01')),
                  '(8.000000,134.000000,1072.00,895.65,845.99,49.65)');

SELECT pg_temp.eq('USD summary: cash + holdings = total, as displayed',
                  (SELECT (cash_eur, holdings_eur, total_value_eur, profit_eur, return_pct)::text
                   FROM portfolio_summary('Test USD', DATE '2020-09-01')),
                  '(154.01,895.65,1049.66,49.66,4.97)');

SELECT pg_temp.eq('missing ECB rate makes the totals unknown, not wrong',
                  (SELECT holdings_eur IS NULL FROM portfolio_summary('Test USD', DATE '2020-09-08')),
                  true);

SELECT pg_temp.eq('a cash flow without an ECB rate makes cash unknown, not wrong',
                  (SELECT (deposits_eur, cash_eur, dividends_eur, profit_eur)::text FROM portfolio_summary('Main', DATE '2024-12-31')),
                  '(40000.00,,,)');

SELECT pg_temp.eq('positions without ECB rates have unknown EUR flows',
                  (SELECT (shares, bought_eur, profit_eur)::text FROM portfolio_positions('Main', DATE '2024-12-31') WHERE ticker = 'AAPL'),
                  '(10.000000,,)');

ROLLBACK;
