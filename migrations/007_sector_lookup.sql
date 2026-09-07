CREATE TABLE sectors
(
    name text PRIMARY KEY
);

INSERT INTO sectors (name)
VALUES ('Energy'),
       ('Materials'),
       ('Industrials'),
       ('Consumer Discretionary'),
       ('Consumer Staples'),
       ('Health Care'),
       ('Financials'),
       ('Information Technology'),
       ('Communication Services'),
       ('Utilities'),
       ('Real Estate');

ALTER TABLE securities
    ADD CONSTRAINT securities_sector_fk
        FOREIGN KEY (sector) REFERENCES sectors (name);

