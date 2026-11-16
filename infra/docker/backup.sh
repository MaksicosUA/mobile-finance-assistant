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
#
# A dump that stays on this volume is lost with it, so each one is then sent
# away sealed (`offsite.py`), and a watcher elsewhere is told how the run ended.
# Silence is the third answer: a host that is gone tells nobody, and the
# watcher notices the missing word.

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

# Which step was under way, for the watcher to pass on. A word, never a path
# or an error text: the address it goes to is someone else's server.
STAGE="dump"

# Tells the watcher how this run ended, if there is one to tell. Telling can
# fail without changing the answer: a backup that worked is not undone by a
# watcher that could not be reached, and one that failed stays failed.
tell() {
  local status="$1" address="${MFA_BACKUP_PING_URL:-}"
  [ -n "$address" ] || return 0
  if [ "$status" -ne 0 ]; then
    address="$address/fail"
  fi
  curl -fsS --max-time 10 --retry 2 -o /dev/null \
    --data-raw "$([ "$status" -eq 0 ] && echo ok || echo "$STAGE")" \
    "$address" 2>/dev/null \
    || echo "the backup watcher could not be told" >&2
}

finish() {
  local status=$?
  rm -f "$PARTIAL"
  tell "$status"
  exit "$status"
}
trap finish EXIT

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
chmod 600 "$TARGET"
echo "wrote $TARGET ($SIZE bytes)"

# Retention runs only after a good dump, so a run of failures can never age out
# the last working copy.
#
# In minutes, with an hour's slack: `-mtime +14` means "fifteen days or more",
# and the timer does not fire at the same minute every night. An erased account
# is promised that backups hold it for fourteen days and no longer (ADR 0030),
# so a dump has to be gone at the run fourteen days after its own.
STAGE="retention"
find "$DESTINATION" -maxdepth 1 \
  \( -name 'mfa-*.dump' -o -name 'mfa-*.dump.sent' \) \
  -mmin "+$((KEEP_DAYS * 1440 - 60))" -print -delete
# Left by a run that was killed halfway.
find "$DESTINATION" -maxdepth 1 -name 'mfa-*.partial' -mmin +1440 -delete

# After retention, so nothing about to be aged out is sent first. A failure
# here fails the run, and the dump just written stays where it is.
STAGE="offsite"
python3 "$HERE/offsite.py" "$DESTINATION"
