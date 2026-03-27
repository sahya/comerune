# Issue 10: WAV 音声再生 (MediaPlayerWavPlayer)

## Goal

VOICEVOX Core が生成した WAV バイト列を Android 端末上で再生する。
初期実装は一時ファイル保存 + MediaPlayer 方式を採用する。

## Scope

### インターフェース

```kotlin
interface WavPlayer {
    suspend fun play(wavBytes: ByteArray): Result<Unit>
    suspend fun stop(): Result<Unit>
    fun isPlaying(): Boolean
    fun currentState(): PlayerState
    fun release()
}
```

### 実装クラス: `MediaPlayerWavPlayer`

#### 再生処理（仕様 Section 5.2 方式A）

1. WAV バイト列を一時ファイルに書き出し
2. `MediaPlayer` で一時ファイルを再生
3. 再生完了コールバック（`OnCompletionListener`）を待機
4. 完了後に一時ファイルを削除
5. `PlayerState` を `IDLE` に戻す

#### 停止処理

- `MediaPlayer.stop()` を呼ぶ
- `PlayerState` を `STOPPED` に遷移

#### 状態管理

- IDLE → PLAYING → IDLE (正常完了)
- PLAYING → STOPPED (手動停止)
- PLAYING → ERROR (再生失敗)

## Non-scope

- AudioTrack 方式（将来の改善版）
- Audio Focus 制御（Issue 11）
- 音量制御（SpeechSettings の volumeScale はエンジン側の合成パラメータ）
- バックグラウンド再生

## Dependencies

- Issue 01（データモデル: PlayerState）

## Acceptance Criteria

1. 有効な WAV バイト列を渡すと音声が再生される
2. 再生中に `isPlaying() == true` が返る
3. 再生完了後に `currentState() == IDLE` に戻る
4. `stop()` で再生が停止する
5. 空のバイト列や不正データで `Result.failure` が返り、クラッシュしない
6. `release()` 後に MediaPlayer リソースが解放される
7. 一時ファイルが再生後に削除される

## Test Expectations

- **統合テスト（実機必要）**:
  - 実際の WAV データでの再生確認
  - 停止操作の動作確認
- **単体テスト（限定的）**:
  - 状態遷移の検証
  - 不正データ入力時のエラーハンドリング

## AI 実装適性

- **AI 実装に向いている**: MediaPlayer の基本的な使い方は定型的
- **人間承認ポイント**:
  - 一時ファイルのディレクトリパス（`cacheDir` を使うのが一般的）
  - 再生完了待機を `suspendCancellableCoroutine` で実装する方法の確認

## Implementation Notes

- `play()` は `suspend` 関数で、再生完了まで待機する。`suspendCancellableCoroutine` + `OnCompletionListener` で実装
- 一時ファイルは `context.cacheDir` に作成し、再生後に即削除
- `MediaPlayer` は再利用可能だが、エラー状態になった場合は `reset()` または `release()` + 再生成が必要
- `Dispatchers.IO` で実行（ファイル I/O のため）
- スケルトンコードのダミー `delay(300)` を実際の MediaPlayer 実装に置き換える
