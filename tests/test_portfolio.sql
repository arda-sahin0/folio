SELECT pg_temp.eq('transactions booked', (SELECT count(*) FROM transactions), 52);

SELECT pg_temp.eq('portfolio rejects', (SELECT count(*) FROM staging.rejects WHERE loader = '006_portfolio'), 0);

SELECT pg_temp.eq('open positions',
                  (SELECT string_agg(ticker || '=' || qty, ', ' ORDER BY ticker)
                   FROM (SELECT s.ticker,
                                sum(-tt.cash_sign * t.quantity)::int AS qty
                         FROM transactions t
                         JOIN txn_types tt ON tt.code = t.txn_type
                         JOIN securities s USING (security_id)
                         WHERE tt.affects_position
                         GROUP BY s.ticker) p),
                  'AAPL=10, BMW=50, MSFT=30, SAP=100');

SELECT pg_temp.eq('dividends booked',
                  (SELECT count(*) FROM transactions WHERE txn_type = 'dividend'), 38);
