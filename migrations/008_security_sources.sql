CREATE TABLE IF NOT EXISTS security_sources
(
    security_id integer NOT NULL,
    source      text    NOT NULL,
    symbol      text    NOT NULL,

    FOREIGN KEY (security_id) REFERENCES securities (security_id),
    PRIMARY KEY (security_id, source),
    UNIQUE (source, symbol),
    CONSTRAINT symbol_format CHECK (symbol <> ''),
    CONSTRAINT source_known CHECK (source = 'yfinance')
);