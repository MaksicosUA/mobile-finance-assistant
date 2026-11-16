#!/usr/bin/env bash
#
# Asks whether this host is doing its job, and tells a watcher elsewhere.
#
#   sudo ./watch.sh
#
# A host cannot report its own death, so the report is turned around: every few
# minutes this says "still well" to a service outside, and that service raises
# the alarm when the word stops coming. A failure it can still speak about is
# reported at once, by name.
#
# What is asked:
#   api          the service answers through its public name and its own TLS,
#                with a query getting through to the database
#   projector    the read models are being kept up, with no dead letters
#   disk         neither the system disk nor the data volume is nearly full
#   certificate  the certificate will still be valid a week from now
#
# Only those words leave the host, never a path, a count or an error text.

set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${MFA_ENV_FILE:-$HERE/.env}"

[ -r "$ENV_FILE" ] || { echo "no readable $ENV_FILE" >&2; exit 78; }
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

: "${MFA_DOMAIN:?}" "${MFA_DATA_ROOT:?}"
DISK_PERCENT="${MFA_WATCH_DISK_PERCENT:-90}"
CERTIFICATE_DAYS="${MFA_WATCH_CERTIFICATE_DAYS:-7}"

failing=()

# The way a phone reaches it: the public name, Caddy, the certificate, the API,
# and one query through the pool every request shares. A 401 from any other
# route would prove only that the process is up.
if ! curl -fsS --max-time 20 -o /dev/null "https://$MFA_DOMAIN/api/v1/health"; then
  failing+=("api")
fi

# Said only when it fails: a healthy line every five minutes would bury the
# journal.
if ! projector="$(docker compose -f "$HERE/compose.yaml" --env-file "$ENV_FILE" \
  exec -T projector python -m mobile_finance_api.projector_runtime --check-health 2>&1)"; then
  echo "$projector" >&2
  failing+=("projector")
fi

for mount in / "$MFA_DATA_ROOT"; do
  used="$(df --output=pcent "$mount" 2>/dev/null | tail -n 1 | tr -dc '0-9')"
  # Unreadable counts as full: a volume that cannot be asked is not a healthy one.
  if [ -z "$used" ] || [ "$used" -ge "$DISK_PERCENT" ]; then
    echo "disk: $mount is at ${used:-an unknown} percent" >&2
    failing+=("disk")
    break
  fi
done

# Caddy renews a month ahead, so a certificate with a week left means renewal
# has been failing quietly for three, and there is still a week to fix it.
if ! echo | openssl s_client -connect "$MFA_DOMAIN:443" -servername "$MFA_DOMAIN" 2>/dev/null \
  | openssl x509 -noout -checkend "$((CERTIFICATE_DAYS * 86400))" >/dev/null 2>&1; then
  failing+=("certificate")
fi

# Telling can fail without changing the answer. If the word does not get out,
# the watcher hears silence, which is the alarm anyway.
tell() {
  local suffix="$1" words="$2" address="${MFA_WATCH_PING_URL:-}"
  [ -n "$address" ] || return 0
  curl -fsS --max-time 10 --retry 2 -o /dev/null --data-raw "$words" \
    "$address$suffix" 2>/dev/null \
    || echo "the watcher could not be told" >&2
}

if [ "${#failing[@]}" -eq 0 ]; then
  tell "" "ok"
  exit 0
fi

echo "failing: ${failing[*]}" >&2
tell "/fail" "${failing[*]}"
exit 1
