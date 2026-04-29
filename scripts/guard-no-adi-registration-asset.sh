#!/usr/bin/env bash
set -euo pipefail

readonly asset_path="android/app/src/main/assets/adi-registration.properties"

if [[ -f "$asset_path" ]]; then
  echo "Verification-only asset $asset_path must not be present for standard release builds."
  exit 1
fi
