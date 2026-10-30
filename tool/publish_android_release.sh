#!/usr/bin/env bash

# Publishes a signed APK so installed apps can offer it as an update (ADR 0026).
#
# The APK is uploaded first and the manifest second, each through a temporary
# name and a rename, so a manifest never names a file that is not fully there.
#
#   MFA_RELEASE_HOST=user@host MFA_RELEASE_PATH=/mnt/mfa-data/releases \
#     tool/publish_android_release.sh [--check] [--notes "what changed"]
#
# --check stops after the file has been proved to be the deliverable.
#
# The server distributes what it is given; it cannot build or sign anything.

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

notes=""
check_only=false
apk="build/app/outputs/flutter-apk/mobile-finance-assistant-network-release.apk"
# The certificate every installed copy already trusts. It is public: anyone can
# read it from the APK. It is written down so that a build signed with anything
# else stops here rather than on someone's phone (issue 0005).
expected_signer="5d8f1fcc84ac318442a4b09b1898d18ac1cd4625b12d1a691ecc291deaa74668"

while (($# > 0)); do
  case "$1" in
    --notes)
      (($# >= 2)) || { echo "--notes needs a value" >&2; exit 64; }
      notes="$2"
      shift 2
      ;;
    --apk)
      (($# >= 2)) || { echo "--apk needs a value" >&2; exit 64; }
      apk="$2"
      shift 2
      ;;
    --check)
      check_only=true
      shift
      ;;
    *)
      echo "Usage: $0 [--check] [--apk PATH] [--notes TEXT]" >&2
      exit 64
      ;;
  esac
done

: "${MFA_RELEASE_HOST:?MFA_RELEASE_HOST must name the host to publish to}"
: "${MFA_RELEASE_PATH:?MFA_RELEASE_PATH must be the release directory on it}"

if [[ ! -f $apk ]]; then
  echo "No APK at $apk. Build one with tool/build_android_network_release.sh." >&2
  exit 66
fi

if [[ ${#notes} -gt 500 ]]; then
  echo "Notes must be at most 500 characters." >&2
  exit 64
fi

apkanalyzer_bin="${APKANALYZER_BIN:-}"
if [[ -z $apkanalyzer_bin ]]; then
  sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  apkanalyzer_bin="${sdk_root:+$sdk_root/cmdline-tools/latest/bin/apkanalyzer}"
fi
if [[ -z $apkanalyzer_bin || ! -x $apkanalyzer_bin ]]; then
  echo "APKANALYZER_BIN or Android SDK cmdline-tools/latest is required." >&2
  exit 64
fi

apksigner_bin="${APKSIGNER_BIN:-}"
if [[ -z $apksigner_bin ]]; then
  sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  apksigner_bin="$(ls -d "$sdk_root"/build-tools/*/apksigner 2>/dev/null | tail -1)"
fi
if [[ -z $apksigner_bin || ! -x $apksigner_bin ]]; then
  echo "APKSIGNER_BIN or Android SDK build-tools is required." >&2
  exit 64
fi

# Nothing leaves this machine until the file is shown to be the deliverable.
# These were manual steps, and a release without API_BASE_URL builds happily
# against a loopback address.
if [[ "$("$apkanalyzer_bin" manifest debuggable "$apk")" != "false" ]]; then
  echo "Refusing to publish a debuggable APK: run-as would open its storage." >&2
  exit 1
fi
signer="$("$apksigner_bin" verify --print-certs "$apk" |
  sed -n 's/^Signer #1 certificate SHA-256 digest: //p')"
if [[ $signer != "$expected_signer" ]]; then
  echo "Refusing to publish: the APK is not signed with the release key." >&2
  exit 1
fi
# The address with its scheme: the bare host sits in the HTTPS-only validator
# on purpose, so it proves nothing.
loopback="$(unzip -p "$apk" 'lib/*/libapp.so' |
  LC_ALL=C grep -a -c -E 'http://(127\.0\.0\.1|localhost|\[::1\])' || true)"
if [[ $loopback != "0" ]]; then
  echo "Refusing to publish: the APK points at a loopback address." >&2
  exit 1
fi
echo "Verified: release build, release key, no loopback address."
if $check_only; then
  exit 0
fi

# Read from the APK itself rather than from whatever the build printed: the
# manifest must describe the file that is actually being published.
version_name="$("$apkanalyzer_bin" manifest version-name "$apk")"
version_code="$("$apkanalyzer_bin" manifest version-code "$apk")"
size_bytes="$(stat -c '%s' "$apk")"
digest="$(sha256sum "$apk" | cut -d' ' -f1)"
published_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

if [[ ! $version_name =~ ^[0-9]+(\.[0-9]+){3}$ ]] ||
  [[ ! $version_code =~ ^[1-9][0-9]*$ ]]; then
  echo "The APK manifest does not carry a delivered version (ADR 0013)." >&2
  exit 1
fi

manifest="$(mktemp)"
trap 'rm -f "$manifest"' EXIT
if [[ -n $notes ]]; then
  notes_json="$(printf '%s' "$notes" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
else
  notes_json="null"
fi
cat >"$manifest" <<JSON
{
  "versionCode": $version_code,
  "versionName": "$version_name",
  "sizeBytes": $size_bytes,
  "sha256": "$digest",
  "notes": $notes_json,
  "publishedAt": "$published_at"
}
JSON

echo "Publishing $version_name ($version_code), $size_bytes bytes"

ssh "$MFA_RELEASE_HOST" "mkdir -p -- '$MFA_RELEASE_PATH' && chmod 0755 -- '$MFA_RELEASE_PATH'"
scp -q "$apk" "$MFA_RELEASE_HOST:$MFA_RELEASE_PATH/latest.apk.incoming"
# World-readable on purpose: the API container runs as its own unprivileged
# user, and neither file is a secret — the APK is exactly what is distributed.
ssh "$MFA_RELEASE_HOST" "chmod 0644 -- '$MFA_RELEASE_PATH/latest.apk.incoming' && mv -f -- '$MFA_RELEASE_PATH/latest.apk.incoming' '$MFA_RELEASE_PATH/latest.apk'"
# Second, and only now: until this lands the old manifest still describes the
# old file, and a device sees no update rather than a half-written one.
scp -q "$manifest" "$MFA_RELEASE_HOST:$MFA_RELEASE_PATH/latest.json.incoming"
ssh "$MFA_RELEASE_HOST" "chmod 0644 -- '$MFA_RELEASE_PATH/latest.json.incoming' && mv -f -- '$MFA_RELEASE_PATH/latest.json.incoming' '$MFA_RELEASE_PATH/latest.json'"

echo "Published. Devices on an older version will be offered $version_name."
