# ニコニコ生放送 コメント取得 & 読み上げアプリ 仕様書（統合版 / v1.2）

作成日: 2026-02-23（JST）  
対象: Android（Flutter）  
言語: 日本語  
目的: 「ニコ生コメント取得 + 画面表示 + 読み上げ（棒読みちゃん / VOICEVOX） + 安定接続（Keepalive/再接続）」を実装可能な粒度で仕様化する

---

## 0. この仕様書の位置づけ

本仕様書は、これまで決まった要件（会話内合意）と、提供された参考情報（Qiita / GitHubコード）を統合して、矛盾がない形にまとめたもの。

「NDGR/legacy自動判別」については、**getplayerstatus の is_ndgr 判別は採用しない**方針で確定しているため、本仕様書ではその要件を削除済み（採用しない理由は「参考情報側の主要フローと一致しない」「仕様変動で壊れやすい」）。

---

## 1. 用語

- **lv**: ニコニコ生放送 番組ID（例: lv345678901）
- **入口WS（Session WS）**: `wss://a.live2.nicovideo.jp/wsapi/v2/watch/{lv}`  
  視聴セッション開始と、コメント取得用接続先（NDGR/legacy）情報の取得に使用するWebSocket
- **NDGR**: 新コメントサーバ方式（HTTP streaming + Protobuf length-delimited）
- **legacy**: 旧来方式のコメント取得（入口WSで返る wss URL に接続し、JSON等を解析する想定）
- **view API URI**: NDGRの入口となるHTTP(S) URI（`/api/view/v4/` を含むものを検出して採用）
- **棒読みちゃん**: Windows上の読み上げソフト。TCP連携（一般に50001）で外部から読み上げ指示を送る
- **VOICEVOX**: 音声合成エンジン。HTTP API（/audio_query, /synthesis）で音声生成し、アプリ内再生する

---

## 2. 目的 / ゴール

### 2.1 ゴール（必須）
1. 放送ID（lv）またはURL入力から、コメントを取得して画面表示できる
2. NDGR/legacy を自動判別し、適切な方式でコメント取得できる
3. 接続/停止をボタンで制御できる
4. 接続状態をWi-Fiアイコンの色（緑/赤）で表示できる
5. 新着コメントで自動スクロールして追従表示できる（ユーザー操作時は停止推奨）
6. 読み上げを **棒読みちゃん と VOICEVOX の両方**で実装し、切替できる
7. Keepalive / 再接続により、回線断・ストール・スリープ復帰で止まりにくい

### 2.2 非ゴール（v1.2では必須にしない）
- コメント投稿（一般）
- 放送者コメント（運営/配信者コメント投稿）
- 終了番組の全量アーカイブ取得
- TV実況（jk系）完全対応
- コテハン/ユーザー色などのChazuke互換の高度機能一式  
  ※将来拡張の候補としては残す

---

## 3. 対象プラットフォーム / 技術要件

- Flutter 3.0+
- Dart
- 対応: Android実機 / Androidエミュレータ
- 権限: Internet必須
- 主要ライブラリ（確定）
  - `web_socket_channel`（WebSocket）
  - `http`（HTTP API / VOICEVOX）
  - `audioplayers`（音声再生）
  - `xml`（※不要の可能性が高い。getplayerstatus方式を採用しないため、基本は不要）
- 追加推奨（実装安定性のため）
  - HTMLパース（embedded-dataから情報を抜く場合）
  - Protobufデコード用（Dart側でlength-delimited stream decodeが必要）
  - UIスレッド負荷を避けるため、Protobuf decodeは Isolate へ逃がすのを推奨

---

## 4. UI仕様

### 4.1 画面構成（単一画面MVP）
- テキスト入力欄（放送ID/URL）
- ボタン：接続 / 接続停止
- ステータス（Wi-Fiアイコン + デバッグ）
- コメント一覧（ListView）

### 4.2 入力欄仕様
- 入力: lv または URL
- 正規表現で `lv\d+` を抽出し、それ以外は除去
- Enterキー（IMEの送信/完了）で接続開始
- 抽出結果（lv）をデバッグ表示に反映

### 4.3 ボタン仕様
- 接続:
  - 既に接続中の場合は無効化、または再接続（仕様としては無効化推奨）
- 接続停止:
  - 入口WS、コメント接続（NDGR/legacy）、読み上げキューを全停止
  - 状態を未接続に戻す

### 4.4 ステータス表示
- Wi-Fiアイコン色:
  - 緑: 接続中（コメントストリームが稼働中、または稼働に向けた接続試行中）
  - 赤: 未接続 / 停止 / 致命的失敗
