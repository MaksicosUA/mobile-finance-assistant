-- The login the API and the projector run as (ADR 0024).
--
-- The account POSTGRES_USER names is a superuser, because the image makes it one.
-- Migrations need that. Serving requests does not, and a superuser connection
-- turns any future mistake in a query into the whole server. This login can read
-- and write rows and nothing else: no schema changes, no roles, no files.
--
-- Applied by app-role.sh, which puts `\set app_password '...'` ahead of this file
-- on standard input, so the password never appears in a process list. Safe to run
-- again.

\set ON_ERROR_STOP on

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mfa_app') THEN
        CREATE ROLE mfa_app LOGIN;
    END IF;
END
$$;

ALTER ROLE mfa_app
    WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
ALTER ROLE mfa_app PASSWORD :'app_password';

DO $$
BEGIN
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO mfa_app', current_database());
END
$$;
GRANT USAGE ON SCHEMA public TO mfa_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO mfa_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO mfa_app;
REVOKE ALL ON public.alembic_version FROM mfa_app;
GRANT SELECT ON public.alembic_version TO mfa_app;

-- Tables a later migration creates are usable without running this again, or the
-- first request to touch one would answer 503 after an otherwise clean deploy.
DO $$
BEGIN
    EXECUTE format(
        'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public '
        'GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO mfa_app',
        current_user
    );
    EXECUTE format(
        'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public '
        'GRANT USAGE, SELECT ON SEQUENCES TO mfa_app',
        current_user
    );
END
$$;
