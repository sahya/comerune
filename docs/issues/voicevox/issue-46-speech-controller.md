# Issue #46: SpeechController 統合制御

## Goal

コメント整形・キュー管理・音声合成・音声再生を一貫して制御するオーケストレーターを実装する。
このコンポーネントがコメント読み上げの中核であり、全処理の流れを統括する。

## Scope

### インターフェース

```kotlin
interface SpeechController {
    suspend fun initialize(): Result<Unit>
    suspend fun start(): Result<Unit>
    suspend fun stop(clearQueue: Boolean = false): Result<Unit>
    suspend fun skip(): Result<Unit>
    suspend fun clearQueue(): Result<Unit>
    suspend fun submitComment(rawComment: RawComment): Result<SubmitResult>
    suspend fun updateSettings(settings: SpeechSettings): Result<Unit>
    suspend fun getStatus(): SpeechRuntimeStatus
    fun release()
}
```

### 実装クラス: `SpeechControllerImpl`

#### 依存

- `CommentNormalizer` — コメント整形
- `SpeechQueueManager` — キュー管理
- `VoicevoxEngine` — 音声合成
- `WavPlayer` — 音声再生
- `SettingsRepository` — 設定取得
- `SpeechEventEmitter` — イベント通知

#### 処理フロー: `submitComment()`（仕様 Section 6.1-6.2）

1. 設定の enabled チェック
2. `normalizer.normalize()` で整形
3. スキップ判定（skipReason / blank）
4. `queueManager.offer()` でキュー投入
5. `started` 状態なら worker を起動

#### 処理フロー: キュー処理 worker

1. `Mutex` で排他（同時に1つの worker のみ）
2. キューから1件取り出し
3. `engine.synthesize()` で WAV 生成
4. 失敗時: イベント通知して次へ（当該コメントのみ破棄）
5. `player.play()` で再生
6. 完了イベント通知
7. キューが空になるまで繰り返し

#### 非同期制御（仕様 Section 9）

- 単一 `CoroutineScope` + `SupervisorJob`
- `Mutex` で逐次化（二重再生防止）
- worker はキューが空なら終了、新コメントで再起動

## Non-scope

- エラー連続時の自動再初期化（初期版では手動の `initialize` 再呼び出しで対応）
- Foreground Service
- バックグラウンド実行最適化

## Dependencies

- #33-#36（CommentNormalizer 一式）
- #37（SpeechQueueManager）
- #38（SettingsRepository）
- #42（VoicevoxEngine）
- #43（WavPlayer）
- #45（SpeechEventEmitter）

## Acceptance Criteria

1. `submitComment()` が整形→キュー投入→合成→再生の一連フローを正しく実行する
2. `enabled = false` のコメントが `skipped = true` で返る
3. 複数コメントが順次（1件ずつ）処理される
4. 二重再生が発生しない
5. `stop()` で現在の再生が停止する
6. `stop(clearQueue = true)` でキューも空になる
7. `skip()` で次のコメントに進む
8. `clearQueue()` で未再生キューが全削除される
9. `updateSettings()` で設定が更新される
10. `getStatus()` が現在状態を正しく返す
11. `release()` でエンジンとプレイヤーのリソースが解放される
12. 合成失敗時に当該コメントが破棄され、次のコメント処理に進む

## Test Expectations

- **単体テスト（モック使用、必須）**:
  - submit → normalize → queue → synthesize → play の呼び出し順序
  - enabled=false でのスキップ
  - skipReason 付きコメントのスキップ
  - 合成失敗時の次コメント続行
  - stop / skip / clearQueue の動作
- **統合テスト（実機）**:
  - 複数コメント連続投入→順次再生
  - 途中停止→再開

## AI 実装適性

- **AI 実装に部分的に向いている**: ロジックは仕様書とスケルトンコードに明示されているが、非同期制御は慎重なテストが必要
- **人間承認ポイント**:
  - Coroutine のスコープ管理とキャンセレーション戦略
  - race condition の有無（Mutex だけで十分かの判断）

## Implementation Notes

- 仕様書 Section 3 (SpeechControllerImpl) のスケルトンコードをベースにする
- 仕様書 Section 8 の注意点: 合成失敗後に永続 ERROR にしない設計
- `startWorkerIfNeeded()` は `started == true` かつ worker が走っていない場合にのみ起動
- `@Volatile` フラグと `Mutex` の使い分けに注意
