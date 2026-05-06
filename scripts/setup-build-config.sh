#!/usr/bin/env bash
set -euo pipefail

# Copy android/{key.properties,oauth_bff.env,app_id.properties}.example into
# the real (gitignored) config locations so a fresh clone can build without
# hand-creating each file. Existing real files are NEVER overwritten —
# placeholder values must be replaced manually before producing a release
# build (see scripts/verify-release-keystore.sh, which still runs for
# release targets and rejects placeholder credentials).

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

# shellcheck source=scripts/lib/build-config-files.sh
source "$repo_root/scripts/lib/build-config-files.sh"

if [[ -t 1 ]]; then
    green=$'\033[32m'; yellow=$'\033[33m'; red=$'\033[31m'
    bold=$'\033[1m'; reset=$'\033[0m'
else
    green=""; yellow=""; red=""; bold=""; reset=""
fi

printf "\n%s== Bootstrap build config from .example templates ==%s\n" "$bold" "$reset"
printf "  既存ファイルは上書きしません。debug ビルドはこのままでも動きますが、release ビルド前に値を埋めてください。\n\n"

created_any=0
for target in "${BUILD_CONFIG_FILES[@]}"; do
    example="${target}.example"
    if [[ -f "$target" ]]; then
        printf "  %s[skip]%s    %s (already exists)\n" "$yellow" "$reset" "$target"
    elif [[ -f "$example" ]]; then
        cp "$example" "$target"
        printf "  %s[create]%s  %s ← %s\n" "$green" "$reset" "$target" "$example"
        created_any=1
    else
        printf "  %s[error]%s   %s (template %s missing)\n" "$red" "$reset" "$target" "$example"
    fi
done

printf "\n"
if (( created_any == 1 )); then
    printf "Next: edit the newly created files with real values, then run 'make show-config' to verify, or 'make build' / 'make build-release'.\n\n"
else
    printf "No files copied. Run 'make show-config' to see what each file currently resolves to.\n\n"
fi
