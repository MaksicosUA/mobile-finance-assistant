#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
flutter_bin="${FLUTTER_BIN:-flutter}"
adb_bin="${ADB_BIN:-adb}"
api_base_url="${API_BASE_URL:-http://127.0.0.1:8000}"
home_timezone="${HOME_API_TIMEZONE:-Europe/Berlin}"
install_after_build=false

if [[ $# -gt 1 ]] || { [[ $# -eq 1 ]] && [[ $1 != "--install" ]]; }; then
  echo "Usage: $0 [--install]" >&2
  exit 64
fi
if [[ ${1:-} == "--install" ]]; then
  install_after_build=true
fi

if [[ $api_base_url =~ [[:space:]@?#] ]]; then
  echo "API_BASE_URL must not contain whitespace, userinfo, query, or fragment." >&2
  exit 64
fi

if [[ ! $api_base_url =~ ^https://[^/]+(/.*)?$ ]] &&
  [[ ! $api_base_url =~ ^http://(127\.0\.0\.1|localhost|\[::1\])(:[0-9]+)?(/.*)?$ ]]; then
  echo "API_BASE_URL must use HTTPS or loopback with adb reverse." >&2
  exit 64
fi

if [[ ! $home_timezone =~ ^(UTC|[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)+)$ ]]; then
  echo "HOME_API_TIMEZONE must be a non-empty IANA timezone name." >&2
  exit 64
fi

cd "$repo_root"
network_apk="build/app/outputs/flutter-apk/mobile-finance-assistant-network-debug.apk"
if [[ -e $network_apk ]]; then
  unlink -- "$network_apk"
fi

"$flutter_bin" build apk \
  --debug \
  "--dart-define=API_BASE_URL=$api_base_url" \
  "--dart-define=HOME_API_TIMEZONE=$home_timezone"

source_apk="build/app/outputs/flutter-apk/app-debug.apk"
temporary_apk="${network_apk}.tmp"
cp -- "$source_apk" "$temporary_apk"
mv -- "$temporary_apk" "$network_apk"

if $install_after_build; then
  "$adb_bin" install -r "$network_apk"
fi

echo "Authenticated network APK: $network_apk"
