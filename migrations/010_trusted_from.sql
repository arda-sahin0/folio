-- First date whose vendor prices are trusted; earlier bars are rejected by the price loader.

ALTER TABLE securities ADD COLUMN trusted_from date;
