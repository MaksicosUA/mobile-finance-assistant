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

## Backups

Hetzner snapshots capture the disk, which is not the same as a consistent
database. Take a logical dump as well:

    docker compose exec -T postgres pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" \
      | gzip > "/mnt/mfa-data/backups/$(date -u +%Y-%m-%dT%H%M).sql.gz"
