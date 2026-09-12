#!/usr/bin/env bash
# Creates or refreshes mfa_readonly: a login that reads everything except the
# password and refresh-token hashes, and can change nothing (ADR 0024).
#
#   sudo ./readonly-role.sh
#
# The password is generated here the first time and kept in .env beside every
# other secret. It is never printed; read it when signing in to Adminer with
#   sudo grep ^MFA_READONLY_DB_PASSWORD= .env
set -euo pipefail
cd "$(dirname "$0")"
[ -f .env ] || { echo ".env not found beside this script" >&2; exit 1; }

setting() { grep -m1 "^$1=" .env | cut -d= -f2- || true; }

password="$(setting MFA_READONLY_DB_PASSWORD)"
if [ -z "$password" ]; then
  password="$(openssl rand -hex 24)"
  sed -i '/^MFA_READONLY_DB_PASSWORD=/d' .env
  printf 'MFA_READONLY_DB_PASSWORD=%s\n' "$password" >> .env
  chmod 600 .env
  echo "generated MFA_READONLY_DB_PASSWORD in .env"
fi
# Hex only, so it can sit inside a quoted SQL literal without escaping.
case "$password" in
  *[!0-9a-f]*) echo "MFA_READONLY_DB_PASSWORD must be lowercase hex; delete the line to regenerate it" >&2; exit 1 ;;
esac

user="$(setting POSTGRES_USER)"
database="$(setting POSTGRES_DB)"
{ printf '%s\n' "\\set readonly_password '${password}'"; cat readonly-role.sql; } \
  | docker compose --env-file .env exec -T postgres \
      psql -q -X -U "$user" -d "$database" -v ON_ERROR_STOP=1
echo "mfa_readonly is ready: read-only, password and token hashes hidden"
