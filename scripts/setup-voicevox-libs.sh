#!/usr/bin/env bash
# VOICEVOX Core + ONNX Runtime ネイティブライブラリのダウンロードと配置
# Usage: ./scripts/setup-voicevox-libs.sh
#
# ダウンロードしたアーカイブは展開前に SHA-256 を照合し、一致しなければ
# 削除して異常終了する（期待値が未登録のアーカイブも同様に失敗させる）。
set -euo pipefail

# バージョンを上げるときは、下の expected_sha256 も必ず同時に更新すること。
# 新しいアーカイブの値は、公式 Release から取得したファイルに対して
# `sha256sum <file>`（macOS は `shasum -a 256 <file>`）で求める。
VOICEVOX_CORE_VERSION="0.16.2"
ONNXRUNTIME_VERSION="1.17.3"

# アーカイブのファイル名 → 期待する SHA-256。未登録の名前には何も出力しない。
# macOS 標準の bash 3.2 でも動くよう、連想配列ではなく case で持つ。
expected_sha256() {
  case "$1" in
    voicevox_core-android-arm64-0.16.2.zip)
      echo "3661b52a43c3d1cefb17c7147ea22d321132439896eef317f46cd6dfea76eef1" ;;
    voicevox_core-android-x86_64-0.16.2.zip)
      echo "f22cd0388c8ed55f59d3ee16258e7f74ffede8a02828b92ee3b1cd53ec7cbcaf" ;;
    voicevox_onnxruntime-android-arm64-1.17.3.tgz)
      echo "516a992cec029d4414260b602f38f388423517221ad5f81f0e1da4ada7104c60" ;;
    voicevox_onnxruntime-android-x64-1.17.3.tgz)
      echo "95f48afe11706476cedcea51b9b59f4f5dab3ec1e2f509fcf74a6230ee4b7d8b" ;;
  esac
}

# ファイルの SHA-256 を 16 進で出力する。sha256sum が無ければ shasum を使い、
# どちらも無ければ照合を省略せずに失敗する。
sha256_of() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    echo "[error] sha256sum も shasum も見つからないため、アーカイブを検証できません" >&2
    return 1
  fi
}

# アーカイブを期待値と照合する。不一致・期待値なしのときはファイルを削除して失敗する。
verify_archive() {
  local file="$1"
  local name
  name="$(basename "$file")"
  local expected
  expected="$(expected_sha256 "$name")"

  if [[ -z "$expected" ]]; then
    echo "[error] $name の期待 SHA-256 が未登録です（expected_sha256 を更新してください）" >&2
    rm -f "$file"
    return 1
  fi

  local actual
  if ! actual="$(sha256_of "$file")"; then
    rm -f "$file"
    return 1
  fi

  if [[ "$actual" != "$expected" ]]; then
    echo "[error] $name の SHA-256 が一致しません" >&2
    echo "        expected: $expected" >&2
    echo "        actual:   $actual" >&2
    rm -f "$file"
    return 1
  fi

  echo "[verify] $name sha256 OK"
}

main() {
  local JNILIBS_DIR="android/app/src/main/jniLibs"
  TMP_DIR="${TMPDIR:-/tmp}/voicevox-setup"

  local ABIS=("arm64-v8a:arm64" "x86_64:x86_64")

  cleanup() { rm -rf "$TMP_DIR"; }
  trap cleanup EXIT

  mkdir -p "$TMP_DIR"

  echo "=== VOICEVOX ネイティブライブラリ セットアップ ==="

  local entry abi arch dest archive

  # --- VOICEVOX Core ---
  for entry in "${ABIS[@]}"; do
    abi="${entry%%:*}"
    arch="${entry##*:}"
    dest="$JNILIBS_DIR/$abi"

    if [[ -f "$dest/libvoicevox_core.so" ]]; then
      echo "[skip] libvoicevox_core.so ($abi) already exists"
      continue
    fi

    archive="voicevox_core-android-${arch}-${VOICEVOX_CORE_VERSION}.zip"
    echo "[download] voicevox_core $VOICEVOX_CORE_VERSION ($arch)..."
    gh release download "$VOICEVOX_CORE_VERSION" \
      --repo VOICEVOX/voicevox_core \
      --pattern "$archive" \
      --dir "$TMP_DIR" --clobber

    verify_archive "$TMP_DIR/$archive"

    mkdir -p "$dest"
    unzip -o "$TMP_DIR/$archive" -d "$TMP_DIR" >/dev/null
    cp "$TMP_DIR/voicevox_core-android-${arch}-${VOICEVOX_CORE_VERSION}/lib/libvoicevox_core.so" "$dest/"
    echo "[ok] libvoicevox_core.so -> $dest/"
  done

  # --- ONNX Runtime ---
  local ONNX_ABIS=("arm64-v8a:arm64" "x86_64:x64")

  for entry in "${ONNX_ABIS[@]}"; do
    abi="${entry%%:*}"
    arch="${entry##*:}"
    dest="$JNILIBS_DIR/$abi"

    if [[ -f "$dest/libvoicevox_onnxruntime.so" ]]; then
      echo "[skip] libvoicevox_onnxruntime.so ($abi) already exists"
      continue
    fi

    archive="voicevox_onnxruntime-android-${arch}-${ONNXRUNTIME_VERSION}.tgz"
    echo "[download] voicevox_onnxruntime $ONNXRUNTIME_VERSION ($arch)..."
    gh release download "voicevox_onnxruntime-${ONNXRUNTIME_VERSION}" \
      --repo VOICEVOX/onnxruntime-builder \
      --pattern "$archive" \
      --dir "$TMP_DIR" --clobber

    verify_archive "$TMP_DIR/$archive"

    tar xzf "$TMP_DIR/$archive" -C "$TMP_DIR"
    mkdir -p "$dest"
    cp "$TMP_DIR/voicevox_onnxruntime-android-${arch}-${ONNXRUNTIME_VERSION}/lib/libvoicevox_onnxruntime.so" "$dest/"
    echo "[ok] libvoicevox_onnxruntime.so -> $dest/"
  done

  echo ""
  echo "=== 配置結果 ==="
  ls -lh "$JNILIBS_DIR"/*/lib*.so 2>/dev/null || echo "(no .so files found)"
  echo ""
  echo "Done. 'make build' or 'make build-clean' でビルドできます。"
}

# 直接実行されたときだけ main を動かす（source した場合は関数定義のみ読み込む）。
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
