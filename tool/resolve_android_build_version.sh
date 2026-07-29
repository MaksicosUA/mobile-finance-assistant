#!/usr/bin/env bash

set -euo pipefail

readonly version_code_stride=1000000
readonly android_version_code_max=2100000000

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  echo "Android build version: $*" >&2
  exit 64
}

git rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
  fail "the source is not a Git worktree."

if [[ $(git rev-parse --is-shallow-repository) != "false" ]]; then
  fail "full Git history is required; fetch with --unshallow first."
fi
grafts_file="$(git rev-parse --git-path info/grafts)"
if [[ -n $(git replace -l) ]] || [[ -s $grafts_file ]]; then
  fail "Git replace refs and grafts are not allowed for reproducible versions."
fi

head_revision="$(git rev-parse --verify 'HEAD^{commit}')" ||
  fail "HEAD is not a commit."
git rev-list --objects --missing=error "$head_revision" >/dev/null ||
  fail "the reachable Git history is incomplete."

if ! worktree_status="$(git status --porcelain=v1 --untracked-files=all)"; then
  fail "the worktree status could not be inspected."
fi
if [[ -n $worktree_status ]]; then
  fail "the worktree must be clean so one SHA identifies the APK source."
fi

previous_revision="${ANDROID_PREVIOUS_REVISION:-}"
if [[ -n $previous_revision ]]; then
  if [[ ! $previous_revision =~ ^[0-9a-fA-F]{40}$ ]]; then
    fail "ANDROID_PREVIOUS_REVISION must be a full Git commit SHA."
  fi
  previous_revision="${previous_revision,,}"
  if [[ $previous_revision != "0000000000000000000000000000000000000000" ]]; then
    git cat-file -e "${previous_revision}^{commit}" 2>/dev/null ||
      fail "the previous delivered revision is unavailable."
    git merge-base --is-ancestor "$previous_revision" "$head_revision" ||
      fail "HEAD must descend from the previous delivered revision."
  fi
fi

version_line="$(sed -nE '/^version:[[:space:]]*/p' pubspec.yaml)"
if [[ $(printf '%s\n' "$version_line" | wc -l) -ne 1 ]]; then
  fail "pubspec.yaml must contain exactly one numeric version x.y.z+epoch."
fi
if [[ $version_line =~ ^version:[[:space:]]*(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\+([1-9][0-9]*)[[:space:]]*$ ]]; then
  major="${BASH_REMATCH[1]}"
  minor="${BASH_REMATCH[2]}"
  patch="${BASH_REMATCH[3]}"
  version_epoch="${BASH_REMATCH[4]}"
else
  fail "pubspec.yaml must contain exactly one numeric version x.y.z+epoch."
fi

while IFS= read -r version_revision; do
  ancestor_version_line="$(
    git show "${version_revision}:pubspec.yaml" 2>/dev/null |
      sed -nE '/^version:[[:space:]]*/p'
  )" || fail "an ancestor pubspec version could not be inspected."
  if [[ $ancestor_version_line =~ ^version:[[:space:]]*(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\+([1-9][0-9]*)[[:space:]]*$ ]]; then
    ancestor_epoch="${BASH_REMATCH[4]}"
  else
    fail "an ancestor pubspec.yaml has an unsupported version."
  fi
  if ((10#$ancestor_epoch > 10#$version_epoch)); then
    fail "the pubspec build epoch must not decrease across history."
  fi
done < <(git log --format='%H' "$head_revision" -- pubspec.yaml)

if ((${#version_epoch} > 4)) || ((10#$version_epoch > 2099)); then
  fail "the pubspec build epoch is outside the supported range."
fi

commit_count="$(git rev-list --count "$head_revision")" ||
  fail "the reachable commit count could not be resolved."
if [[ ! $commit_count =~ ^[0-9]+$ ]] ||
  ((10#$commit_count < 1 || 10#$commit_count >= version_code_stride)); then
  fail "the reachable commit count is outside the supported range."
fi

build_number=$((10#$version_epoch * version_code_stride + 10#$commit_count))
if ((build_number > android_version_code_max)); then
  fail "the derived versionCode exceeds Android's maximum."
fi

build_name="${major}.${minor}.${patch}.${build_number}"

printf 'build_name=%s\n' "$build_name"
printf 'build_number=%s\n' "$build_number"
printf 'revision=%s\n' "$head_revision"
printf 'commit_count=%s\n' "$commit_count"
printf 'source_version=%s.%s.%s+%s\n' \
  "$major" "$minor" "$patch" "$version_epoch"
