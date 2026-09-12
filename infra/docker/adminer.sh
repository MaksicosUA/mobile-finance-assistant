#!/usr/bin/env bash
# Starts or stops Adminer for looking at the database (ADR 0024).
#
#   sudo ./adminer.sh start     # listens on 127.0.0.1:8080 of this host only
#   sudo ./adminer.sh stop
#
# Nothing is published. From your own computer, open a tunnel first:
#   ssh -N -L 8080:127.0.0.1:8080 <user>@<host>
# then browse http://localhost:8080 and sign in as mfa_readonly — System
# "PostgreSQL", Server "postgres", Database the POSTGRES_DB value, password from
#   sudo grep ^MFA_READONLY_DB_PASSWORD= .env
# It stops by itself after two hours, so it cannot be left running and forgotten.
set -euo pipefail
cd "$(dirname "$0")"

readonly name=mfa-adminer
# The tag names the version for people; the digest is the image that was
# actually tested, so a re-pushed tag cannot change what runs here.
readonly image=adminer:6.0.1-standalone@sha256:f742dcf1b6ca95733b54c4e020488ce78f3e774d73543a6ded9b4eaea8974f3d
readonly lifetime_seconds=7200

case "${1:-}" in
  start)
    if docker ps --format '{{.Names}}' | grep -qx "$name"; then
      echo "$name is already running"
      exit 0
    fi
    postgres="$(docker compose ps -q postgres)"
    [ -n "$postgres" ] || { echo "postgres is not running" >&2; exit 1; }
    network="$(docker inspect "$postgres" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}')"
    container="$(docker run -d --rm --name "$name" --network "$network" \
      -p 127.0.0.1:8080:8080 -e ADMINER_DEFAULT_SERVER=postgres "$image")"
    # Stops this container by id, so an earlier timer cannot stop a later start.
    setsid nohup sh -c "sleep $lifetime_seconds; docker stop $container" \
      >/dev/null 2>&1 < /dev/null &
    echo "Adminer is up on 127.0.0.1:8080 of this host for two hours."
    echo "From your computer: ssh -N -L 8080:127.0.0.1:8080 ${SUDO_USER:-$(id -un)}@<host>"
    echo "then open http://localhost:8080 and sign in as mfa_readonly."
    ;;
  stop)
    if docker stop "$name" >/dev/null 2>&1; then echo "$name stopped"; else echo "$name was not running"; fi
    ;;
  *)
    echo "usage: $0 start|stop" >&2
    exit 2
    ;;
esac
