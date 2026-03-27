# Issue #45: イベント通知基盤 (SpeechEventEmitter)

## Goal

Android ネイティブ側の状態変化（エンジン状態、キュー更新、再生開始/完了、エラー等）を Flutter 側にイベントとして通知する仕組みを作る。

## Scope

### インターフェース

```kotlin
interface SpeechEventEmitter {
    fun emit(event: Map<String, Any?>)
}
```

### 実装クラス: `FlutterSpeechEventEmitter`

- `EventChannel.EventSink` を通じて Flutter にイベントを送信
- メインスレッドでの送信を保証（Flutter の EventSink はメインスレッドから呼ぶ必要がある）

### イベントファクトリ: `SpeechEvent`

イベント種別と payload を生成するユーティリティ（仕様 Section 5）:

| イベント | payload |
|---|---|
| `engine_state_changed` | `{ "state": "READY" }` |
| `queue_updated` | `{ "size": 4 }` |
| `comment_skipped` | `{ "commentId": "...", "reason": "..." }` |
| `speech_started` | `{ "commentId": "...", "text": "..." }` |
| `speech_completed` | `{ "commentId": "..." }` |
| `speech_failed` | `{ "commentId": "...", "message": "..." }` |
| `player_state_changed` | `{ "state": "PLAYING" }` |
| `error` | `{ "code": "...", "message": "..." }` |

### イベント共通形式

```json
{
  "type": "イベント名",
  "payload": { ... }
}
```

## Non-scope

- EventChannel のセットアップ（Issue #47: Plugin の責務）
- Flutter 側でのイベント受信処理（Issue #48）
- イベントのフィルタリング・バッファリング

## Dependencies

- #32（データモデル: TtsEngineState）

## Acceptance Criteria

1. 全8種のイベントが正しい形式（`type` + `payload`）で生成される
2. `FlutterSpeechEventEmitter` が注入された `EventSink` にイベントを送信する
3. `EventSink` が null の場合（未購読時）にクラッシュしない
4. イベントの `type` フィールドが仕様と一致する

## Test Expectations

- **単体テスト（必須）**:
  - `SpeechEvent` の各ファクトリメソッドが正しい Map を返すこと
  - `FlutterSpeechEventEmitter` がコールバックにイベントを渡すこと
  - null EventSink での安全性

## AI 実装適性

- **AI 実装に向いている**: スケルトンコードがそのまま使える。テストも容易
- **人間承認ポイント**: 特になし

## Implementation Notes

- 仕様書 Section 13 (event 関連) のコードをそのまま使用可能
- `FlutterSpeechEventEmitter` は高階関数 `(Map<String, Any?>) -> Unit` を受け取る設計
- メインスレッド保証は `Handler(Looper.getMainLooper())` で確保するか、Plugin 側で管理する
