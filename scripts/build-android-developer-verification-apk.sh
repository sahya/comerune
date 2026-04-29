#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

readonly asset_path="android/app/src/main/assets/adi-registration.properties"
readonly app_id_properties_path="android/app_id.properties"
readonly key_properties_path="android/key.properties"
readonly output_dir="build/app/outputs/flutter-apk"
readonly release_apk_path="$output_dir/app-release.apk"
readonly verification_output_path="$output_dir/comerune-android-developer-verification-arm64.apk"

require_file() {
  local path="$1"
  local message="$2"
  if [[ ! -f "$path" ]]; then
    echo "$message"
    exit 1
  fi
}

resolve_store_file_path() {
  local store_file
  local candidate_dir
  local candidate_name

  store_file="$(sed -n 's/^storeFile=//p' "$key_properties_path" | tail -n 1)"
  if [[ -z "$store_file" ]]; then
    echo "storeFile is missing in $key_properties_path."
    exit 1
  fi

  if [[ "$store_file" = /* ]]; then
    printf '%s\n' "$store_file"
    return
  fi

  candidate_dir="$repo_root/android/app/$(dirname "$store_file")"
  candidate_name="$(basename "$store_file")"

  if [[ ! -d "$candidate_dir" ]]; then
    echo "Directory referenced by storeFile does not exist: $candidate_dir"
    exit 1
  fi

  (
    cd "$candidate_dir"
    printf '%s/%s\n' "$(pwd -P)" "$candidate_name"
  )
}

require_file "$app_id_properties_path" \
  "android/app_id.properties is required. See docs/build-guide.md."
require_file "$key_properties_path" \
  "android/key.properties is required. See docs/build-guide.md."

if [[ -z "${ANDROID_ADI_REGISTRATION_PUBLIC_CONTENT_FILE:-}" ]]; then
  echo "ANDROID_ADI_REGISTRATION_PUBLIC_CONTENT_FILE is required."
  exit 1
fi

require_file "$ANDROID_ADI_REGISTRATION_PUBLIC_CONTENT_FILE" \
  "$ANDROID_ADI_REGISTRATION_PUBLIC_CONTENT_FILE not found."

resolved_store_file_path="$(resolve_store_file_path)"
require_file "$resolved_store_file_path" \
  "Keystore referenced by android/key.properties was not found: $resolved_store_file_path"

if [[ -f "$asset_path" ]]; then
  echo "$asset_path already exists. Remove it before running this command."
  exit 1
fi

mkdir -p "$(dirname "$asset_path")"
trap 'rm -f "$asset_path"' EXIT
cp "$ANDROID_ADI_REGISTRATION_PUBLIC_CONTENT_FILE" "$asset_path"

flutter build apk --release --target-platform android-arm64 --obfuscate --split-debug-info=build/debug-info

unzip -l "$release_apk_path" | grep -q "assets/adi-registration.properties" \
  || { echo "Verification APK does not contain assets/adi-registration.properties."; exit 1; }

mv -f "$release_apk_path" "$verification_output_path"
echo "Built verification APK: $verification_output_path"
