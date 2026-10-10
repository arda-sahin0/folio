-- Fingerprints every loaded table, so test_idempotency.sql can prove a second load changed nothing.

CREATE SCHEMA IF NOT EXISTS ci;

CREATE OR REPLACE VIEW ci.fingerprint AS
SELECT 'securities' AS tbl, md5(string_agg(t::text, '|' ORDER BY t::text)) AS hash FROM securities t
UNION ALL SELECT 'security_sources', md5(string_agg(t::text, '|' ORDER BY t::text)) FROM security_sources t
UNION ALL SELECT 'corporate_actions', md5(string_agg(t::text, '|' ORDER BY t::text)) FROM corporate_actions t
UNION ALL SELECT 'daily_prices', md5(string_agg(t::text, '|' ORDER BY t::text)) FROM daily_prices t
UNION ALL SELECT 'trading_calendar', md5(string_agg(t::text, '|' ORDER BY t::text)) FROM trading_calendar t
UNION ALL SELECT 'fx_rates', md5(string_agg(t::text, '|' ORDER BY t::text)) FROM fx_rates t
UNION ALL SELECT 'accounts', md5(string_agg(t::text, '|' ORDER BY t::text)) FROM accounts t
UNION ALL SELECT 'transactions', md5(string_agg(t::text, '|' ORDER BY t::text)) FROM transactions t
UNION ALL SELECT 'rejects', md5(string_agg(t::text, '|' ORDER BY t::text))
          FROM (SELECT loader, reason, raw_row FROM staging.rejects) t;

DROP TABLE IF EXISTS ci.snapshot;
CREATE TABLE ci.snapshot AS SELECT * FROM ci.fingerprint;
