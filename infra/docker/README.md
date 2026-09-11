# Deploying the backend

The API, the projector, PostgreSQL, and automatic TLS, as four containers on
one host. Everything except Caddy stays on the internal network: a financial
database that listens on a public port is one firewall mistake away from being
read.

## What the host needs

Docker with the compose plugin, a DNS record pointing at it, and a data
directory. The database lives outside the container so that recreating the
stack never touches it.

## Configuration

Copy `env.example` to `.env` beside `compose.yaml` on the host, fill it in, and
keep it readable only by its owner:

    chmod 600 .env

`.env` is never committed. Secrets belong to the deployment, not the
repository.

## Running it

    docker compose --env-file .env up -d --build

Migrations run as a one-shot before the API starts, so the schema is part of
the deployment rather than something the first request discovers missing.

### After changing the Caddyfile

`up -d --build` is not enough. The Caddyfile is bind-mounted as a single file,
and uploading a new copy with `rsync` — or saving it from most editors —
replaces the file with a new inode. A single-file bind mount stays attached to
the old one, so the running Caddy keeps reading the previous configuration, and
compose does not recreate the container because its service definition did not
change. Even `caddy reload` re-reads the stale copy. Recreate it:

    docker compose --env-file .env up -d --force-recreate --no-deps caddy

Then check the file *inside* the container, not on the host — validating a
configuration is not the same as running it:

    docker compose exec -T caddy cat /etc/caddy/Caddyfile

Certificates live in `$MFA_DATA_ROOT/caddy/data`, so recreating the container
costs a few seconds and no reissue. This is how the download-link route was
logged for twenty minutes on its first deploy (ADR 0026).

## Backups

Provider snapshots capture a disk, which is not the same as a database: a
snapshot taken mid-write restores a file tree PostgreSQL then has to repair,
and nothing tells you in advance whether it can.

`backup.sh` takes a logical dump in custom format, refuses to keep a
suspiciously small one, and only then ages out anything older than
`MFA_BACKUP_KEEP_DAYS` — so a run of failures can never delete the last working
copy. Install the schedule once:

    sudo cp mfa-backup.service mfa-backup.timer /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable --now mfa-backup.timer

Failures surface in `systemctl status mfa-backup` and the journal rather than
in a mailbox nobody reads.

### Proving a backup restores

A backup nobody restored is a hope. Restore the newest one into a scratch
database and compare it with the live one, then drop the scratch:

    docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres \
      -c "CREATE DATABASE mfa_restore_check;"
    cat <newest>.dump | docker compose exec -T postgres \
      pg_restore -U "$POSTGRES_USER" -d mfa_restore_check --no-owner --no-privileges
    # compare counts of users, finance_operations, finance_categories, ...
    docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres \
      -c "DROP DATABASE mfa_restore_check;"
