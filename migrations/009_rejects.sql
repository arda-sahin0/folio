CREATE TABLE staging.rejects (
    reject_id       bigint          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    rejected_at     timestamptz     NOT NULL DEFAULT now(),
    loader          text            NOT NULL,
    reason          text            NOT NULL,
    raw_row         jsonb           NOT NULL
);