# comerune 仕様書（ニコ生コメント取得 & 読み上げ / Flutter / Android）

作成日: 2026-02-23（JST）  
対象: Android（Flutter）  ※将来的にはiOSも対応できるようにしておく
アプリ名（プロダクト名）: comerune
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
- ログイン / 認証（詳細は §11 参照）
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
- 対応: Android実機 / Androidエミュレータ   ※将来的にはiOSも対応できるようにしておく
- 権限: Internet必須
- 主要ライブラリ（確定）
  - `web_socket_channel`（WebSocket）
  - `http`（HTTP API / VOICEVOX）
  - `audioplayers`（音声再生）
  - Protobufデコード用（Dart側でlength-delimited stream decodeが必要。NDGR接続に必須）
  - 設定永続化: `shared_preferences`（読み上げエンジン選択・接続設定の保存）
- 追加推奨（実装安定性のため）
  - `xml`（XMLパース。v1.2 では不要だが、必要になった時点で追加する）
  - HTMLパース（embedded-dataから情報を抜く場合）
  - UIスレッド負荷を避けるため、Protobuf decodeは Isolate へ逃がすのを推奨

### 3.1 DI方針

- DI（依存性注入）ライブラリは **v1.2では導入しない**。
- 各コンポーネントは手動組み立て（コンストラクタ注入）とする。
  - `ConnectionSupervisor` が `SessionWsClient` / `NdgrClient` / `LegacyCommentClient` を保持する。
  - `SpeechEngine` は選択中のエンジン実装（`BouyomiEngine` または `VoicevoxEngine`）を差し替え可能な形で保持する。
- 新しいDIパターン（Provider / Riverpod / GetIt 等）の導入は、イシューで明示的に承認された場合のみ行う。

### 3.2 Androidバックグラウンド動作方針

- v1.2では **Foreground Service は導入しない**（非ゴール）。
- アプリがバックグラウンドに移行した場合の動作:
  - Androidのシステムが接続を切断するまでは接続を維持する（標準的なActivity動作に従う）。
  - スリープや画面オフで接続が切れた場合は、フォアグラウンド復帰後に再接続の仕組み（§8.3 / §9.3）が自動的に働く。
- Foreground Serviceは将来拡張候補（§15）に追記する。

---

## 4. UI仕様

### 4.1 画面構成
v1.2 では以下の3画面構成とする。詳細は `UI_Specification.md` に委譲する。

| 画面 | 役割 |
|------|------|
| 接続先選択画面（SelectScreen） | 放送ID/URL入力 → 接続開始。将来的にはログイン後のフォローリストからも選択できるようにする |
| コメント閲覧画面（CommentScreen） | 接続中の放送のコメント一覧・ステータス表示・停止ボタン |
| 設定画面（SettingsScreen） | 読み上げエンジン・各種パラメータ設定 |

### 4.2 入力欄仕様（SelectScreen）
- 入力: lv または URL
- 正規表現で `lv\d+` を抽出し、それ以外は除去
- Enterキー（IMEの送信/完了）で接続開始
- 抽出した lv を接続処理へ渡す（CommentScreen のデバッグ欄に反映される）

### 4.3 ボタン仕様
- 接続（SelectScreen）:
  - 既に接続中の場合は無効化推奨
- 接続停止（CommentScreen）:
  - 入口WS、コメント接続（NDGR/legacy）、読み上げキューを全停止
  - 状態を未接続に戻し、SelectScreen に戻る

### 4.4 ステータス表示（CommentScreen）
- Wi-Fiアイコン色:
  - 緑: 接続中（コメントストリームが稼働中、または稼働に向けた接続試行中）
  - 赤: 未接続 / 停止 / 放送終了 / 致命的失敗
- 通常表示（常時）:
  - 抽出した放送ID
  - 最終受信時刻
  - 再接続回数
  - 直近エラー（短いコード/メッセージ）
- デバッグモード時追加表示（設定で ON/OFF）:
  - 接続方式: NDGR / legacy
  - 接続フェーズ: 状態機械の現在状態名

### 4.5 コメント一覧仕様（CommentScreen）
- 並び: 古い順
- 新着受信で自動スクロール
  - ユーザーが手動でスクロールしている間は自動スクロール停止（推奨）
