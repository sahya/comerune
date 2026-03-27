# Issue #42: VoicevoxEngineImpl 実装

## Goal

VOICEVOX Core の初期化・音声合成・解放を行う `VoicevoxEngineImpl` (Kotlin 側ラッパー) を本実装する。
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

1. assets から OpenJTalk 辞書を `filesDir` へ展開（初回のみ）
2. assets から VVM モデルファイルを `filesDir` へ展開（初回のみ）
3. `NativeVoicevoxBridge.nativeInitialize()` で Core 初期化
4. `NativeVoicevoxBridge.nativeLoadModel()` でモデルロード
5. 状態を `READY` に遷移

#### 合成処理（仕様 Section 4.6-4.7）

1. 状態チェック（初期化済み・READY であること）
2. テキストの空チェック
3. `NativeVoicevoxBridge.nativeTts()` で WAV バイト列を取得
4. `WavSynthesisResult` として返却

#### 状態管理

- UNINITIALIZED → INITIALIZING → READY ⇄ SYNTHESIZING → ERROR

#### エラーリカバリ（仕様 Section 8 の注意点）

- 合成の一時的失敗では `READY` に戻す（永続 ERROR にしない）
- 初期化失敗のみ `ERROR` 扱い

### assets 配置

- `assets/open_jtalk_dic_utf_8-1.11/` — OpenJTalk 辞書
- `assets/voice/default.vvm` — デフォルト VVM モデル

### 防御コーディング（追加仕様 Section 8）

#### `initialize()` に追加する防御

- `dictDir` の exists チェック（展開後に存在するか）
- `vvmFile` の exists チェック
- 失敗時にパスを含めてログ出力（デバッグ用）

#### `synthesize()` に追加する防御

- `wavBytes.isNotEmpty()` チェック
- 小さすぎるサイズ（WAV ヘッダ 44 bytes 以下）を reject
- 連続失敗回数カウント（将来の自動再初期化の基盤）

#### `release()` に追加する防御

- 二重解放を許容する（2回呼ばれても安全）
- release 後に state を確実に `UNINITIALIZED` にする

### 失敗パターンへの対処

| パターン | 症状 | 確認項目 |
|---|---|---|
| 辞書パス不正 | initialize 失敗 | assets 展開先がディレクトリか、絶対パスか |
| VVM ロード失敗 | initialize は通るが synthesize 失敗 | VVM 存在確認、対象 style 含有確認 |
| 空 WAV | エラーなしに見えるが音が出ない | WAV サイズ > 44 byte、ヘッダ検証 |

## Non-scope

- JNI ブリッジのセットアップ（#39）
- `voicevox_jni.cpp` の C++ 本実装（#40）
- 複数話者の動的切替
- VVM のダウンロード機能
- エラー連続時の自動再初期化（SpeechController 側の責務）
- 方式2 (`create_audio_query`) への移行

## Dependencies

- #32（データモデル: VoicevoxConfig, SpeechRequest, WavSynthesisResult, TtsEngineState）
- #39（JNI ブリッジ基盤: NativeVoicevoxBridge, .so, CMake）
- #41（C++ 本実装: `nativeInitialize` / `nativeLoadModel` / `nativeTts` が動作すること）

## Acceptance Criteria

1. `initialize()` が成功すると `currentState() == READY` になる
2. `synthesize()` が短文テキストに対して空でない WAV バイト列を返す
3. 返される WAV のサイズが 44 bytes を超える
4. 未初期化状態での `synthesize()` が `Result.failure` を返す
5. 空テキストの `synthesize()` が `Result.failure` を返す
6. `release()` 後に `currentState() == UNINITIALIZED` になる
7. `release()` を2回呼んでもクラッシュしない
8. 合成失敗後に `currentState()` が `READY` に戻る（永続 ERROR にならない）
9. assets 展開が初回のみ実行される（2回目以降はスキップ）
10. 初期化失敗時にログにパス情報が出力される

### 実装完了の最低条件（仕様に記載）

以下が満たせれば次の Issue に進める:
- Android 実機 arm64 で起動する
- `initialize()` 成功
- `nativeLoadModel()` 成功
- `"こんにちは"` を1件だけ合成できる
- WAV byte array が返る

## Test Expectations

- **統合テスト（実機必要）**:
  - 初期化→合成→解放の一連フロー
  - 合成結果の WAV ヘッダ検証（RIFF ヘッダの存在、サイズ > 44 bytes）
- **単体テスト（モック使用）**:
  - 状態遷移の検証（UNINITIALIZED → READY → SYNTHESIZING → READY）
  - エラー時の状態復帰
  - 二重 release の安全性
  - 空 WAV / 小さすぎる WAV の reject

## AI 実装適性

- **AI 実装に部分的に向いている**: Kotlin ラッパーは書けるが、assets 配置と C++ 側は人間作業が先行
- **人間承認が必要な論点**:
  - assets に配置する辞書と VVM の入手手順
  - 初期話者 ID の確定（Q4）
  - VVM ライセンス確認（Q3）
  - speakerId/styleId の対応（Q14）

## Implementation Notes

- 仕様書 Section 4 (VoicevoxEngineImpl 本実装雛形) のコードをベースにする
- assets 展開は `Dispatchers.IO` で実行（ファイル I/O のため）
- 辞書展開は再帰コピーが必要（ディレクトリ構造を維持）
- 初回展開後は `File.exists()` チェックでスキップ
- 実装の優先順序: **ニコニココメント連携より先に、固定文字列で音が出ることを証明する**（仕様の推奨）
