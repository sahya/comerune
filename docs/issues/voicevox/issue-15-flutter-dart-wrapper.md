# Issue 15: Flutter Dart ラッパー

## Goal

Flutter (Dart) 側から Android ネイティブの読み上げ機能を呼び出すための、Dart モデルクラスとプラットフォームラッパーを実装する。

## Scope

### Dart モデルクラス

以下のモデルを `lib/src/models/` に作成:

- `RawComment` — コメント入力
- `SubmitResult` — コメント投入結果
- `SpeechSettings` — 読み上げ設定
- `ReplaceRule` — 辞書置換ルール
- `SpeechRuntimeStatus` — 実行時状態
- `SpeechEvent` — イベント

各モデルに:
- `toMap()` — MethodChannel 送信用
- `fromMap()` — MethodChannel 受信用

### プラットフォームインターフェース

```dart
abstract class CommentSpeechPlatform {
  Future<void> initialize();
  Future<void> start();
  Future<void> stop({bool clearQueue = false});
  Future<void> skip();
  Future<void> clearQueue();
  Future<SubmitResult> submitComment(RawComment comment);
  Future<void> updateSettings(SpeechSettings settings);
  Future<SpeechRuntimeStatus> getStatus();
  Future<void> release();
  Stream<SpeechEvent> get events;
}
```

### 実装クラス: `MethodChannelCommentSpeech`

- `MethodChannel('jp.example.comment_speech/methods')` を使用
- `EventChannel('jp.example.comment_speech/events')` を使用
- 各メソッドで Map の変換を行う

## Non-scope

- Flutter 側の UI（設定画面、読み上げ状態表示等）
- 状態管理（Riverpod / BLoC 等）の統合
- コメント取得処理との結合

## Dependencies

- Issue 14（Plugin 側の MethodChannel/EventChannel が実装済みであること）

## Acceptance Criteria

1. 全モデルクラスが `toMap()` / `fromMap()` を持つ
2. `CommentSpeechPlatform` の全メソッドが `MethodChannel` 経由で Native を呼び出せる
3. `events` Stream が `EventChannel` のイベントを `SpeechEvent` に変換して流す
4. `PlatformException` がキャッチ可能な形で伝播する
5. `dart format` / `flutter analyze` でエラーがない

## Test Expectations

- **単体テスト（必須）**:
  - 各モデルの `toMap()` → `fromMap()` ラウンドトリップ
  - `SpeechEvent.fromMap()` の全イベント種別パース
- **Widget テスト（推奨）**:
  - モック MethodChannel を使った `submitComment` の呼び出し検証

## AI 実装適性

- **AI 実装に向いている**: 仕様書の JSON スキーマから Dart モデルを生成する作業。判断ポイントが少ない
- **人間承認ポイント**:
  - Channel 名のパッケージ名確定（Q10）
  - Dart モデルのフィールド名が Kotlin 側と一致しているかの確認

## Implementation Notes

- 仕様書 Section 6.1-6.2 の Dart API を参考にする
- `receiveBroadcastStream()` で EventChannel を購読
- `SpeechEvent.fromMap()` は `type` フィールドで分岐してサブクラスまたは sealed class を返す
- ファイル配置は仕様書 Section 10 (Flutter ディレクトリ構成) に従う:
  ```
  lib/
    comment_speech.dart
    src/
      method_channel_comment_speech.dart
      models/
        raw_comment.dart
        submit_result.dart
        speech_settings.dart
        speech_runtime_status.dart
        speech_event.dart
  ```
