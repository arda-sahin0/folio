ALTER TABLE accounts
    ADD CONSTRAINT accounts_name_unique UNIQUE (name);

ALTER TABLE transactions
    ADD COLUMN external_ref text;

ALTER TABLE transactions
    ADD CONSTRAINT transactions_external_ref_unique UNIQUE (external_ref),
    ADD CONSTRAINT external_ref_present CHECK (external_ref <> '');