- デバッグ情報（必須表示）
  - 抽出した放送ID
  - 接続方式: NDGR / legacy
  - 接続フェーズ: SessionWS / CommentStream
  - 最終受信時刻
  - 再接続回数
  - 直近エラー（短いコード/メッセージ）

### 4.5 コメント一覧仕様
- 並び: 古い順
- 新着受信で自動スクロール
  - ユーザーが手動でスクロールしている間は自動スクロール停止（推奨）
- タップで単発読み上げ（SpeechEngineを呼ぶ）

---

## 5. 全体アーキテクチャ（論理構成）

### 5.1 コンポーネント
- `LvParser`
  - 入力文字列から lv を抽出（regex）
- `ConnectionSupervisor`
  - 状態機械、接続開始/停止、再接続制御、バックオフ、監視
- `SessionWsClient`（入口WS）
  - wsapi/v2/watch に接続し、startWatchingなどを送信し、接続先情報（NDGR view URI / legacy wss）を抽出
- `NdgrClient`
  - view/segment/backward をHTTP streamingで購読、Protobuf length-delimited をデコード、コメントをemit
- `LegacyCommentClient`
  - 入口WSで得た wss URL に接続し、JSON等のメッセージからコメントを抽出してemit
- `MessageNormalizer`
  - NDGR/legacyの差を吸収して AppMessageへ正規化
- `TimelineStore`
  - コメント保持（リングバッファ）、重複排除、UIへ流す
- `SpeechEngine`（抽象）
  - `BouyomiEngine` / `VoicevoxEngine`
  - キュー制御、フィルタ、整形
- `AudioPlayer`
  - VOICEVOXの生成音声を再生（audioplayers）

### 5.2 AppMessage（共通モデル案）
最低限、以下を含む。

- `id`（文字列）
  - NDGR: message id 等が取れればそれ、無理なら生成
  - legacy: 受信payloadから取れない場合は生成
- `timestamp`（DateTime）
- `userId`（文字列 / optional）
- `content`（文字列）
- `type`（enum）
  - `chat`（通常コメント）
  - `operator`（運営/配信者）
  - `notification`（通知）
  - `gift` / `nicoad` など（将来表示拡張用）
- `raw`（optional）
  - デバッグ用途（必要なら）

---

## 6. 状態機械（ConnectionSupervisor）

### 6.1 状態（例）
- `IDLE`
- `CONNECTING_SESSION_WS`
- `RESOLVING_ENDPOINTS`
- `STREAMING_NDGR`
- `STREAMING_LEGACY`
- `RECONNECTING`
- `STOPPED`（ユーザー停止）
- `FAILED`

### 6.2 状態遷移（概略）
1. IDLE → CONNECTING_SESSION_WS（接続ボタン）
2. CONNECTING_SESSION_WS → RESOLVING_ENDPOINTS（WS接続完了）
3. RESOLVING_ENDPOINTS で判別
   - NDGR view URI 獲得 → STREAMING_NDGR
   - legacy wss URL 獲得 → STREAMING_LEGACY
   - どちらも不可 → FAILED
4. STREAMING_* でエラー/ストール発生 → RECONNECTING
5. RECONNECTING → CONNECTING_SESSION_WS（入口WSから取り直す）または STREAMING_*（同一接続先へ再接続）
6. STOPPED はユーザー停止で到達。以後再開は IDLE → 接続
7. FAILED は致命的失敗。ユーザー操作で再試行可能

### 6.3 Wi-Fiアイコン判定
- 緑: CONNECTING_SESSION_WS / RESOLVING_ENDPOINTS / STREAMING_*
- 赤: IDLE / STOPPED / FAILED

---

## 7. 接続方式の自動判別（確定仕様）

### 7.1 判別は「入口WS受信内容」ベース
- `getplayerstatus.is_ndgr` を使った判別は採用しない（要件から除外済み）
- 入口WSから受信したメッセージ群を解析し、次を抽出する。

### 7.2 抽出ルール
- NDGRの判定:
  - 受信文字列に `/api/view/v4/` を含む HTTP(S) URL を検出したら、それを **NDGR view API URI** として採用
- legacyの判定:
  - 受信文字列に `wss://` で始まる URL を検出したら、それを **legacyコメントWS URL** として採用
- 優先順位:
  1) NDGR view API URI が見つかれば NDGR 確定
  2) 見つからない場合に legacy wss URL が見つかれば legacy 確定
  3) どちらも見つからなければ FAILED

### 7.3 フォールバック方針（壊れにくさ）
- 入口WSで「イベント型が変わる」可能性を考慮し、未知イベントでも raw JSON をデバッグログに残し、URL検出のフォールバックを常に働かせる
- 認証付きURL（ログイン時に混ざる可能性）のログ出力は禁止（トークン/クッキーが混入し得るため）

---

## 8. NDGRモード仕様

