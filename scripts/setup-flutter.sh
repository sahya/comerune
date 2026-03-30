#!/usr/bin/env bash
# Flutter SDK setup script for Claude Code sessions.
# Installs Flutter to ~/tools/flutter if not present,
# then runs flutter pub get for the project.
#
# This script is idempotent - safe to run multiple times.

set -euo pipefail

FLUTTER_DIR="$HOME/tools/flutter"
FLUTTER_BIN="$FLUTTER_DIR/bin/flutter"
FLUTTER_CHANNEL="stable"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ---------- helpers ----------
info()  { echo "[flutter-setup] $*"; }
error() { echo "[flutter-setup] ERROR: $*" >&2; }

# ---------- skip if already installed ----------
if [ -x "$FLUTTER_BIN" ]; then
  info "Flutter already installed: $("$FLUTTER_BIN" --version 2>/dev/null | head -1)"
  export PATH="$FLUTTER_DIR/bin:$PATH"

  # Ensure dependencies are resolved
  if [ -f "$PROJECT_DIR/pubspec.yaml" ]; then
    cd "$PROJECT_DIR"
    info "Running flutter pub get..."
    "$FLUTTER_BIN" pub get --no-example 2>&1 | tail -3
  fi
  exit 0
fi

# ---------- install ----------
info "Installing Flutter SDK ($FLUTTER_CHANNEL) to $FLUTTER_DIR ..."
mkdir -p "$HOME/tools"

# Download
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.29.3-stable.tar.xz"
ARCHIVE="/tmp/flutter_linux.tar.xz"

if [ ! -f "$ARCHIVE" ]; then
  info "Downloading Flutter SDK..."
  curl -fSL --retry 3 --retry-delay 5 -o "$ARCHIVE" "$FLUTTER_URL"
fi

# Extract
info "Extracting..."
tar -xf "$ARCHIVE" -C "$HOME/tools"
rm -f "$ARCHIVE"

# Verify
if [ ! -x "$FLUTTER_BIN" ]; then
  error "Installation failed - $FLUTTER_BIN not found"
  exit 1
fi

export PATH="$FLUTTER_DIR/bin:$PATH"

# Fix git safe directory issue (Flutter SDK is extracted with different owner)
git config --global --add safe.directory "$FLUTTER_DIR" 2>/dev/null || true

info "Flutter installed successfully:"
"$FLUTTER_BIN" --version

# ---------- precache & pub get ----------
info "Running flutter precache..."
"$FLUTTER_BIN" precache --no-ios --no-macos --no-windows --no-web --no-fuchsia --no-linux-desktop 2>&1 | tail -3

if [ -f "$PROJECT_DIR/pubspec.yaml" ]; then
  cd "$PROJECT_DIR"
  info "Running flutter pub get..."
  "$FLUTTER_BIN" pub get --no-example 2>&1 | tail -3
fi

# ---------- git config to ignore Flutter dir ----------
info "Setup complete. Flutter is ready at $FLUTTER_DIR"
