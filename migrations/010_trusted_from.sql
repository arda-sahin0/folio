-- 010_trusted_from.sql
--
-- Some vendor history is not trustworthy. Yahoo's Xetra data for BMW and SAP
-- before 2004 contains hundreds of bars whose close lies outside that day's
-- high-low range, so we don't use those years at all.
--
-- trusted_from records, per security, the first date whose prices we accept.
-- NULL means "trust the whole history". The price loader rejects earlier bars
-- with reason 'before trusted_from', so they stay visible in staging.rejects
-- instead of silently disappearing.
--
-- Deliberately a separate column from listed_on: listed_on is a fact about the
-- company, trusted_from is a judgement about our data source.

ALTER TABLE securities ADD COLUMN trusted_from date;
