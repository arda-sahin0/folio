-- Loading the same files twice must leave every table exactly as it was after the first load.

SELECT pg_temp.eq('table unchanged by second load: ' || s.tbl, f.hash, s.hash)
FROM ci.snapshot s
JOIN ci.fingerprint f USING (tbl);

SELECT pg_temp.eq('fingerprinted tables', (SELECT count(*) FROM ci.snapshot), 9);
