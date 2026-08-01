#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -gt 1 ]] || { [[ $# -eq 1 ]] && [[ $1 != "--install" ]]; }; then
  echo "Usage: $0 [--install]" >&2
  exit 64
fi

arguments=(--network-only)
if [[ ${1:-} == "--install" ]]; then
  arguments+=(--install-network)
fi
exec "$repo_root/tool/build_android_apks.sh" "${arguments[@]}"
