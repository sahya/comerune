# Epic: VOICEVOX コメント読み上げ機能

## 目的

ニコニコのコメントを端末内で音声合成し、1件ずつ順番に読み上げる機能を Flutter アプリに追加する。

## ユーザーから見た振る舞い

1. 読み上げ ON にすると、届いたコメントが自動で音声再生される
2. 不適切なコメント（URL、記号連打、NGワード等）は自動で除外または整形される
3. 長いコメントは短く切り詰められる
4. コメントが大量に来てもキューで順番待ちし、アプリがクラッシュしない
5. 再生中のコメントをスキップしたり、キューを空にしたりできる
6. 読み上げ速度や話者を設定で変更できる

## 技術方針

- 音声合成は VOICEVOX Core を Android ネイティブ層で実行
- Flutter と Android は Platform Channel (MethodChannel / EventChannel) で連携
- Flutter は UI・設定・コメント受け渡しに専念し、合成・再生はネイティブ側
- JNI 経由で VOICEVOX Core の C API を呼ぶ

## Issue 一覧（依存順）

| # | Issue | 概要 | Phase |
|---|---|---|---|
| 1 | Kotlin データモデル定義 | 全 Issue の基盤となるデータクラス群 | 0: 基盤 |
| 2 | コメント整形: 前処理・スキップ判定 | 空白正規化、空文字・記号のみ判定 | 1: 整形 |
| 3 | コメント整形: URL・記号圧縮・絵文字変換 | URL置換、草→わら等、絵文字削除 | 1: 整形 |
| 4 | コメント整形: 文字数制限・辞書置換・NGワード | 50文字制限、用語辞書、禁止語 | 1: 整形 |
| 5 | 重複抑制 (DuplicateDetector) | 同一コメント・連投の抑制 | 1: 整形 |
| 6 | 読み上げキュー管理 (SpeechQueueManager) | FIFO キュー、最大件数、重複排除 | 2: 制御 |
| 7 | 設定リポジトリ (SettingsRepository) | 読み上げ設定の保持・読み出し | 2: 制御 |
| 8 | VOICEVOX Core JNI ブリッジ基盤 | .so 配置、CMake、NativeVoicevoxBridge | 3: エンジン |
| 9 | VoicevoxEngineImpl 実装 | 初期化・合成・解放の本実装 | 3: エンジン |
| 10 | WAV 音声再生 (MediaPlayerWavPlayer) | 一時ファイル保存 + MediaPlayer 再生 | 4: 再生 |
| 11 | Audio Focus 制御 | 他アプリとの音声競合管理 | 4: 再生 |
| 12 | イベント通知基盤 (SpeechEventEmitter) | Flutter 向け状態変化イベント送信 | 5: 統合 |
| 13 | SpeechController 統合制御 | 整形→合成→再生のオーケストレーション | 5: 統合 |
| 14 | CommentSpeechPlugin (Platform Channel) | MethodChannel/EventChannel の Android 側 | 6: 連携 |
| 15 | Flutter Dart ラッパー | Dart 側モデル + CommentSpeechPlatform | 6: 連携 |

## スコープ外（この Epic に含まないもの）

- コメント取得処理
- 認証処理
- 設定画面 UI
- 複数話者自動切替
- 感情パラメータ制御
- ピー音差し込み
- AudioTrack 方式への切替
- Foreground Service 対応
- バックグラウンド再生最適化