### 8.1 基本方針
- 入口WSで得た **view API URI** を起点に、HTTP streamingでコメントを取得する
- Protobuf length-delimited stream のデコードが必要

### 8.2 過去コメント初期ロード
- 直近100件を既定とする（設定で変更可能）
- NDGRの backward/segment を辿って過去を補完する（参考実装に準拠）

### 8.3 Keepalive / 再接続（NDGR）
- 入口WSが切断:
  - 入口WSを再接続して view API URI を再取得し、NDGRストリームを張り替える
- NDGR HTTP streaming が停止（ストール）:
  - 「最終受信時刻」から一定時間（例30秒）無受信でストール判定
  - 同一 view API URI（可能なら at/next を保持）で再接続
- リトライ:
  - エラー時は指数バックオフ（1,2,4,8,16,30秒 + jitter）
  - 再接続回数をデバッグ表示に反映

### 8.4 メッセージ正規化（NDGR→AppMessage）
- 参考実装の分類（chat/operator/notification/gift/nicoad/state/statistics/signal 等）を前提に、最低限 `chat` の表示を必須とする
- `timestamp` はサーバ時刻優先（取得できない場合は受信時刻）
- `userId`（匿名含む）は取れれば取る。取れない場合でも表示は成立させる

---

## 9. legacyモード仕様（A確定：URL直渡し）

### 9.1 前提
- 入口WSから **legacyコメント取得用の wss URL がそのまま返る**
- そのURLへ接続し、受信JSON等からコメントを抽出する

### 9.2 コメント抽出（legacy）
- 受信payloadの具体フォーマットは「返ってくるURLの実体」に依存するため、v1.2では以下方針で実装する。
  - まず raw JSON を受け取り、コメントらしきキー候補（例: `chat`, `content`, `text`, `message`, `body` など）を候補探索できるよう、抽出部は差し替え可能にする
  - 実サンプル（マスク可）が1本でも得られれば、キーを固定した抽出仕様へ更新する（v1.3で確定）

### 9.3 Keepalive / 再接続（legacy）
- legacyコメントWSが切断:
  - 同一URLへ再接続（指数バックオフ）
  - 一定回数（例3回）連続失敗で、入口WSからURLを取り直す
- 入口WSが切断:
  - 入口WS再接続→legacy URL再取得→張り替え

---

## 10. 読み上げ仕様（棒読みちゃん + VOICEVOX 両対応）

### 10.1 共通ポリシー（応答性を守る）
- 読み上げは「自動読み上げ」と「タップ読み上げ」を分ける
- 読み上げキュー制御は必須（VOICEVOXで詰まりやすいため）
  - 例: キュー上限 20
  - 例: 最大遅延 10秒を超えたら古いものから破棄
- 整形フィルタ（推奨）
  - URLを省略（「URL」等の固定文に置換）
  - 連投抑制（同一userIdの短時間連続）
  - NG正規表現（設定可能）

### 10.2 棒読みちゃん（既定：応答性優先）
- 送信方式:
  - TCP接続（1発話=1接続）
  - 15byte固定ヘッダ + 本文
- 設定項目:
  - host（例: 192.168.x.x）
  - port（既定: 50001）
  - speed / tone / volume / voice / charset
- 失敗時:
  - 接続失敗・タイムアウト時は、その発話をスキップし、キューを詰まらせない

### 10.3 VOICEVOX（品質優先）
- API（既定）:
  - `POST /audio_query`
  - `POST /synthesis`
- 接続先:
  - エミュレータ開発時: `http://10.0.2.2:50021`
  - 実機運用時: 同一LAN内ホスト（例: `http://192.168.x.x:50021`）
- 音声再生:
  - synthesisレスポンスの音声バイナリを `audioplayers` で再生
- 性能方針:
  - 生成待ちが溜まりやすいので、キュー上限と破棄は必須
  - HTTP処理はUIスレッドを塞がない（非同期 + 必要ならIsolate/別スレッド）

---

## 11. 認証・認可（ログイン）について（v1.2の扱い）

### 11.1 現状方針
- v1.2の必須要件には「ログイン」は含めない（閲覧中心）
- ただし将来拡張として以下を想定できる:
  - コメント投稿（一般視聴者）
  - 放送者コメント（配信者/運営）
  - 終了番組の取得（プレミアム要件が出る可能性）

### 11.2 セキュリティ要件（ログイン導入時に必須）
- Cookie/トークン/認証付きURLはログに出さない
- CookieはOSの安全な領域に保存し、ログアウトで破棄できること
- 認証導入の実装方式は以下の順で推奨:
  1) アプリ内ブラウザ（Custom Tabs/WebView）でログインしてCookieJar共有
  2) 直接メール/パスワード入力方式は避ける（運用・安全面の負債が大きい）

