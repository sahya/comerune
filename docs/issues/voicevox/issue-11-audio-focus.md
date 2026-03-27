# Issue 11: Audio Focus 制御

## Goal

他のアプリ（音楽プレイヤー等）と音声出力が競合した場合の挙動を制御する。
読み上げ開始時に Audio Focus を取得し、フォーカス喪失時に適切に対応する。

## Scope

### Audio Focus 取得（仕様 Section 5.7）

- 読み上げ開始時に `AudioManager.requestAudioFocus()` を呼ぶ
- `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK` を使用
  - 意味: 一時的にフォーカスを取得し、他のアプリは音量を下げてもよい

### フォーカス喪失時の対応

- **初期版**: 単純停止（現在のコメント再生を停止、キューは保持）
- `AUDIOFOCUS_LOSS` → 停止
- `AUDIOFOCUS_LOSS_TRANSIENT` → 一時停止（初期版は停止で代用可）

### MediaPlayerWavPlayer への統合

- `play()` の前に Audio Focus を取得
- `stop()` / 再生完了時に Audio Focus を放棄
- `OnAudioFocusChangeListener` で喪失を検知

## Non-scope

- フォーカス喪失後の自動再開
- 音量ダッキング（他アプリの音量を下げる制御）
- 他のオーディオストリームとのミキシング

## Dependencies

- Issue 10（WavPlayer: Audio Focus を WavPlayer に統合するため）

## Acceptance Criteria

1. 読み上げ再生時に Audio Focus が取得される
2. 再生完了/停止時に Audio Focus が放棄される
3. 他のアプリが Audio Focus を奪った場合、再生が停止する
4. Audio Focus 取得失敗時に再生が開始されない（`Result.failure` を返す）

## Test Expectations

- **統合テスト（実機、手動確認）**:
  - 読み上げ中に音楽アプリを再生 → 読み上げが停止すること
  - 音楽アプリ停止後に次のコメント再生が可能なこと
- **自動テストは困難**: Audio Focus は Android システムの機能

## AI 実装適性

- **AI 実装に向いている**: AudioManager の定型的な使い方
- **人間承認ポイント**: Audio Focus 喪失時に「停止してキュー保持」でよいかの確認（Q9 参照）

## Implementation Notes

- `AudioManager.requestAudioFocus()` は API 26+ の `AudioFocusRequest.Builder` を使う
- `AudioAttributes` は `USAGE_MEDIA` + `CONTENT_TYPE_SPEECH` を設定
- Audio Focus の状態は `WavPlayer` 内部で管理する
- 初期版はシンプルに停止だけ。「一時停止 → 再開」は将来対応