- コメント行のタップ操作は v1.2 では未割当（将来拡張候補）

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
  - コメント保持（リングバッファ、上限は過去コメント取得件数設定に連動。既定: **100件**）、重複排除、UIへ流す
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
- `ENDED`（放送終了）
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
7. ENDED は放送終了通知（入口WSからの終了イベント）で到達。再接続はしない。ユーザー操作でIDLEに戻れる
8. FAILED は致命的失敗。ユーザー操作で再試行可能

### 6.3 Wi-Fiアイコン判定
- 緑: CONNECTING_SESSION_WS / RESOLVING_ENDPOINTS / STREAMING_* / RECONNECTING
- 赤: IDLE / STOPPED / ENDED / FAILED

### 6.4 放送終了時の挙動
- 入口WSから放送終了を示すイベント（例: `disconnect` 等）を受信したとき:
  - 再接続は行わず `ENDED` 状態に遷移する
  - デバッグ表示に「放送終了」を記録する
  - 接続停止ボタンと同等の後処理（入口WS / コメントストリーム / 読み上げキュー の停止）を行う
- ENDED 状態でのUI:
  - Wi-Fiアイコンは赤
  - デバッグ欄に「放送終了」と表示
  - 接続ボタンを再度押すことで IDLE → CONNECTING_SESSION_WS に遷移できる（同一 lv の再試行）
- 注意: 放送終了イベントの具体的なイベント名・フォーマットは入口WSの実装依存のため、`ENDED` 遷移のトリガー判定は `SessionWsClient` 内で行い、未知の終了イベントが来た場合は FAILED にフォールバックする

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
  - raw JSON のログ出力時は以下のマスキングを適用する:
    - 既知の機密キー（`token`, `cookie`, `session`, `auth`, `credential`, `secret` 等）の値は `"***"` に置換する
    - URL値は既存ルール（`scheme://host/path` のみ、クエリパラメータ除去）を適用する
- URLのログ出力は `scheme://host/path` までとし、クエリパラメータは常に除去する（トークン/クッキーが混入し得るため）

### 7.4 入口WS Keepalive（セッション維持）
- ニコ生の入口WSはサーバから定期的に keepalive 要求（`serverTime` イベント等）を送信し、クライアントが一定時間内に応答しないとサーバ側がセッションを切断する。
- `SessionWsClient` は受信したメッセージの中に keepalive 要求が含まれる場合、それに対して応答を返さなければならない。
- 具体的な応答フォーマット:
  - サーバから `{"type":"serverTime","data":{...}}` 等のハートビートが届いたら、`{"type":"pong","body":{}}` 等の形式で返す（実際のイベント名は参考実装に準拠）
  - 応答に失敗した場合はセッション切断として扱い、再接続フロー（§6.2 → RECONNECTING）に進む
- セッション維持のための送信間隔や要求フォーマットは、入口WSの仕様変更に伴い変わる可能性があるため、ハードコードを避けて受信イベントドリブンで応答する設計を推奨する

---

## 8. NDGRモード仕様

### 8.1 基本方針
- 入口WSで得た **view API URI** を起点に、HTTP streamingでコメントを取得する
- Protobuf length-delimited stream のデコードが必要

### 8.2 過去コメント初期ロード
- 直近100件を既定とする（設定で変更可能: 100 / 500 / 1000 / 全部）
- NDGRの backward/segment を辿って過去を補完する（参考実装に準拠）
- 設定値に応じて TimelineStore のリングバッファ上限も連動して変更される（§5.1参照）。初期ロード完了後にリアルタイムコメントが流入しても最新コメントが保持されるよう、リングバッファは初期ロード後もスライドして動作する（古いものから順に破棄）
- 「全部」選択時はバッファ上限を十分大きな値（例: 10000件）に設定し、取得可能な過去コメントをすべて段階的に取得する

### 8.3 Keepalive / 再接続（NDGR）
- 入口WSが切断:
  - 入口WSを再接続して view API URI を再取得し、NDGRストリームを張り替える
- NDGR HTTP streaming が停止（ストール）:
  - 「最終受信時刻」から一定時間（既定15秒）無受信でストール判定
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
- v1.2では `chat` キーを固定の抽出対象とする
  - 受信JSONに `chat` キーが存在する場合、そのオブジェクトからコメント本文・ユーザーID・タイムスタンプ等を抽出し、AppMessageへ正規化する
  - `chat` キーが存在しない受信メッセージは無視する（デバッグログには raw JSON を出力する）
  - `chat` キーでの抽出が実運用で不十分な場合は、v1.3で抽出キーを追加・変更する
