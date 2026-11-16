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

## Running as an unprivileged login

The account `POSTGRES_USER` names is a superuser, because the image makes it one.
Migrations need that; serving requests does not. Once, on the host:

    sudo ./app-role.sh
    docker compose --env-file .env up -d api projector

It creates `mfa_app`, which reads and writes rows and nothing else, and writes
its URL into `.env`. Until it has run, both services keep using
`MFA_DATABASE_URL`, so no deploy depends on it. Migrations stay on the privileged
login, and tables they create later are granted automatically.

## Backups

Provider snapshots capture a disk, which is not the same as a database: a
snapshot taken mid-write restores a file tree PostgreSQL then has to repair,
and nothing tells you in advance whether it can.

`backup.sh` takes a logical dump in custom format, refuses to keep a
suspiciously small one, and only then ages out anything older than
`MFA_BACKUP_KEEP_DAYS` — so a run of failures can never delete the last working
copy. Fourteen days means fourteen: a dump is gone at the run two weeks after
its own, because that is what a person who erased their account was told
(ADR 0030). Install the schedule once:

    sudo cp mfa-backup.service mfa-backup.timer /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable --now mfa-backup.timer

Failures surface in `systemctl status mfa-backup` and the journal, and are told
to a watcher outside the host when one is set (below).

### A copy that leaves the host

The dumps sit on the same volume as the database, so a lost volume, a lost host
or a lost provider account takes both. After each dump `backup.sh` runs
`offsite.py`, which seals the dump with `age` and uploads it to a Backblaze B2
bucket.

What leaves is ciphertext, sealed to a public key. The host holds only that
public key: it can seal a dump and cannot open one. The private key stays with
the owner, off this host and off the storage account, so taking either reads
nothing. **Losing the private key loses every copy that left.** Keep it where
the signing key's copy is kept, and in a password manager.

Once, on the host:

    sudo apt install age

On a machine that is not the host, make the key pair. The file is the private
key; the line it prints is the public one:

    age-keygen -o mfa-backup.key

In Backblaze B2:

1. A **private** bucket, with **Object Lock enabled** when it is created.
2. Lifecycle, custom rule for the whole bucket: hide after **9** days, delete
   **1** day after hiding. A copy is then gone within twelve days of arriving,
   and the two nights a failed upload may wait keep that inside the fourteen an
   erased account was promised. Do not lengthen it without changing that promise.
3. If the bucket offers a default retention, 9 days: until then nobody, with
   any key, can remove a copy.
4. An application key limited to that bucket, **Write Only**.

Then in `.env`, all four:

    MFA_OFFSITE_AGE_RECIPIENT=age1...
    MFA_OFFSITE_B2_KEY_ID=...
    MFA_OFFSITE_B2_APPLICATION_KEY=...
    MFA_OFFSITE_B2_BUCKET=...

Ask what the key may do, without sending anything, then send:

    sudo sh -c 'set -a; . ./.env; python3 offsite.py --check "$MFA_DATA_ROOT/backups"'
    sudo ./backup.sh

A key that can also delete is pointed out on every run rather than refused,
because the console's presets may not offer less; Object Lock is then what
keeps a copy from whoever holds the key. A dump that could not be sent fails
the run and waits for the next two; each one sent leaves a small `.sent` receipt
beside it. Dumps older than two days are not sent late.

To get one back: download the `.age` file from the bucket in the Backblaze
console, then, where the private key is,

    age --decrypt -i mfa-backup.key mfa-<stamp>.dump.age > mfa-<stamp>.dump

and restore it as below. `tool/pull_backups.sh` still copies the plain dumps to
another machine; that copy belongs on an encrypted disk.

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

## Being told when it stops

A host cannot report its own death, so the report is turned around. Every five
minutes `watch.sh` asks whether the host is doing its job and says "still well"
to a service outside it (healthchecks.io); that service raises the alarm when
the word stops coming, and again when it comes back. `backup.sh` does the same
once a night.

`watch.sh` asks four things and names the ones that fail:

- `api` — `GET /api/v1/health` through the public name and its own TLS. Every
  other route answers 401 before it looks at the database; this one sends a
  query through the pool the requests share, and says up or down and nothing
  else.
- `projector` — its own health check: leader present, no lag, no dead letters.
- `disk` — the system disk or the data volume is at 90 percent or more.
- `certificate` — less than a week of validity left, which means renewal has
  been failing for three.

Only those words leave the host. In healthchecks.io, two checks:

| Check | Period | Grace | Goes into `.env` as |
|---|---|---|---|
| the host | 5 minutes | 5 minutes | `MFA_WATCH_PING_URL` |
| the backup | 1 day | 2 hours | `MFA_BACKUP_PING_URL` |

Each address is a capability: whoever has it can speak for this host. Then:

    sudo cp mfa-watch.service mfa-watch.timer /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable --now mfa-watch.timer

Run by hand, `sudo ./watch.sh` prints what is failing and exits non-zero.
Without the addresses both scripts still run and answer only in the journal.

The watch runs on the host it watches, so it cannot see a fault that only the
outside sees, such as a DNS record pointing elsewhere.

## Looking at the database

The database publishes no port, and it stays that way: everything below goes
through SSH.

Once, and again after a migration adds a column to `users` or
`auth_refresh_tokens`:

    sudo ./readonly-role.sh

It creates `mfa_readonly`, which can read every table except the password hash,
the recovery-code hash and the refresh-token hash, runs every statement in a
read-only transaction, and can therefore change nothing. A column a migration
adds to those two tables stays unreadable until the script is run again, so
forgetting to run it hides something rather than exposing it. Its password is generated into `.env` and never
printed.

When you want to look:

    sudo ./adminer.sh start        # on the host; stops itself after two hours
    ssh -N -L 8080:127.0.0.1:8080 <user>@<host>    # on your computer

Open http://localhost:8080 and sign in with System **PostgreSQL**, Server
**postgres**, Username **mfa_readonly**, Database the `POSTGRES_DB` value, and the
password from `sudo grep ^MFA_READONLY_DB_PASSWORD= .env`. `sudo ./adminer.sh stop`
when done.

`users` and `auth_refresh_tokens` refuse `SELECT *`, because some of their columns
are hidden: in Adminer, choose the columns under **Select** before opening them.
For accounts, `account_admin list` is quicker anyway.

**Do not edit financial rows by hand, even with a stronger login.** A write that
skips Finance Core skips its audit row and its outbox invalidation, can break
the append-only ledgers, and leaves Home showing numbers the database no longer
holds. Accounts are managed with `account_admin`.
