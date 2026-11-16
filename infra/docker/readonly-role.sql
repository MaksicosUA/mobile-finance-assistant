-- A login that can read the database and change nothing (ADR 0024).
--
-- Applied by readonly-role.sh, which puts `\set readonly_password '...'` ahead of
-- this file on standard input, so the password never appears in a process list.
-- Safe to run again. After a migration adds a column to users or
-- auth_refresh_tokens, run it again to make that column readable too.

\set ON_ERROR_STOP on

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mfa_readonly') THEN
        CREATE ROLE mfa_readonly LOGIN;
    END IF;
END
$$;

ALTER ROLE mfa_readonly
    WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
ALTER ROLE mfa_readonly PASSWORD :'readonly_password';
-- Belt and braces: anything that slipped past the grants below would still run
-- inside a read-only transaction.
ALTER ROLE mfa_readonly SET default_transaction_read_only = on;

DO $$
BEGIN
    EXECUTE format(
        'GRANT CONNECT ON DATABASE %I TO mfa_readonly', current_database()
    );
END
$$;
GRANT USAGE ON SCHEMA public TO mfa_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO mfa_readonly;

-- Three columns stay out of sight. A password hash, a recovery-code hash and a
-- refresh-token hash are nothing anyone needs to read, and they are what an
-- attacker would want. A table-level grant cannot leave a column out, so these
-- two tables are granted column by column instead.
REVOKE SELECT ON public.users, public.auth_refresh_tokens FROM mfa_readonly;
DO $$
DECLARE
    target text;
    hidden text[];
    present text;
    readable text;
BEGIN
    FOR target, hidden IN
        SELECT * FROM (
            VALUES
                ('users', ARRAY['password_hash', 'recovery_code_hash']),
                ('auth_refresh_tokens', ARRAY['token_hash'])
        ) AS pairs (target, hidden)
    LOOP
        -- A grant made before a column joined this list is taken back. Only
        -- columns that exist are named: this file also runs against a database
        -- that has not been migrated that far yet.
        SELECT string_agg(quote_ident(c.column_name), ', ' ORDER BY c.ordinal_position)
          INTO present
          FROM information_schema.columns AS c
         WHERE c.table_schema = 'public'
           AND c.table_name = target
           AND c.column_name = ANY (hidden);
        IF present IS NOT NULL THEN
            EXECUTE format(
                'REVOKE SELECT (%s) ON public.%I FROM mfa_readonly', present, target
            );
        END IF;
        SELECT string_agg(quote_ident(c.column_name), ', ' ORDER BY c.ordinal_position)
          INTO readable
          FROM information_schema.columns AS c
         WHERE c.table_schema = 'public'
           AND c.table_name = target
           AND c.column_name <> ALL (hidden);
        EXECUTE format('GRANT SELECT (%s) ON public.%I TO mfa_readonly', readable, target);
    END LOOP;
END
$$;

-- As a result `SELECT *` on these two tables is refused: name the columns. No
-- view is created to smooth that over. A view that depends on these columns would
-- stop a later migration from dropping or retyping one of them, and a migration
-- that fails keeps the API from starting.

-- Tables a later migration creates become readable without running this again.
DO $$
BEGIN
    EXECUTE format(
        'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public '
        'GRANT SELECT ON TABLES TO mfa_readonly',
        current_user
    );
END
$$;
