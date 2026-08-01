#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
flutter_bin="${FLUTTER_BIN:-flutter}"
adb_bin="${ADB_BIN:-adb}"
api_base_url="${API_BASE_URL:-http://127.0.0.1:8000}"
home_timezone="${HOME_API_TIMEZONE:-Europe/Berlin}"
network_only=false
install_network=false
github_output=""

usage() {
  echo "Usage: $0 [--network-only] [--install-network] [--github-output PATH]" >&2
  exit 64
}

while (($# > 0)); do
  case "$1" in
    --network-only)
      network_only=true
      shift
      ;;
    --install-network)
      install_network=true
      shift
      ;;
    --github-output)
      (($# >= 2)) || usage
      github_output="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

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

build_name=""
build_number=""
revision=""
commit_count=""
source_version=""
while IFS='=' read -r key value; do
  case "$key" in
    build_name) build_name="$value" ;;
    build_number) build_number="$value" ;;
    revision) revision="$value" ;;
    commit_count) commit_count="$value" ;;
    source_version) source_version="$value" ;;
    *)
      echo "Unexpected Android build-version field: $key" >&2
      exit 64
      ;;
  esac
done < <(tool/resolve_android_build_version.sh)

if [[ ! $build_name =~ ^[0-9]+(\.[0-9]+){3}$ ]] ||
  [[ ! $build_number =~ ^[1-9][0-9]*$ ]] ||
  [[ ! $revision =~ ^[0-9a-f]+$ ]] ||
  [[ ! $commit_count =~ ^[1-9][0-9]*$ ]] ||
  [[ -z $source_version ]]; then
  echo "Android build-version resolver returned incomplete data." >&2
  exit 64
fi

output_dir="build/app/outputs/flutter-apk"
source_apk="$output_dir/app-debug.apk"
fixture_apk="$output_dir/mobile-finance-assistant-fixture-debug.apk"
network_apk="$output_dir/mobile-finance-assistant-network-debug.apk"

apkanalyzer_bin="${APKANALYZER_BIN:-}"
if [[ -z $apkanalyzer_bin ]]; then
  if command -v apkanalyzer >/dev/null 2>&1; then
    apkanalyzer_bin="$(command -v apkanalyzer)"
  else
    sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
    if [[ -n $sdk_root ]]; then
      apkanalyzer_bin="$sdk_root/cmdline-tools/latest/bin/apkanalyzer"
    fi
  fi
fi
if [[ -z $apkanalyzer_bin || ! -x $apkanalyzer_bin ]]; then
  echo "APKANALYZER_BIN or Android SDK cmdline-tools/latest is required." >&2
  exit 64
fi

replace_apk() {
  local source="$1"
  local destination="$2"
  local temporary="${destination}.tmp"
  if [[ -e $temporary ]]; then
    unlink -- "$temporary"
  fi
  cp -- "$source" "$temporary"
  mv -- "$temporary" "$destination"
}

if ! $network_only; then
  if [[ -e $fixture_apk ]]; then
    unlink -- "$fixture_apk"
  fi
  "$flutter_bin" build apk \
    --debug \
    "--build-name=$build_name" \
    "--build-number=$build_number"
  replace_apk "$source_apk" "$fixture_apk"
fi

if [[ -e $network_apk ]]; then
  unlink -- "$network_apk"
fi
"$flutter_bin" build apk \
  --debug \
  "--build-name=$build_name" \
  "--build-number=$build_number" \
  "--dart-define=API_BASE_URL=$api_base_url" \
  "--dart-define=HOME_API_TIMEZONE=$home_timezone"
replace_apk "$source_apk" "$network_apk"

verify_apk_version() {
  local apk="$1"
  local actual_name
  local actual_number
  actual_name="$("$apkanalyzer_bin" manifest version-name "$apk")"
  actual_number="$("$apkanalyzer_bin" manifest version-code "$apk")"
  if [[ $actual_name != "$build_name" || $actual_number != "$build_number" ]]; then
    echo "Unexpected Android manifest version in $apk." >&2
    exit 1
  fi
}

if ! $network_only; then
  verify_apk_version "$fixture_apk"
fi
verify_apk_version "$network_apk"

if ! final_revision="$(git rev-parse --verify 'HEAD^{commit}')"; then
  echo "The committed source revision could not be re-read after the build." >&2
  exit 1
fi
if ! final_status="$(git status --porcelain=v1 --untracked-files=all)"; then
  echo "The worktree status could not be re-read after the build." >&2
  exit 1
fi
if [[ $final_revision != "$revision" || -n $final_status ]]; then
  echo "The committed source changed while Android APKs were building." >&2
  exit 1
fi

metadata_file="$output_dir/android-build-version.txt"
{
  printf 'revision=%s\n' "$revision"
  printf 'source_version=%s\n' "$source_version"
  printf 'build_name=%s\n' "$build_name"
  printf 'build_number=%s\n' "$build_number"
  printf 'commit_count=%s\n' "$commit_count"
} >"$metadata_file"

if [[ -n $github_output ]]; then
  {
    printf 'build_name=%s\n' "$build_name"
    printf 'build_number=%s\n' "$build_number"
    printf 'revision=%s\n' "$revision"
  } >>"$github_output"
fi

if $install_network; then
  "$adb_bin" install -r "$network_apk"
fi

if ! $network_only; then
  echo "Fixture APK: $fixture_apk"
fi
echo "Authenticated network APK: $network_apk"
echo "Android version: $build_name ($build_number), revision $revision"
