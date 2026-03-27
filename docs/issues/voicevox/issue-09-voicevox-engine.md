# Issue 09: VoicevoxEngineImpl 実装

## Goal

VOICEVOX Core の初期化・音声合成・解放を行う `VoicevoxEngineImpl` を本実装する。
assets から辞書と VVM を展開し、JNI ブリッジ経由で合成を実行する。

## Scope

### インターフェース

```kotlin
interface VoicevoxEngine {
    suspend fun initialize(config: VoicevoxConfig): Result<Unit>
    suspend fun synthesize(request: SpeechRequest): Result<WavSynthesisResult>
    fun isReady(): Boolean
    fun currentState(): TtsEngineState
    fun release()
}
```

### 実装クラス: `VoicevoxEngineImpl`

#### 初期化処理（仕様 Section 4.4）

1. assets から OpenJTalk 辞書を内部ストレージへ展開
2. assets から VVM モデルファイルを内部ストレージへ展開
3. `NativeVoicevoxBridge.nativeInitialize()` で Core 初期化
4. `NativeVoicevoxBridge.nativeLoadModel()` でモデルロード
5. 状態を `READY` に遷移

#### 合成処理（仕様 Section 4.6-4.7）

1. 状態チェック（初期化済み・READY であること）
2. テキストの空チェック
3. `NativeVoicevoxBridge.nativeTts()` で WAV バイト列を取得
4. `WavSynthesisResult` として返却
5. 失敗時: 当該コメントのみ破棄、一時的失敗なら READY に戻す

#### 状態管理

- UNINITIALIZED → INITIALIZING → READY ⇄ SYNTHESIZING → ERROR

### assets 配置

- `assets/open_jtalk_dic_utf_8-1.11/` — OpenJTalk 辞書
- `assets/voice/default.vvm` — デフォルト VVM モデル

### エラーリカバリ（仕様 Section 8 の注意点）

- 合成の一時的失敗では `READY` に戻す（永続 ERROR にしない）
- 初期化失敗のみ `ERROR` 扱い

## Non-scope

- JNI ブリッジのセットアップ（Issue 08）
- `voicevox_jni.cpp` の C++ 本実装（Issue 08 のスケルトンに TODO を埋める作業）
- 複数話者の動的切替
- VVM のダウンロード機能
- エラー連続時の自動再初期化（SpeechController の責務）

## Dependencies

- Issue 01（データモデル: VoicevoxConfig, SpeechRequest, WavSynthesisResult, TtsEngineState）
- Issue 08（JNI ブリッジ基盤: NativeVoicevoxBridge, .so, CMake）

## Acceptance Criteria

1. `initialize()` が成功すると `currentState() == READY` になる
2. `synthesize()` が短文テキストに対して空でない WAV バイト列を返す
3. 未初期化状態での `synthesize()` が `Result.failure` を返す
4. 空テキストの `synthesize()` が `Result.failure` を返す
5. `release()` 後に `currentState() == UNINITIALIZED` になる
6. 合成失敗後に `currentState()` が `READY` に戻る（永続 ERROR にならない）
7. assets 展開が初回のみ実行される（2回目以降はスキップ）

## Test Expectations

- **統合テスト（実機必要）**:
  - 初期化→合成→解放の一連フロー
  - 合成結果の WAV ヘッダ検証（RIFF ヘッダの存在）
- **単体テスト（モック使用）**:
  - 状態遷移の検証（UNINITIALIZED → READY → SYNTHESIZING → READY）
  - エラー時の状態復帰

## AI 実装適性

- **AI 実装に部分的に向いている**: Kotlin 側のラッパーは書けるが、C++ 側の TODO 埋めは VOICEVOX Core API の実際のヘッダに依存
- **人間承認が必要な論点**:
  - assets に配置する辞書と VVM の入手手順
  - 初期話者 ID の確定（Q4）
  - VVM ライセンス確認（Q3）
  - C++ 側の `voicevox_core` API 呼び出しの正確さ（0.16 系の実ヘッダに合わせる必要）

## Implementation Notes

- 仕様書 Section 4 (VoicevoxEngineImpl 本実装雛形) のコードをベースにする
- assets 展開は `Dispatchers.IO` で実行する（ファイル I/O のため）
- 辞書展開は再帰コピーが必要（ディレクトリ構造を維持）
- 初回展開後は `File.exists()` チェックでスキップする