---

## 12. ロギング / デバッグ / 観測性

### 12.1 必須ログ（ユーザー向けデバッグ表示）
- lv
- 接続方式（NDGR/legacy）
- 状態（フェーズ/状態機械）
- 最終受信時刻
- 再接続回数
- 直近エラー（短文）

### 12.2 開発ログ（内部）
- 入口WS受信イベントの型一覧（ただし秘匿情報はマスク）
- NDGR/legacyの接続先URL（ただし認証情報が含まれる可能性がある場合はマスク）
- Protobuf decode例外（断片復元の発生回数）

---

## 13. エラー取り扱い

### 13.1 エラー分類
- `LV_PARSE_FAILED`: lv抽出失敗
- `SESSION_WS_CONNECT_FAILED`: 入口WS接続失敗
- `ENDPOINT_RESOLVE_FAILED`: NDGR/legacyの接続先抽出失敗
- `NDGR_STREAM_FAILED`: NDGRのHTTP streaming失敗
- `LEGACY_WS_FAILED`: legacyコメントWS失敗
- `SPEECH_BOUYOMI_FAILED`: 棒読みちゃん送信失敗
- `SPEECH_VOICEVOX_FAILED`: VOICEVOX合成失敗
- `USER_STOPPED`: ユーザー停止（エラーではないが状態）

### 13.2 ユーザー通知
- FAILEDに落ちる場合は「原因カテゴリ」と「再試行可能性」を示す
- 接続中の断続的エラーは、UIを騒がせずデバッグ欄に記録（再接続を優先）

---

## 14. 受け入れ基準（Definition of Done）

- URL貼り付けで lv が抽出される
- 接続開始でコメントが流れる（NDGRまたはlegacy）
- 接続停止で確実に停止する（ネットワーク通信が止まる）
- Wi-Fiアイコンが状態に応じて赤/緑で切り替わる
- 新着で自動スクロールする（ユーザーがスクロール中は止まる）
- 読み上げが両方動作する
  - 棒読みちゃん: TCP送信で読み上げが鳴る
  - VOICEVOX: audio_query→synthesis→アプリ内再生
- 瞬断後に自動復帰する（30秒以内目標）
- デバッグ情報が必要最低限揃っている

---

## 15. 将来拡張（候補）
- コメントのユーザー別色
- コテハン登録
- 読み上げ声のUI設定
- 翻訳（日本語→英語など）
- 音量調整
- コメント投稿（一般）
- 放送者コメント投稿
- 次枠追従
- TV実況

---

## 16. 参考情報（本仕様の根拠・参照元）

### 16.1 実装参照（N Air）
- Nicolive comment viewer（サービス本体）
  - https://github.com/n-air-app/n-air-app/blob/n-air_development/app/services/nicolive-program/nicolive-comment-viewer.ts
- NDGR受信・変換（Receiver）
  - https://github.com/n-air-app/n-air-app/blob/n-air_development/app/services/nicolive-program/NdgrCommentReceiver.ts
- NDGRクライアント（Client）
  - https://github.com/n-air-app/n-air-app/blob/n_air_development/app/services/nicolive-program/NdgrClient.ts

### 16.2 仕様解説（Qiita）
- 新コメントサーバ（NDGR）接続・startWatching・pong・postComment等の解説
  - https://qiita.com/DaisukeDaisuke/items/3938f245caec1e99d51e

### 16.3 NDGRクライアント（tsukumijima）
- NDGRClient（仕様・実装の参照）
  - https://github.com/tsukumijima/NDGRClient

### 16.4 NDGRクライアント（C#）
- NdgrClientSharp（API一覧・接続例の参照）
  - https://github.com/TORISOUP/NdgrClientSharp

### 16.5 棒読みちゃん連携（TCPヘッダ等）
- 棒読みちゃん外部連携のフォーマット解析
  - https://qiita.com/itokonpsp/items/e39e231dfaec0c98545a

---

## 17. 未確定事項（v1.2で残すもの）
1) legacyコメントWSの受信payload形式（JSONキー構造）
   - 入口WSが返す “legacy wss URL” の実サンプル（マスク可）が1つあれば、抽出仕様（フィールド名、イベント種別）をv1.3で確定可能
2) NDGR ProtobufデコードのDart実装詳細（ライブラリ選定）
   - length-delimited stream decode + 断片復元の実装方針を別紙（技術設計）として確定する

---

## 18. 実装メモ（推奨）
- ProtobufデコードはUI負荷が出やすいため、Isolateで行うのを推奨
- VOICEVOXは詰まりやすいので、キュー上限・破棄が体感品質の要
- ログインを将来入れる場合、Cookie/トークン秘匿（ログ禁止）は必須

---