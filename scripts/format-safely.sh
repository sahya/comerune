#!/usr/bin/env bash
set -euo pipefail

# Run `dart format .` while keeping only files that were already part of the
# current change set. Any newly formatted out-of-scope tracked files are
# restored automatically.

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

declare -A keep_files=()

while IFS= read -r -d '' file; do
  keep_files["$file"]=1
done < <(git diff --name-only -z)

while IFS= read -r -d '' file; do
  keep_files["$file"]=1
done < <(git diff --cached --name-only -z)

echo "[format-safely] Running dart format ."
dart format .

restored_count=0
while IFS= read -r -d '' file; do
  if [[ -n "${keep_files[$file]+x}" ]]; then
    continue
  fi
  git restore --worktree --staged -- "$file"
  restored_count=$((restored_count + 1))
done < <(git diff --name-only -z)

echo "[format-safely] Restored out-of-scope tracked files: $restored_count"
