#!/usr/bin/env bash
set -euo pipefail

# Print which property/key files the next build will actually load.
#
# Background: android/key.properties, android/oauth_bff.env and
# android/app_id.properties are gitignored. When absent (or filled with
# example placeholders), build.gradle.kts silently falls back to debug
# values so local development still works. That fallback also means a
# misconfigured machine can produce a "release" APK that quietly used
# debug values. This banner makes the choice visible at build time.
#
# We deliberately DO NOT print resolved secret-adjacent values
# (OAUTH_BFF_HOST, applicationId) so the banner stays safe to paste into
# bug reports or screencasts. The banner only states release-vs-fallback;
# real values stay in the gitignored files.

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

# shellcheck source=scripts/lib/build-config-files.sh
source "$repo_root/scripts/lib/build-config-files.sh"

# Pull paths out of the shared list by basename, so this script and
# setup-build-config.sh stay in sync via a single source of truth.
key_file=""
bff_file=""
appid_file=""
for f in "${BUILD_CONFIG_FILES[@]}"; do
    case "$(basename "$f")" in
        key.properties)     key_file="$f" ;;
        oauth_bff.env)      bff_file="$f" ;;
        app_id.properties)  appid_file="$f" ;;
    esac
done

build_kind="${1:-build}"

if [[ -t 1 ]]; then
    green=$'\033[32m'; yellow=$'\033[33m'; red=$'\033[31m'
    bold=$'\033[1m'; reset=$'\033[0m'
else
    green=""; yellow=""; red=""; bold=""; reset=""
fi

read_kv() {
    sed -n "s/^${2}=//p" "$1" 2>/dev/null | tail -n 1 | tr -d '\r'
}

# Status helpers — fixed-width labels keep the file column aligned.
release_ok() {
    printf "  %s[release]%s         %-32s — %s\n" "$green"  "$reset" "$1" "$2"
}
fallback() {
    printf "  %s[debug fallback]%s  %-32s — %s\n" "$yellow" "$reset" "$1" "$2"
}
absent() {
    printf "  %s[file absent]%s     %-32s — %s (debug fallback)\n" "$red" "$reset" "$1" "$2"
}

printf "\n%s== Build configuration (%s) ==%s\n" "$bold" "$build_kind" "$reset"
printf "  鍵やプロパティファイルが見つからないときは debug フォールバックされます。以下で確認してください。\n\n"

# --- key.properties (release signing) ---
# We only show the alias name (it is also visible via apksigner output and
# via Play Console upload metadata). storeFile path, passwords, and
# fingerprints are never printed.
if [[ -f "$key_file" ]]; then
    sp="$(read_kv "$key_file" storePassword)"
    kp="$(read_kv "$key_file" keyPassword)"
    sf="$(read_kv "$key_file" storeFile)"
    ka="$(read_kv "$key_file" keyAlias)"
    if [[ -z "$sp" || -z "$kp" || -z "$sf" || -z "$ka" ]]; then
        fallback "$key_file" "incomplete (missing required keys), debug signing"
    elif [[ "$sp" == "your_store_password" || "$kp" == "your_key_password" ]]; then
        fallback "$key_file" "example placeholder values, debug signing"
    else
        release_ok "$key_file" "release signing (alias=$ka)"
    fi
else
    absent "$key_file" "debug signing will be used"
fi

# --- oauth_bff.env (App Links host + Dart defines) ---
# Host value is intentionally not printed — production hosts can be
# sensitive when banners get pasted into screencasts / bug reports.
if [[ -f "$bff_file" ]]; then
    host="$(read_kv "$bff_file" OAUTH_BFF_HOST)"
    if [[ -z "$host" ]]; then
        fallback "$bff_file" "OAUTH_BFF_HOST not set, App Links use .invalid host"
    else
        release_ok "$bff_file" "OAUTH_BFF_HOST configured"
    fi
else
    absent "$bff_file" "App Links use .invalid host, OAuth login disabled"
fi

# --- app_id.properties (applicationId) ---
# Configured value is not printed (production app id identifies the
# product). Default placeholder is named explicitly because that detection
# is the whole point of the banner.
if [[ -f "$appid_file" ]]; then
    aid="$(read_kv "$appid_file" applicationId)"
    if [[ -z "$aid" ]]; then
        fallback "$appid_file" "applicationId not set, default com.example.comerune"
    elif [[ "$aid" == "com.example.comerune" ]]; then
        fallback "$appid_file" "applicationId is default placeholder com.example.comerune"
    else
        release_ok "$appid_file" "applicationId configured"
    fi
else
    absent "$appid_file" "applicationId=com.example.comerune"
fi

printf "\n"
