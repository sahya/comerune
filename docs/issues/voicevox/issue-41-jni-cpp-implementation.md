# Issue #41: voicevox_jni.cpp C++ 本実装

## Goal

Issue 08b-prep でリポジトリに配置された `voicevox_core.h` を読み、`voicevox_jni.cpp` の TODO を埋めて VOICEVOX Core を実際に呼び出す C++ コードを完成させる。
固定テキスト「こんにちは」で WAV バイト列が返るところまでが目標。

## 前提条件（Issue #40 の成果物）

この Issue を着手する前に、以下がリポジトリに存在すること:

- `android/src/main/cpp/include/voicevox_core.h` — 0.16.2 のヘッダ
- `android/src/main/jniLibs/arm64-v8a/libvoicevox_core.so`
- `android/src/main/jniLibs/x86_64/libvoicevox_core.so`
- Q13 / Q14 / Q15 の回答メモ
- OpenJTalk 辞書が assets に配置済み
- VVM が assets に配置済み

## Scope

### 実装方針

**ヘッダファイル (`voicevox_core.h`) を一次情報として読み、そこに記載された関数名・構造体名を正確に使う。**
古いブログ記事やサンプルコードを参照しない。

### `nativeInitialize()` の実装

`voicevox_core.h` を読んで以下を実装:

1. `openJtalkDictDir` を `std::string` に変換
2. OpenJTalk オブジェクトの生成（辞書パスを指定）
3. Synthesizer の生成
4. 成功時のみ `g_initialized = true`
5. 失敗時は `false` を返す
6. ログ: start/end、辞書パス、成功/失敗

### `nativeLoadModel()` の実装

1. VVM パスを受け取る
2. VoiceModelFile 相当を読み込む
3. Synthesizer に model を load する
4. ログ: VVM パス、成功/失敗

### `nativeIsModelLoaded()` の実装

1. speakerId (style id) のロード状態を確認
2. ログ: speakerId、結果

### `nativeTts()` の実装

Q13 の回答に基づき、一発 TTS または audio_query 方式で実装する。

**入力検証**:
- `g_initialized == true`
- `text` が空でない
- モデルが load 済み

**合成**:
- options 生成
- speed / pitch / intonation / volume / pre/post phoneme を設定
- synthesis 実行

**戻り値**:
- `std::vector<uint8_t>` または voicevox_core が返すバッファを `jbyteArray` にコピー
- 0 byte の WAV を返さない
- 失敗時は `nullptr`
- voicevox_core が確保したメモリの解放を忘れない

**ログ**:
- 入力文字列長、style id、生成 wav size、失敗時の関数名とエラーコード

### `nativeRelease()` の実装

- Synthesizer の解放
- OpenJTalk オブジェクトの解放
- その他 voicevox_core リソースの解放
- `g_initialized = false`

### JNI 層の安全対策

- 複数スレッドからの同時合成を防ぐ（`std::mutex` で逐次化）
- null / 空文字列の入力で crash しない
- voicevox_core のエラーコードを取得してログに出す

## Non-scope

- `create_audio_query` 方式への対応（Q13 で方式2が選ばれた場合を除く）
- 複数話者の動的切替
- パフォーマンス最適化
- Kotlin 側のラッパー実装（Issue 09）

## Dependencies

- Issue #39（JNI ブリッジ基盤: スケルトン、CMake、ビルド通過）
- Issue #40（ヘッダ配置、設計判断確定、assets 配置）

## Acceptance Criteria

1. `nativeInitialize()` が辞書パスを受け取り、成功/失敗を返す
2. `nativeLoadModel()` が VVM パスを受け取り、成功/失敗を返す
3. `nativeTts("こんにちは", ...)` が空でない WAV バイト列を返す
4. 返される WAV が有効（サイズ > 44 bytes、RIFF ヘッダあり）
5. 空テキストで `nullptr` が返る（クラッシュしない）
6. 未初期化状態で `nativeTts()` を呼んでも `nullptr` が返る（クラッシュしない）
7. Logcat に初期化・合成のログが出力される
8. `nativeRelease()` 後に内部状態がリセットされる
9. voicevox_core が確保したメモリが正しく解放されている

## 先に潰すべき失敗パターン

| パターン | 症状 | 確認 |
|---|---|---|
| 辞書パス不正 | initialize 失敗 | 絶対パスか、ディレクトリが存在するか |
| VVM ロード失敗 | initialize は通るが synthesize 失敗 | VVM の存在確認、対象 style の含有確認 |
| 空 WAV | エラーなしに見えるが音が出ない | WAV サイズ > 44 byte |
| メモリリーク | 長時間使用でメモリ増加 | voicevox_core のバッファ解放漏れ |

## Test Expectations

- **統合テスト（実機、手動確認、必須）**:
  - Android 実機 arm64 で `nativeInitialize()` → `nativeLoadModel()` → `nativeTts("こんにちは")` → WAV 取得
  - WAV バイト列のサイズが 44 bytes を超えること
  - Logcat でログが確認できること
  - `nativeRelease()` 後に再度 `nativeInitialize()` できること
- **自動テストは困難**: C++ / JNI コードは実機環境が必要

## AI 実装適性

- **AI 実装に向いている（前提条件を満たす場合）**: ヘッダファイルがリポジトリにあれば、AI はそれを読んで正確な C++ コードを生成できる
- **人間承認ポイント**:
  - 生成された C++ コードがヘッダの API を正しく使っているか
  - メモリ解放が正しいか
  - 実機での動作確認（AI では実行できない）

## Implementation Notes

- **最重要**: `voicevox_core.h` を読んでから書き始める。推測で関数名を書かない
- ログは `__android_log_print(ANDROID_LOG_INFO, "VoicevoxJNI", ...)` を使用
- 実装順のおすすめ（仕様書記載）:
  1. `nativeInitialize()` を通す
  2. `nativeLoadModel()` を通す
  3. `nativeTts()` で固定テキスト `"テストです"` を WAV 化
  4. Kotlin 側で byte size を確認
  5. MediaPlayer で再生
  6. その後で `submitComment()` とつなぐ
- ニコニココメント連携より先に、**固定文字列で音が出ることを証明する**
