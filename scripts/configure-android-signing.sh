#!/usr/bin/env bash
set -euo pipefail

readonly secret_context="${ANDROID_SECRET_CONTEXT:-Android signing}"
readonly keystore_dir="android/keystore"
readonly keystore_path="$keystore_dir/release.jks"
readonly key_properties_path="android/key.properties"
readonly key_alias="${ANDROID_SIGNING_KEY_ALIAS:-release}"
readonly store_file="${ANDROID_SIGNING_STORE_FILE:-../keystore/release.jks}"

if [[ -z "${ANDROID_SIGNING_KEYSTORE_BASE64:-}" ]]; then
  echo "::error::ANDROID_SIGNING_KEYSTORE_BASE64 is not set for ${secret_context}."
  exit 1
fi

if [[ -z "${ANDROID_SIGNING_KEY_PASSWORD:-}" || -z "${ANDROID_SIGNING_STORE_PASSWORD:-}" ]]; then
  echo "::error::Missing signing secrets for ${secret_context}."
  exit 1
fi

mkdir -p "$keystore_dir"
echo "$ANDROID_SIGNING_KEYSTORE_BASE64" | base64 -d > "$keystore_path" \
  || { echo "::error::Failed to decode keystore."; exit 1; }

{
  printf 'storePassword=%s\n' "$ANDROID_SIGNING_STORE_PASSWORD"
  printf 'keyPassword=%s\n' "$ANDROID_SIGNING_KEY_PASSWORD"
  printf 'keyAlias=%s\n' "$key_alias"
  printf 'storeFile=%s\n' "$store_file"
} > "$key_properties_path"
