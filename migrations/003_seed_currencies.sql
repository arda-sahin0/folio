DROP TABLE IF EXISTS staging.raw_currencies;
CREATE TABLE staging.raw_currencies(
   entity               text,
   currency             text,
   alphabetic_code       text,
   numeric_code          text,
   minor_unit            text,
   withdrawal_date       text
);

COPY staging.raw_currencies FROM '/data/currencies.csv' WITH (FORMAT csv, HEADER true);
INSERT INTO currencies (code) SELECT DISTINCT alphabetic_code FROM staging.raw_currencies WHERE alphabetic_code ~ '^[A-Z]{3}$' AND coalesce(withdrawal_date, '') = '';