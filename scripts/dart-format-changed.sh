#!/usr/bin/env bash
set -euo pipefail

BASE_REF="${1:-origin/main}"

if ! git rev-parse --verify --quiet "$BASE_REF" >/dev/null; then
  echo "Base ref '$BASE_REF' was not found." >&2
  echo "Usage: scripts/dart-format-changed.sh [base-ref]" >&2
  exit 1
fi

MERGE_BASE="$(git merge-base HEAD "$BASE_REF")"

declare -A seen=()
declare -a dart_files=()

add_unique() {
  local path="$1"
  if [[ -n "${seen[$path]:-}" ]]; then
    return 0
  fi
  if [[ -f "$path" ]]; then
    seen["$path"]=1
    dart_files+=("$path")
  fi
}

collect_from_git() {
  local -a cmd=("$@")
  while IFS= read -r -d '' path; do
    add_unique "$path"
  done < <("${cmd[@]}")
}

collect_from_git git diff --name-only --diff-filter=ACMR -z "${MERGE_BASE}...HEAD" -- '*.dart'
collect_from_git git diff --name-only --diff-filter=ACMR -z --cached -- '*.dart'
collect_from_git git diff --name-only --diff-filter=ACMR -z -- '*.dart'
collect_from_git git ls-files --others --exclude-standard -z -- '*.dart'

if [[ ${#dart_files[@]} -eq 0 ]]; then
  echo "No changed Dart files detected. Skipping dart format."
  exit 0
fi

echo "Formatting ${#dart_files[@]} changed Dart files (base: $BASE_REF):"
printf '  %s\n' "${dart_files[@]}"
dart format "${dart_files[@]}"
