ALTER TABLE fx_rates
    ADD CONSTRAINT fx_base_is_eur CHECK (base_currency = 'EUR');
