#!/usr/bin/env bash
#
# One logical backup of the finance database.
#
# Provider snapshots capture a disk, which is not the same as a database: a
# snapshot taken mid-write restores a file tree PostgreSQL then has to repair,
# and nothing tells you in advance whether it can. A dump is the database
# saying what it holds.
#
# Custom format rather than plain SQL: it is compressed, and `pg_restore` can
# pull a single table out of it without replaying the rest.

set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${MFA_ENV_FILE:-$HERE/.env}"
KEEP_DAYS="${MFA_BACKUP_KEEP_DAYS:-14}"

# The smallest dump this database could honestly produce. A truncated or empty
# file that lands quietly is worse than a loud failure, because it looks like a
# backup until the day it is needed.
MINIMUM_BYTES="${MFA_BACKUP_MINIMUM_BYTES:-20000}"

[ -r "$ENV_FILE" ] || { echo "no readable $ENV_FILE" >&2; exit 78; }
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

: "${POSTGRES_USER:?}" "${POSTGRES_DB:?}"
DESTINATION="${MFA_DATA_ROOT:?}/backups"
# A dump is everyone's finances, including while it is being written.
umask 077
mkdir -p "$DESTINATION"
chmod 700 "$DESTINATION"

STAMP="$(date -u +%Y-%m-%dT%H%M%SZ)"
TARGET="$DESTINATION/mfa-$STAMP.dump"

# Written to a temporary name and moved into place only once it is complete,
# so a run interrupted halfway never leaves a file that looks finished.
PARTIAL="$TARGET.partial"
trap 'rm -f "$PARTIAL"' EXIT

# No password: the image trusts its own local socket, and an argument would be
# readable in the process list for as long as the dump runs.
docker compose -f "$HERE/compose.yaml" --env-file "$ENV_FILE" exec -T postgres \
  pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom \
  > "$PARTIAL"

SIZE=$(stat -c %s "$PARTIAL")
if [ "$SIZE" -lt "$MINIMUM_BYTES" ]; then
  echo "dump is only $SIZE bytes, refusing to keep it" >&2
  exit 1
fi

mv "$PARTIAL" "$TARGET"
trap - EXIT
chmod 600 "$TARGET"
echo "wrote $TARGET ($SIZE bytes)"

# Retention runs only after a good dump, so a run of failures can never age out
# the last working copy.
find "$DESTINATION" -maxdepth 1 -name 'mfa-*.dump' -mtime "+$KEEP_DAYS" -print -delete
