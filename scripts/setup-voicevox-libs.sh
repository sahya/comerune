#!/usr/bin/env bash
# VOICEVOX Core + ONNX Runtime ネイティブライブラリのダウンロードと配置
# Usage: ./scripts/setup-voicevox-libs.sh
set -euo pipefail

VOICEVOX_CORE_VERSION="0.16.2"
ONNXRUNTIME_VERSION="1.17.3"

JNILIBS_DIR="android/app/src/main/jniLibs"
TMP_DIR="${TMPDIR:-/tmp}/voicevox-setup"

ABIS=("arm64-v8a:arm64" "x86_64:x86_64")

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

mkdir -p "$TMP_DIR"

echo "=== VOICEVOX ネイティブライブラリ セットアップ ==="

# --- VOICEVOX Core ---
for entry in "${ABIS[@]}"; do
  abi="${entry%%:*}"
  arch="${entry##*:}"
  dest="$JNILIBS_DIR/$abi"

  if [[ -f "$dest/libvoicevox_core.so" ]]; then
    echo "[skip] libvoicevox_core.so ($abi) already exists"
    continue
  fi

  echo "[download] voicevox_core $VOICEVOX_CORE_VERSION ($arch)..."
  gh release download "$VOICEVOX_CORE_VERSION" \
    --repo VOICEVOX/voicevox_core \
    --pattern "voicevox_core-android-${arch}-${VOICEVOX_CORE_VERSION}.zip" \
    --dir "$TMP_DIR" --clobber

  mkdir -p "$dest"
  unzip -o "$TMP_DIR/voicevox_core-android-${arch}-${VOICEVOX_CORE_VERSION}.zip" -d "$TMP_DIR" >/dev/null
  cp "$TMP_DIR/voicevox_core-android-${arch}-${VOICEVOX_CORE_VERSION}/lib/libvoicevox_core.so" "$dest/"
  echo "[ok] libvoicevox_core.so -> $dest/"
done

# --- ONNX Runtime ---
ONNX_ABIS=("arm64-v8a:arm64" "x86_64:x64")

for entry in "${ONNX_ABIS[@]}"; do
  abi="${entry%%:*}"
  arch="${entry##*:}"
  dest="$JNILIBS_DIR/$abi"

  if [[ -f "$dest/libvoicevox_onnxruntime.so" ]]; then
    echo "[skip] libvoicevox_onnxruntime.so ($abi) already exists"
    continue
  fi

  echo "[download] voicevox_onnxruntime $ONNXRUNTIME_VERSION ($arch)..."
  gh release download "voicevox_onnxruntime-${ONNXRUNTIME_VERSION}" \
    --repo VOICEVOX/onnxruntime-builder \
    --pattern "voicevox_onnxruntime-android-${arch}-${ONNXRUNTIME_VERSION}.tgz" \
    --dir "$TMP_DIR" --clobber

  tar xzf "$TMP_DIR/voicevox_onnxruntime-android-${arch}-${ONNXRUNTIME_VERSION}.tgz" -C "$TMP_DIR"
  mkdir -p "$dest"
  cp "$TMP_DIR/voicevox_onnxruntime-android-${arch}-${ONNXRUNTIME_VERSION}/lib/libvoicevox_onnxruntime.so" "$dest/"
  echo "[ok] libvoicevox_onnxruntime.so -> $dest/"
done

echo ""
echo "=== 配置結果 ==="
ls -lh "$JNILIBS_DIR"/*/lib*.so 2>/dev/null || echo "(no .so files found)"
echo ""
echo "Done. 'make build' or 'make build-clean' でビルドできます。"