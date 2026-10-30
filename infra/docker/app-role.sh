#!/usr/bin/env bash
# Creates or refreshes mfa_app, the unprivileged login the API and the projector
# run as, and writes its connection URL into .env (ADR 0024).
#
#   sudo ./app-role.sh
#   docker compose --env-file .env up -d api projector
#
# Until this has run, both keep using MFA_DATABASE_URL as before. The password is
# generated here the first time and never printed.
set -euo pipefail
cd "$(dirname "$0")"
[ -f .env ] || { echo ".env not found beside this script" >&2; exit 1; }

setting() { grep -m1 "^$1=" .env | cut -d= -f2- || true; }

password="$(setting MFA_APP_DB_PASSWORD)"
if [ -z "$password" ]; then
  password="$(openssl rand -hex 24)"
  sed -i '/^MFA_APP_DB_PASSWORD=/d' .env
  printf 'MFA_APP_DB_PASSWORD=%s\n' "$password" >> .env
  chmod 600 .env
  echo "generated MFA_APP_DB_PASSWORD in .env"
fi
# Hex only, so it can sit inside a quoted SQL literal and a URL without escaping.
case "$password" in
  *[!0-9a-f]*) echo "MFA_APP_DB_PASSWORD must be lowercase hex; delete the line to regenerate it" >&2; exit 1 ;;
esac

user="$(setting POSTGRES_USER)"
database="$(setting POSTGRES_DB)"
{ printf '%s\n' "\\set app_password '${password}'"; cat app-role.sql; } \
  | docker compose --env-file .env exec -T postgres \
      psql -q -X -U "$user" -d "$database" -v ON_ERROR_STOP=1

sed -i '/^MFA_APP_DATABASE_URL=/d' .env
printf 'MFA_APP_DATABASE_URL=postgresql+asyncpg://mfa_app:%s@postgres:5432/%s\n' \
  "$password" "$database" >> .env
chmod 600 .env
echo "mfa_app is ready; recreate api and projector to start using it"
