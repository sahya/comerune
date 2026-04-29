#!/usr/bin/env bash
set -euo pipefail

# Verify that android/key.properties actually unlocks the keystore it points
# to. This catches the failure mode where key.properties is present and
# syntactically complete (so build.gradle.kts treats it as valid), but the
# password is wrong — Gradle would then silently fall back to debug signing
# and ship a "release" APK signed with the Android default debug key.
#
# The check is intentionally a no-op when key.properties is absent (debug
# signing fallback is the documented local-development behaviour).

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

readonly key_properties_path="android/key.properties"

if [[ ! -f "$key_properties_path" ]]; then
  # No release credentials configured locally — debug fallback is the
  # documented behaviour, not an error.
  exit 0
fi

# Read keys defensively: trim trailing whitespace and ignore comment lines.
read_property() {
  local key="$1"
  sed -n "s/^${key}=//p" "$key_properties_path" | tail -n 1 | tr -d '\r'
}

store_password="$(read_property storePassword)"
key_password="$(read_property keyPassword)"
key_alias="$(read_property keyAlias)"
store_file="$(read_property storeFile)"

errors=()

if [[ -z "$store_password" || -z "$key_password" || -z "$key_alias" || -z "$store_file" ]]; then
  errors+=(
    "[invalid] $key_properties_path is missing one of storePassword/keyPassword/keyAlias/storeFile."
    "  fix: see android/key.properties.example and docs/build-guide.md"
  )
fi

# Detect the example placeholders before invoking keytool so the message is
# explicit — keytool would otherwise just say "password was incorrect".
if [[ "$store_password" == "your_store_password" || "$key_password" == "your_key_password" ]]; then
  errors+=(
    "[invalid] $key_properties_path still contains placeholder values from key.properties.example."
    "  fix: edit $key_properties_path and set the real keystore passwords"
    "  see: docs/build-guide.md (リリース署名の設定)"
  )
fi

# storeFile is resolved relative to android/app/ (Gradle convention) when not
# absolute. Mirror the resolver in build-android-developer-verification-apk.sh.
resolve_store_file_path() {
  if [[ "$store_file" = /* ]]; then
    printf '%s\n' "$store_file"
    return
  fi
  local candidate_dir="$repo_root/android/app/$(dirname "$store_file")"
  local candidate_name
  candidate_name="$(basename "$store_file")"
  if [[ ! -d "$candidate_dir" ]]; then
    printf '%s\n' "INVALID:dir-missing:$candidate_dir"
    return
  fi
  (cd "$candidate_dir" && printf '%s/%s\n' "$(pwd -P)" "$candidate_name")
}

if [[ -n "$store_file" ]]; then
  resolved_store_file="$(resolve_store_file_path)"
  case "$resolved_store_file" in
    INVALID:dir-missing:*)
      missing_dir="${resolved_store_file#INVALID:dir-missing:}"
      errors+=(
        "[invalid] storeFile directory does not exist: $missing_dir"
        "  fix: correct the storeFile path in $key_properties_path"
      )
      ;;
    *)
      if [[ ! -f "$resolved_store_file" ]]; then
        errors+=(
          "[missing] keystore: $resolved_store_file"
          "  fix: place the release keystore at the path above, or run keytool to generate one"
          "  see: docs/build-guide.md (キーストアの生成)"
        )
      fi
      ;;
  esac
fi

if (( ${#errors[@]} > 0 )); then
  echo "verify-release-keystore: keystore configuration is not usable." >&2
  echo "" >&2
  printf '%s\n' "${errors[@]}" >&2
  echo "" >&2
  echo "Resolve the items above before running 'make build-release'." >&2
  exit 1
fi

# Decisive check: actually open the keystore with the configured password
# and confirm the alias resolves. This is the step that would have caught
# the past silent debug-signing fallback. We intentionally suppress stdout
# because '-list' prints certificate details that include fingerprints.
if ! command -v keytool >/dev/null 2>&1; then
  # Most local Android development setups have keytool via the JDK that
  # ships with Android Studio / mise. If you genuinely cannot install it,
  # set KEYSTORE_VERIFY_ALLOW_SKIP=1 to acknowledge that you are bypassing
  # the decisive check. CI environments always have JDK installed before
  # this script runs, so reaching here on CI is a configuration bug.
  if [[ "${KEYSTORE_VERIFY_ALLOW_SKIP:-}" == "1" ]]; then
    echo "verify-release-keystore: keytool not on PATH; skipping (KEYSTORE_VERIFY_ALLOW_SKIP=1)." >&2
    exit 0
  fi
  cat <<'EOF' >&2
verify-release-keystore: keytool is not on PATH and is required for the
decisive keystore check. Without keytool we cannot detect a wrong password
that would silently fall back to debug signing.

Fixes:
  - install a JDK (Android Studio bundles one) and re-run
  - or set KEYSTORE_VERIFY_ALLOW_SKIP=1 to bypass the check explicitly
    (only do this on machines where you understand the trade-off)
EOF
  exit 1
fi

# IMPORTANT: never pass the keystore password as a CLI argument — it would
# end up visible in /proc/<pid>/cmdline and `ps -ef` to any process running
# under the same UID on the same host. Use -storepass:env, which makes
# keytool read the password from a named environment variable instead.
#
# We redirect both stdout AND stderr to the same buffer because keytool
# emits its "keystore password was incorrect" diagnostic on stdout, not
# stderr. On success we discard the buffer (it would otherwise dump the
# certificate fingerprint into our logs).
keytool_output="$(mktemp)"
trap 'rm -f "$keytool_output"' EXIT
set +e
KEYSTORE_VERIFY_PASS="$store_password" \
  keytool -list \
    -keystore "$resolved_store_file" \
    -storepass:env KEYSTORE_VERIFY_PASS \
    -alias "$key_alias" \
    >"$keytool_output" 2>&1
keytool_exit=$?
set -e
unset KEYSTORE_VERIFY_PASS

if (( keytool_exit != 0 )); then
  cat <<EOF >&2
verify-release-keystore: failed to open the keystore with the configured password / alias.

  keystore: $resolved_store_file
  alias:    $key_alias

This is the failure mode that produces a silently debug-signed "release" APK.
Fix one of:
  - storePassword in $key_properties_path (must match the keystore password)
  - keyAlias in $key_properties_path (must match an alias in the keystore)
  - the keystore file itself (regenerate or restore from backup)

keytool diagnostic:
EOF
  # Forward keytool's diagnostic. We try to extract just the lines that
  # look like keytool's own error (to avoid accidentally dumping a
  # certificate fingerprint into logs in unusual cases), and fall back to
  # the full buffer if the heuristic finds nothing.
  filtered_output="$(grep -E '^(keytool error|java\.|\s+at )' "$keytool_output" || true)"
  if [[ -n "$filtered_output" ]]; then
    sed 's/^/  /' <<<"$filtered_output" >&2
  else
    sed 's/^/  /' "$keytool_output" >&2
  fi
  exit 1
fi

# keytool -list with -alias also implicitly verifies the alias exists, so
# reaching here means: keystore opens AND alias is present. The keyPassword
# is verified by Gradle at signing time; we cannot validate it from keytool
# without invoking a sign operation, but mismatch there fails the build
# loudly rather than silently — which is acceptable.

echo "verify-release-keystore: ok (alias=$key_alias)"
