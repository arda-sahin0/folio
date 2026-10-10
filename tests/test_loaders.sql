-- Checks the loaders against tests/fixtures, whose rows each exercise one rule.

SELECT pg_temp.eq('price bars loaded', (SELECT count(*) FROM daily_prices), 10);

SELECT pg_temp.eq('staged price rows = loaded + rejected',
                  (SELECT count(*) FROM daily_prices)
                + (SELECT count(*) FROM staging.rejects WHERE loader = '003_prices'), 16);

SELECT pg_temp.eq('price reject: ' || reason, count(*), 1)
FROM staging.rejects
WHERE loader = '003_prices'
GROUP BY reason;

SELECT pg_temp.eq('price reject reasons',
                  (SELECT string_agg(DISTINCT reason, ', ' ORDER BY reason)
                   FROM staging.rejects WHERE loader = '003_prices'),
                  'bad date, bad open, before trusted_from, no symbol mapping, ohlc inconsistent, placeholder bar (no trading)');

SELECT pg_temp.eq('bar before two splits is multiplied by 28',
                  (SELECT (open, high, low, close, volume)::text FROM daily_prices p
                   JOIN securities s USING (security_id)
                   WHERE s.ticker = 'AAPL' AND p.trade_date = '2014-06-06'),
                  '(644.000000,658.000000,630.000000,651.000000,100000)');

SELECT pg_temp.eq('bar on an ex-date carries only the later splits',
                  (SELECT (close, volume)::text FROM daily_prices p
                   JOIN securities s USING (security_id)
                   WHERE s.ticker = 'AAPL' AND p.trade_date = '2014-06-09'),
                  '(95.000000,500000)');

SELECT pg_temp.eq('bar after the last split is unchanged',
                  (SELECT close FROM daily_prices p
                   JOIN securities s USING (security_id)
                   WHERE s.ticker = 'AAPL' AND p.trade_date = '2020-08-31'),
                  129::numeric);

SELECT pg_temp.eq('zero volume on a day that moved is stored as unknown',
                  (SELECT volume FROM daily_prices p
                   JOIN securities s USING (security_id)
                   WHERE s.ticker = 'AAPL' AND p.trade_date = '2020-09-08'),
                  NULL::bigint);

SELECT pg_temp.eq('splits loaded',
                  (SELECT count(*) FROM corporate_actions WHERE action_type = 'split'), 2);

SELECT pg_temp.eq('dividend de-adjusted by later splits',
                  (SELECT amount FROM corporate_actions ca
                   JOIN securities s USING (security_id)
                   WHERE s.ticker = 'AAPL' AND ca.ex_date = '2012-08-09'),
                  2.65::numeric);

SELECT pg_temp.eq('dividends loaded',
                  (SELECT count(*) FROM corporate_actions WHERE action_type = 'dividend'), 4);

SELECT pg_temp.eq('corporate action rejects',
                  (SELECT string_agg(reason, ', ' ORDER BY reason)
                   FROM staging.rejects WHERE loader = '002_corporate_actions'),
                  'bad amount, bad date, bad ratio, no symbol mapping');

SELECT pg_temp.eq('sessions per exchange',
                  (SELECT string_agg(mic_code || '=' || n, ', ' ORDER BY mic_code)
                   FROM (SELECT mic_code, count(*) AS n FROM trading_calendar GROUP BY mic_code) c),
                  'XETR=2, XNAS=8');

SELECT pg_temp.eq('fx rates loaded', (SELECT count(*) FROM fx_rates), 5);

SELECT pg_temp.eq('fx rejects',
                  (SELECT string_agg(reason, ', ' ORDER BY reason)
                   FROM staging.rejects WHERE loader = '005_fx_rates'),
                  'bad currency code, bad date, bad rate, quote equals base, unknown currency');
