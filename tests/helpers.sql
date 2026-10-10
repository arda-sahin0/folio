CREATE FUNCTION pg_temp.eq(label text, actual anycompatible, expected anycompatible)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF actual IS DISTINCT FROM expected THEN
        RAISE EXCEPTION 'FAILED: % (expected %, got %)', label, expected, actual;
    END IF;
END $$;

CREATE FUNCTION pg_temp.must_fail(label text, stmt text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE stmt;
    EXCEPTION
        WHEN integrity_constraint_violation OR data_exception
            OR SQLSTATE '428C9' THEN
            RETURN;
    END;
    RAISE EXCEPTION 'FAILED: constraint not enforced: %', label;
END $$;

CREATE FUNCTION pg_temp.must_pass(label text, stmt text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE stmt;
    RAISE EXCEPTION USING ERRCODE = 'P0999';
EXCEPTION
    WHEN SQLSTATE 'P0999' THEN
        RETURN;
    WHEN OTHERS THEN
        RAISE EXCEPTION 'FAILED: valid statement rejected: % (%)', label, SQLERRM;
END $$;

CREATE FUNCTION pg_temp.must_raise(label text, stmt text, message text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE stmt;
    EXCEPTION
        WHEN raise_exception THEN
            IF SQLERRM NOT LIKE '%' || message || '%' THEN
                RAISE EXCEPTION 'FAILED: % raised "%" instead of "%"', label, SQLERRM, message;
            END IF;
            RETURN;
    END;
    RAISE EXCEPTION 'FAILED: no error raised: %', label;
END $$;
