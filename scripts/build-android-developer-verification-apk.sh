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

resolve_store_file_path() {
  local store_file
  local candidate_dir
  local candidate_name

  store_file="$(sed -n 's/^storeFile=//p' "$key_properties_path" | tail -n 1)"
  if [[ -z "$store_file" ]]; then
    printf '%s\n' "INVALID:storeFile-missing"
    return
  fi

  if [[ "$store_file" = /* ]]; then
    printf '%s\n' "$store_file"
    return
  fi

  candidate_dir="$repo_root/android/app/$(dirname "$store_file")"
  candidate_name="$(basename "$store_file")"

  if [[ ! -d "$candidate_dir" ]]; then
    printf '%s\n' "INVALID:storeFile-dir-missing:$candidate_dir"
    return
  fi

  (
    cd "$candidate_dir"
    printf '%s/%s\n' "$(pwd -P)" "$candidate_name"
  )
}

# Pre-flight: collect every missing prerequisite at once with actionable hints
# instead of failing on the first one. The verification flow is rare enough
# that contributors usually hit a cold setup; surfacing every missing piece
# up-front avoids a frustrating "fix one thing, re-run, fix the next" loop.
preflight_errors=()

if [[ ! -f "$app_id_properties_path" ]]; then
  preflight_errors+=(
    "[missing] $app_id_properties_path"
    "  fix: cp android/app_id.properties.example $app_id_properties_path && \$EDITOR $app_id_properties_path"
    "  see: docs/build-guide.md (Application ID の設定)"
  )
fi

if [[ ! -f "$key_properties_path" ]]; then
  preflight_errors+=(
    "[missing] $key_properties_path"
    "  fix: cp android/key.properties.example $key_properties_path && chmod 600 $key_properties_path && \$EDITOR $key_properties_path"
    "  see: docs/build-guide.md (リリース署名の設定)"
  )
fi

if [[ -z "${ANDROID_ADI_REGISTRATION_PUBLIC_CONTENT_FILE:-}" ]]; then
  preflight_errors+=(
    "[missing] env ANDROID_ADI_REGISTRATION_PUBLIC_CONTENT_FILE"
    "  fix: ANDROID_ADI_REGISTRATION_PUBLIC_CONTENT_FILE=/path/to/adi-registration.properties make build-adi-verification"
    "  see: docs/build-guide.md (ADI Verification 用 APK)"
  )
elif [[ ! -f "$ANDROID_ADI_REGISTRATION_PUBLIC_CONTENT_FILE" ]]; then
  preflight_errors+=(
    "[missing] file pointed to by ANDROID_ADI_REGISTRATION_PUBLIC_CONTENT_FILE: $ANDROID_ADI_REGISTRATION_PUBLIC_CONTENT_FILE"
    "  fix: confirm the path exists and is readable"
  )
fi

# storeFile resolution depends on key.properties existing; only check if present.
if [[ -f "$key_properties_path" ]]; then
  resolved_store_file_path="$(resolve_store_file_path)"
  case "$resolved_store_file_path" in
    INVALID:storeFile-missing)
      preflight_errors+=(
        "[invalid] storeFile entry is missing in $key_properties_path"
        "  fix: add a 'storeFile=' line, e.g. 'storeFile=../keystore/release.jks'"
      )
      ;;
    INVALID:storeFile-dir-missing:*)
      missing_dir="${resolved_store_file_path#INVALID:storeFile-dir-missing:}"
      preflight_errors+=(
        "[invalid] storeFile directory does not exist: $missing_dir"
        "  fix: create the directory or correct the storeFile path in $key_properties_path"
      )
      ;;
    *)
      if [[ ! -f "$resolved_store_file_path" ]]; then
        preflight_errors+=(
          "[missing] keystore: $resolved_store_file_path"
          "  fix: place the release keystore at the path above, or run keytool to generate one"
          "  see: docs/build-guide.md (キーストアの生成)"
        )
      fi
      ;;
  esac
fi

if [[ -f "$asset_path" ]]; then
  preflight_errors+=(
    "[conflict] $asset_path already exists"
    "  fix: rm '$asset_path' (this script generates it freshly each run)"
  )
fi

if (( ${#preflight_errors[@]} > 0 )); then
  echo "build-adi-verification: prerequisites are not ready." >&2
  echo "" >&2
  printf '%s\n' "${preflight_errors[@]}" >&2
  echo "" >&2
  echo "Resolve the items above and re-run 'make build-adi-verification'." >&2
  exit 1
fi

# Cleanup state, indirected through a function so the trap body stays short
# and the intent of each phase is named rather than re-listed in three traps.
# - asset_path: always remove (it is generated each run, must not leak into
#   other builds where guard-no-adi-registration-asset.sh would block them)
# - release_apk_path: remove only while the APK has not yet been promoted
#   to the verification output path; otherwise we'd delete the artifact we
#   just built
# - apk_listing: tempfile from mktemp, always remove if set
asset_path_to_clean="$asset_path"
release_apk_to_clean="$release_apk_path"
apk_listing=""
cleanup() {
  rm -f "$asset_path_to_clean"
  [[ -n "$release_apk_to_clean" ]] && rm -f "$release_apk_to_clean"
  [[ -n "$apk_listing" ]] && rm -f "$apk_listing"
}
trap cleanup EXIT

mkdir -p "$(dirname "$asset_path")"
cp "$ANDROID_ADI_REGISTRATION_PUBLIC_CONTENT_FILE" "$asset_path"

flutter build apk --release --target-platform android-arm64 --obfuscate --split-debug-info=build/debug-info

apk_listing="$(mktemp)"
if ! unzip -l "$release_apk_path" >"$apk_listing" 2>/dev/null; then
  echo "Failed to read built APK at $release_apk_path." >&2
  exit 1
fi
if ! grep -q "assets/adi-registration.properties" "$apk_listing"; then
  echo "Verification APK does not contain assets/adi-registration.properties." >&2
  exit 1
fi

# Promote the verified APK and tell the cleanup to leave it alone.
mv -f "$release_apk_path" "$verification_output_path"
release_apk_to_clean=""
echo "Built verification APK: $verification_output_path"
