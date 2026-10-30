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

### Updating the host

The tree on the host is a copy, not a clone. Take a dump first, then send
everything the image and the stack are built from. `.env` is excluded by name:
it exists only on the host and an upload must never touch it.

    ./backup.sh
    rsync -a --relative --exclude '__pycache__' --exclude '.env*' \
      .dockerignore services/api/pyproject.toml services/api/uv.lock \
      services/api/alembic.ini services/api/src services/api/migrations \
      infra/docker <user>@<host>:/tmp/mfa-sync/
    ssh <user>@<host> 'sudo rsync -a /tmp/mfa-sync/ /opt/mfa/ && rm -rf /tmp/mfa-sync'
    docker compose --env-file .env up -d --build

The Dockerfile reads `uv.lock`, so an upload without it builds the previous set
of dependencies, or fails.

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

## Looking at the database

The database publishes no port, and it stays that way: everything below goes
through SSH.

Once, and again after a migration adds a column to `users` or
`auth_refresh_tokens`:

    sudo ./readonly-role.sh

It creates `mfa_readonly`, which can read every table except the password hash
and the refresh-token hash, runs every statement in a read-only transaction, and
can therefore change nothing. Its password is generated into `.env` and never
printed.

When you want to look:

    sudo ./adminer.sh start        # on the host; stops itself after two hours
    ssh -N -L 8080:127.0.0.1:8080 <user>@<host>    # on your computer

Open http://localhost:8080 and sign in with System **PostgreSQL**, Server
**postgres**, Username **mfa_readonly**, Database the `POSTGRES_DB` value, and the
password from `sudo grep ^MFA_READONLY_DB_PASSWORD= .env`. `sudo ./adminer.sh stop`
when done.

`users` and `auth_refresh_tokens` refuse `SELECT *`, because two of their columns
are hidden: in Adminer, choose the columns under **Select** before opening them.
For accounts, `account_admin list` is quicker anyway.

**Do not edit financial rows by hand, even with a stronger login.** A write that
skips Finance Core skips its audit row and its outbox invalidation, can break
the append-only ledgers, and leaves Home showing numbers the database no longer
holds. Accounts are managed with `account_admin`.
