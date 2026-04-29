#!/usr/bin/env bash
set -euo pipefail

readonly secret_context="${ANDROID_SECRET_CONTEXT:-Android configuration}"
readonly output_path="android/app_id.properties"

if [[ -z "${ANDROID_APPLICATION_ID:-}" ]]; then
  echo "::error::ANDROID_APPLICATION_ID is not set for ${secret_context}."
  exit 1
fi

printf 'applicationId=%s\n' "$ANDROID_APPLICATION_ID" > "$output_path"