- 抽出部は差し替え可能な設計とし、将来のキー追加に備える

### 9.3 Keepalive / 再接続（legacy）
- legacyコメントWSが切断:
  - 同一URLへ再接続（指数バックオフ）
  - 一定回数（例3回）連続失敗で、入口WSからURLを取り直す
- 入口WSが切断:
  - 入口WS再接続→legacy URL再取得→張り替え

---

## 10. 読み上げ仕様（棒読みちゃん + VOICEVOX 両対応）

### 10.1 共通ポリシー（応答性を守る）
- 読み上げキュー制御は必須（VOICEVOXで詰まりやすいため）
  - 例: キュー上限 20
  - 例: 最大遅延 10秒を超えたら古いものから破棄
- 整形フィルタ（推奨）
  - URLを省略（「URL」等の固定文に置換）
  - 連投抑制（同一userIdの1秒以内の連続）
  - NG正規表現（設定可能）

### 10.2 棒読みちゃん（既定：応答性優先）
- 送信方式:
  - TCP接続（1発話=1接続）
  - 15byte固定ヘッダ + 本文
- 設定項目:
  - host（例: 192.168.x.x）
  - port は 50001 固定（設定不可）
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
- Cookie/トークンはログに出さない。URLは `scheme://host/path` までとし、クエリパラメータは常に除去する
- CookieはOSの安全な領域に保存し、ログアウトで破棄できること
- 認証導入の実装方式は以下の順で推奨:
  1) アプリ内ブラウザ（Custom Tabs/WebView）でログインしてCookieJar共有
  2) 直接メール/パスワード入力方式は避ける（運用・安全面の負債が大きい）

---

## 12. ロギング / デバッグ / 観測性

### 12.1 ユーザー向けデバッグ表示

#### 通常表示（常時）
- lv
- 最終受信時刻
- 再接続回数
- 直近エラー（短文）

#### デバッグモード時追加表示（設定で ON/OFF）
- 接続方式（NDGR/legacy）
- 接続フェーズ（状態機械の現在状態名）

### 12.2 開発ログ（内部）
- 入口WS受信イベントの型一覧（ただし秘匿情報はマスク）
- NDGR/legacyの接続先URL（`scheme://host/path` のみ。クエリパラメータは除去）
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
- `BROADCAST_ENDED`: 放送終了通知受信（エラーではないが状態）

### 13.2 ユーザー通知
- FAILEDに落ちる場合は「原因カテゴリ」と「再試行可能性」を示す
- 接続中の断続的エラーは、UIを騒がせずデバッグ欄に記録（再接続を優先）

---

## 14. 受け入れ基準（Definition of Done）

- URL貼り付けで lv が抽出される
- 接続開始でコメントが流れる（NDGR）
- legacy接続時、受信JSONに `chat` キーが存在すればコメントとして表示される
- legacy接続時、`chat` キーが存在しないフォーマットの場合は「legacy: 未対応フォーマット」をUIに表示し、クラッシュしない
- 接続停止で確実に停止する（ネットワーク通信が止まる）
- Wi-Fiアイコンが状態に応じて赤/緑で切り替わる
- 新着で自動スクロールする（ユーザーがスクロール中は止まる）
- 読み上げが両方動作する
  - 棒読みちゃん: TCP送信で読み上げが鳴る
  - VOICEVOX: audio_query→synthesis→アプリ内再生
- 瞬断（一時的なネットワーク断）後に自動復帰する（通常30秒以内。サーバ側障害等で再接続が連続失敗する場合は指数バックオフにより最大1分程度）
- デバッグ情報が必要最低限揃っている

---

## 15. 将来拡張（候補）
- コメントのユーザー別色
- コテハン登録
- VOICEVOXスタイル選択の拡充（感情パラメータ等）
- 翻訳（日本語→英語など）
- 音量調整
- コメント投稿（一般）
- 放送者コメント投稿
- 次枠追従
- TV実況
- Foreground Service（バックグラウンドでの継続接続・Android通知常駐）

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