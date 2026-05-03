#!/usr/bin/env bash
# Fetch fonts used by scripts/google_play/generate-feature-graphic.py.
# Fonts are stored alongside this script under fonts/ and intentionally
# git-ignored to avoid redistributing third-party font binaries via this
# repository.
#
# Source: Zen Maru Gothic (Google Fonts, SIL Open Font License 1.1)
# https://github.com/googlefonts/zen-marugothic
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="$SCRIPT_DIR/fonts"
mkdir -p "$DEST"

base="https://raw.githubusercontent.com/googlefonts/zen-marugothic/main/fonts/ttf"
for f in ZenMaruGothic-Medium.ttf ZenMaruGothic-Bold.ttf; do
  if [ -s "$DEST/$f" ]; then
    echo "[skip] $f already present"
  else
    echo "[fetch] $f"
    curl -sSLfo "$DEST/$f" "$base/$f"
  fi
done

echo "Fonts ready under $DEST"
