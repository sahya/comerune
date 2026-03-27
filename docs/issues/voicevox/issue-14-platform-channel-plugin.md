# Issue 14: CommentSpeechPlugin (Platform Channel)

## Goal

Flutter と Android ネイティブ側を MethodChannel / EventChannel で接続する Plugin クラスを実装する。
Flutter からの呼び出しを受け付け、SpeechController に委譲し、結果を返す。

## Scope

### Channel 定義（仕様 Section 4.1）

- MethodChannel: `jp.example.comment_speech/methods`
- EventChannel: `jp.example.comment_speech/events`

**注意**: パッケージ名は仮。実パッケージ名はオーナー確認（Q10）。

### `CommentSpeechPlugin` クラス

- `FlutterPlugin` + `MethodCallHandler` + `EventChannel.StreamHandler` を実装
- `onAttachedToEngine` で依存コンポーネントを組み立て
- `onDetachedFromEngine` でリソース解放

### MethodChannel ハンドラ（仕様 Section 4.2）

| メソッド | 入力 | 出力 |
|---|---|---|
| `initialize` | なし | `{ "ok": true }` |
| `start` | なし | `{ "ok": true }` |
| `stop` | `{ "clearQueue": false }` | `{ "ok": true }` |
| `skip` | なし | `{ "ok": true }` |
| `clearQueue` | なし | `{ "ok": true }` |
| `submitComment` | RawComment の JSON | SubmitResult の JSON |
| `updateSettings` | SpeechSettings の JSON | `{ "ok": true }` |
| `getStatus` | なし | SpeechRuntimeStatus の JSON |
| `release` | なし | `{ "ok": true }` |

### EventChannel

- `onListen` で `EventSink` を保持
- `onCancel` で `EventSink` を null に
- `SpeechEventEmitter` 経由でイベントを送信

### 引数のバリデーションとデシリアライズ

- JSON Map を Kotlin データクラスに変換
- 型不一致やキー欠損時は `PlatformException` を返す

### エラーハンドリング（仕様 Section 8）

- 操作失敗: `PlatformException`
- コメント個別失敗: `speech_failed` イベント
- スキップ: 正常レスポンス + `skipped=true`

## Non-scope

- Flutter Dart 側のラッパー（Issue 15）
- 依存コンポーネントの実装（各 Issue で実装済みのものを組み立てるだけ）

## Dependencies

- Issue 06（SpeechQueueManager）
- Issue 07（SettingsRepository）
- Issue 09（VoicevoxEngine）
- Issue 10（WavPlayer）
- Issue 12（SpeechEventEmitter）
- Issue 13（SpeechController）

## Acceptance Criteria

1. `MethodChannel` で全9メソッドが呼び出し可能
2. `EventChannel` で状態変化イベントが Flutter に届く
3. 不正な引数で `PlatformException` が返る（クラッシュしない）
4. `onDetachedFromEngine` でリソースが解放される
5. `submitComment` の JSON → RawComment 変換が正しく動作する
6. `updateSettings` の JSON → SpeechSettings 変換（辞書ルール含む）が正しく動作する

## Test Expectations

- **統合テスト（実機、手動確認）**:
  - Flutter から `submitComment` を呼んで音声再生されること
  - `getStatus` で現在状態が取得できること
  - EventChannel でイベントが受信できること
- **単体テスト（限定的）**:
  - JSON → データクラスの変換テスト
  - 不正引数でのエラーレスポンステスト

## AI 実装適性

- **AI 実装に向いている**: スケルトンコードがほぼ完成形で提供されている。組み立て作業が中心
- **人間承認ポイント**:
  - Channel 名のパッケージ名確定（Q10）
  - CoroutineScope の管理（`Dispatchers.Main.immediate` でよいか）

## Implementation Notes

- 仕様書 Section 1 (CommentSpeechPlugin) のスケルトンコードをそのまま使う
- `pluginScope.launch` で非同期メソッドを呼び出し、成功/失敗で `result` を返す
- `release` のみ同期で実行（`result.success` を即返す）
- `updateSettings` の `dictionaryRules` は `List<Map<String, Any?>>` → `List<ReplaceRule>` への変換が必要
