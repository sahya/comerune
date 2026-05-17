#!/usr/bin/env bash
# Single source of truth for the gitignored Android build-config files
# whose presence/contents drive the debug-vs-release fallback in
# android/app/build.gradle.kts. Sourced by show-build-config.sh and
# setup-build-config.sh so adding a new file (e.g. another *.env) only
# requires editing this list.

# shellcheck disable=SC2034  # consumed via 'source' in sibling scripts
BUILD_CONFIG_FILES=(
    android/key.properties
    android/oauth_bff.env
    android/app_id.properties
)
