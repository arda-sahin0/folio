INSERT INTO exchanges (mic_code, name, country, timezone, currency) VALUES
('XNYS', 'New York Stock Exchange', 'US', 'America/New_York', 'USD'),
('XNAS', 'Nasdaq Stock Market',     'US', 'America/New_York', 'USD'),
('XETR', 'Deutsche Boerse Xetra',   'DE', 'Europe/Berlin',    'EUR'),
('XLON', 'London Stock Exchange',   'GB', 'Europe/London',    'GBP'),
('XTKS', 'Tokyo Stock Exchange',    'JP', 'Asia/Tokyo',       'JPY'),
('XIST', 'Borsa Istanbul',          'TR', 'Europe/Istanbul',  'TRY')
ON CONFLICT (mic_code) DO UPDATE SET
name = excluded.name,
country = excluded.country,
timezone = excluded.timezone,
currency = excluded.currency
