# Issue #39: VOICEVOX Core JNI ブリッジ基盤

## Goal

VOICEVOX Core 0.16.2 の Android 用共有ライブラリ (.so) をプロジェクトに配置し、Kotlin から JNI 経由で呼び出せる基盤を構築する。
この Issue では「ビルドが通り、ライブラリがロードでき、JNI 関数がリンクする」ところまでが目標（仕様の Step A に対応）。

## Scope

### バージョン固定

- `voicevox_core` は **0.16.2 に固定**
- `libvoicevox_core.so` と `voicevox_core.h` は **同じ release ZIP 由来**にする
- 開発中に別バージョンのヘッダと `.so` を混ぜない
- 理由: 0.16 系は API 変更が入っており、ヘッダとバイナリがずれると JNI 層で事故する

### 配布物の配置

0.16 系の CHANGELOG では、リリース内容物の配置が `include/voicevox_core.h` と `lib/` 配下に変更されている。unzip 後の構成を確認し配置する。

```
android/src/main/
  cpp/
    CMakeLists.txt
    voicevox_jni.cpp          ← JNI スケルトン
    include/
      voicevox_core.h         ← 0.16.2 ZIP 由来
  jniLibs/
    arm64-v8a/
      libvoicevox_core.so     ← 0.16.2 ZIP 由来
    x86_64/
      libvoicevox_core.so     ← 0.16.2 ZIP 由来
```

配置時に確認すべき項目:
- `include/voicevox_core.h` が存在するか
- `lib/` 配下の `.so` が ABI ごとに存在するか
- LICENSE ファイルの確認
- VERSION ファイルの確認

### Kotlin 側: NativeVoicevoxBridge

```kotlin
object NativeVoicevoxBridge {
    init { System.loadLibrary("voicevox_jni") }
    external fun nativeInitialize(openJtalkDictDir: String): Boolean
    external fun nativeLoadModel(vvmPath: String): Boolean
    external fun nativeIsModelLoaded(speakerId: Int): Boolean
    external fun nativeTts(
        text: String, speakerId: Int,
        speedScale: Float, pitchScale: Float,
        intonationScale: Float, volumeScale: Float,
        prePhonemeLength: Float, postPhonemeLength: Float
    ): ByteArray?
    external fun nativeRelease()
}
```

JNI 境界を固定する理由: 0.16 系は今後も周辺 API が動く可能性があるが、この境界を固定すれば Kotlin 側への影響を閉じ込められる。

### C++ 側: スケルトン

- `voicevox_jni.cpp` に全 JNI 関数のスケルトン（TODO 付き）を配置
- `#include "voicevox_core.h"` が通ること
- JNI 文字列変換ヘルパー (`JStringToString`) を実装

### CMake

- `voicevox_jni` を SHARED ライブラリとしてビルド
- `voicevox_core` ヘッダの include パス設定
- `libvoicevox_core.so` のリンク

### Gradle

- `build.gradle.kts` に NDK / CMake 設定追加
- ABI フィルタ: `arm64-v8a`, `x86_64`
- `jniLibs.useLegacyPackaging = true`

## Non-scope

- C++ 側の本実装（Issue #40）
- OpenJTalk 辞書の assets 配置（Issue #42）
- VVM モデルの配置（Issue #42）
- VoicevoxEngineImpl の Kotlin 実装（Issue #42）

## Dependencies

- なし（Issue #32 と並行可能）
- ただし **.so ファイルのダウンロード** はオーナーの手動作業が必要

## Acceptance Criteria

1. `libvoicevox_core.so` が `jniLibs` の `arm64-v8a` と `x86_64` に配置されている
2. `voicevox_core.h` が `src/main/cpp/include/` に配置されている
3. `.so` と `.h` が同一バージョン (0.16.2) の ZIP 由来である
4. CMake ビルドが通り、`libvoicevox_jni.so` が生成される
5. `#include "voicevox_core.h"` がコンパイルエラーなく通る
6. Android 実機/エミュレータで `System.loadLibrary("voicevox_jni")` が成功する（`UnsatisfiedLinkError` なし）
7. `nativeInitialize()` を呼んでも即クラッシュしない（スケルトンなので何もしないが、リンクは通る）
8. Gradle ビルドが成功する

## 失敗パターンと対処

### `.so` 読み込み失敗 (`UnsatisfiedLinkError`)

- ABI が合っているか確認
- `jniLibs` のディレクトリ配置が正しいか確認
- `voicevox_jni` → `voicevox_core` の依存リンクが正しいか確認

## Test Expectations

- **統合テスト（手動確認）**:
  - Android 実機/エミュレータでライブラリロード成功
  - JNI リンクエラーなし
- **自動テストは困難**: JNI のテストには実機/エミュレータが必要

## AI 実装適性

- **AI 実装に部分的に向いている**: ファイル配置と CMake 設定は機械的だが、.so ファイル自体はダウンロードが必要
- **人間承認が必要な論点**:
  - VOICEVOX Core バージョン確定（Q1: 0.16.2 でよいか）
  - .so ファイルの入手元と配置手順（人間が ZIP をダウンロード・展開する必要あり）
  - ライセンス確認（Q3）
  - 0.16.2 の実際のヘッダ内容に合わせた JNI 関数名の確認

## Implementation Notes

- ダウンロード元: GitHub Releases `voicevox_core-android-arm64-0.16.2.zip` / `voicevox_core-android-x86_64-0.16.2.zip`
- JNI 関数名のマングリング: パッケージ名のドット→アンダースコア、アンダースコア→`_1`
- この Issue は**オーナーの手動作業（.so ダウンロード・配置）** が先行して必要
