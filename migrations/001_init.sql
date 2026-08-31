CREATE SCHEMA IF NOT EXISTS staging;
CREATE TABLE IF NOT EXISTS schema_migrations(
    filename text,
    applied_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (filename)
);