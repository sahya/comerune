# Issue #32: Kotlin データモデル定義

## Goal

VOICEVOX コメント読み上げ機能で使用する全 Kotlin データクラス・Enum を定義する。
他の全 Issue がこのモデルに依存するため、最初に作成する。

## Scope

以下のデータクラスと Enum を `domain/model/` パッケージに作成する。

- `RawComment` — 取得済みコメントの入力データ
- `NormalizedComment` — 整形後コメント
- `SpeechQueueItem` — キュー内アイテム
- `ReplaceRule` — 辞書置換ルール
- `SpeechSettings` — 読み上げ設定（デフォルト値含む）
- `SpeechRequest` — 合成リクエスト
- `SubmitResult` — コメント投入結果
- `SpeechRuntimeStatus` — 実行時状態
- `VoicevoxConfig` — エンジン初期化設定
- `WavSynthesisResult` — 合成結果
- `QueueOfferResult` — キュー投入結果
- `TtsEngineState` — エンジン状態 Enum
- `PlayerState` — プレイヤー状態 Enum

## Non-scope

- インターフェース定義（各 Issue で定義）
- 実装クラス
- Flutter (Dart) 側のモデル（Issue 15）
- JSON シリアライズ/デシリアライズ（Plugin 側の責務）

## Dependencies

- なし（最初に実装する）

## Acceptance Criteria

1. 上記すべてのデータクラスと Enum が `domain/model/` に存在する
2. 仕様書のフィールド名・型・デフォルト値と一致する
3. `SpeechSettings` のデフォルト値が仕様の推奨値（speedScale=1.15, maxTextLength=50, maxQueueSize=20, duplicateWindowMs=5000）と一致する
4. `dart format` / `flutter analyze` 相当の Kotlin lint でエラーがない
5. data class の equals / hashCode / copy が正しく動作する（Kotlin 標準で保証）

## Test Expectations

- 各 data class のインスタンス生成テスト
- `SpeechSettings` のデフォルト値検証テスト
- `TtsEngineState` / `PlayerState` の全値列挙テスト

## AI 実装適性

- **AI 実装に向いている**: 仕様書のコード例をそのまま Kotlin ファイルに分割する作業。判断ポイントが少ない
- **人間承認ポイント**: パッケージ名（`jp.example.comment_speech` は仮名。実パッケージ名の確認が必要）

## Implementation Notes

- 仕様書 Section 3 (model 一式) のコード例がそのまま使える
- パッケージ名は Q10（未確定事項）の回答に依存する
- 1ファイル1クラスでも、関連するものをまとめてもよい（既存プロジェクトの慣習に従う）
