#!/usr/bin/env bash

# Copies the server's database dumps to this machine.
#
#   MFA_RELEASE_HOST=user@host tool/pull_backups.sh [DIRECTORY]
#
# The dumps sit on the same volume as the database, so a failed volume takes the
# copies with it. A dump is everyone's finances in the clear: the directory stays
# readable by its owner only, and it belongs on an encrypted disk.
#
# Nothing is deleted here. Old dumps are aged out on the server, not on this side.

set -euo pipefail

: "${MFA_RELEASE_HOST:?MFA_RELEASE_HOST must name the host to copy from}"
source_path="${MFA_BACKUP_PATH:-/mnt/mfa-data/backups}"
destination="${1:-$HOME/mfa-backups}"

umask 077
mkdir -p -- "$destination"
chmod 700 -- "$destination"

# The dumps are root's, so the far side runs through sudo.
rsync -a --rsync-path='sudo rsync' -- \
  "$MFA_RELEASE_HOST:$source_path/" "$destination/"

newest="$(ls -1t -- "$destination"/mfa-*.dump 2>/dev/null | head -1 || true)"
if [[ -z $newest ]]; then
  echo "No dump arrived." >&2
  exit 1
fi
echo "Newest dump: $(basename -- "$newest")"
