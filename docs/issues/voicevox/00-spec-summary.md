# 仕様要約: VOICEVOX コメント読み上げ機能

## 概要

ニコニコのコメントを取得後、端末内で音声合成して読み上げる機能。
処理は3段階: **コメント整形 → VOICEVOX Core で WAV 合成 → Android 音声再生**。

## 対象範囲

- コメント読み上げ整形
- VOICEVOX Core によるオンデバイス音声合成
- Android 上での音声再生

## 対象外

- コメント取得処理
- 認証処理
- 画面 UI（設定画面等）
- 配信連携処理

## 処理フロー

```
取得済みコメント → 読み上げ対象判定 → 読み上げ整形 → キュー投入
→ VOICEVOX Core で WAV 合成 → Android 音声再生 → 再生完了後に次コメント処理
```

## 基本方針

- コメントは1件ずつ逐次処理（同時再生しない）
- 合成と再生はキュー制御
- 長文やノイズは整形時点で抑制
- 遅延悪化防止のためコメント間引きあり

## 主要コンポーネント

### 1. コメント整形 (CommentNormalizer)

- **前処理**: 改行→空白、タブ→空白、連続空白圧縮、trim、制御文字除去
- **URL処理**: URL含む→「URL省略」に置換、URLのみ→スキップ
- **記号圧縮**: `wwww`→「わら」、`8888`→「はくしゅ」等の変換表あり
- **絵文字処理**: 単独絵文字→スキップ、文中絵文字→削除
- **文字数制限**: 50文字超過で切り詰め + 「、以下省略」
- **辞書置換**: ニコニコ用語の読み変換（拡張可能）
- **NGワード**: 一致時はスキップ（将来「ピー」置換も想定）
- **重複抑制**: 完全一致・5秒以内同一・同一ユーザー連投を抑制

### 2. VOICEVOX Core 音声合成 (VoicevoxEngine)

- Flutter から直接触らず、Android ネイティブ層に実装
- Platform Channel (MethodChannel / EventChannel) で Flutter と連携
- JNI 経由で VOICEVOX Core の C API を呼ぶ
- 合成は1件ずつ順次実行
- 状態: UNINITIALIZED → INITIALIZING → READY → SYNTHESIZING → ERROR

### 3. Android 音声再生 (WavPlayer)

- 初期実装: MediaPlayer（一時ファイル保存方式）
- 将来改善: AudioTrack（メモリ上 PCM 再生）
- 再生制御: stop / skip / clearQueue
- Audio Focus 取得（初期版は単純停止でも可）

### 4. 統合制御 (SpeechController)

- 整形→合成→再生をオーケストレーション
- 単一 CoroutineScope + Mutex で逐次化
- submitComment で整形→キュー投入→アイドルなら処理開始

### 5. Flutter 連携

- MethodChannel: initialize, start, stop, skip, clearQueue, submitComment, updateSettings, getStatus, release
- EventChannel: engine_state_changed, queue_updated, comment_skipped, speech_started, speech_completed, speech_failed, player_state_changed, error

## 責務分離

| Flutter 側 | Android ネイティブ側 |
|---|---|
| コメント取得 | コメント整形本体 |
| 設定UI | VOICEVOX Core 初期化 |
| NGワード設定 | 音声合成 |
| 辞書設定 | キュー制御 |
| 話者選択 | 音声再生 |
| ON/OFF 切替 | 音声リソース解放 |

## 初期パラメータ推奨値

| 項目 | 値 |
|---|---|
| 最大読み上げ文字数 | 50 |
| 最大キュー件数 | 20 |
| 同一文面重複抑止時間 | 5秒 |
| 読み上げ速度 | 1.15 |
| prePhonemeLength | 0.1 |
| postPhonemeLength | 0.1 |

## 初期版で実装しないもの

- 感情パラメータの高度制御
- コメント優先度の複雑な重み付け
- 複数話者自動切替
- 単語単位のイントネーション調整
- ピー音差し込み
- バックグラウンドサービス最適化の完成版
- 再生中の動的音量ミキシング
