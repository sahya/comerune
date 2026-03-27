# Issue #5: SessionWsClient（入口WebSocket接続）の実装

Labels: v1.2, infra

GitHub Issue: https://github.com/sahya/comerune/issues/5

Epic: #1

## Goal

ニコ生の入口WebSocket（`wss://a.live2.nicovideo.jp/wsapi/v2/watch/{lv}`）に接続し、startWatching 送信、接続先情報（NDGR view URI / legacy wss URL）の抽出、keepalive 応答を行う。

## Scope

- 入口WSへの接続（`web_socket_channel`）
- `startWatching` メッセージの送信
- 受信メッセージの解析:
  - `/api/view/v4/` を含む URL → NDGR view API URI として採用
  - `wss://` で始まる URL → legacy wss URL として採用
  - 放送終了イベントの検出
- keepalive 応答（サーバからのハートビートに対して pong を返す）
- raw JSON のデバッグログ出力（マスキング付き）
  - 機密キーの値を `***` に置換（再帰的、大文字小文字無視）
  - URL のクエリパラメータ除去
  - 40文字以上の値を切り詰め
- 接続/切断/エラーのイベント通知

## Non-scope

- NDGR/legacy クライアントの実装（Issue #6, #7）
- 再接続ロジック（Issue #8）
- UI表示

## Dependencies

- Issue #2（AppMessage モデル）

## Acceptance Criteria

- [ ] 入口WSに接続し、startWatching を送信できる
- [ ] 受信メッセージから NDGR view API URI を抽出できる
- [ ] 受信メッセージから legacy wss URL を抽出できる
- [ ] NDGR 優先、legacy フォールバックの優先順位が守られる
- [ ] keepalive 要求に対して応答を返す
- [ ] 放送終了イベントを検出して通知する
- [ ] raw JSON ログでトークン等がマスクされている
- [ ] URL ログでクエリパラメータが除去されている

## Validation / Error Handling

- WS接続失敗時はエラーイベントを通知する
- keepalive 応答失敗時はセッション切断として扱う
- 未知の終了イベントは FAILED にフォールバックする

## Test Expectations

- **unit**: URL抽出ロジック、マスキングロジック、keepalive応答ロジック
- **widget**: なし
- **integration**: 実際のWS接続テスト（可能であれば）

## Assumptions

- `startWatching` のメッセージフォーマットは参考実装（Qiita記事、N Air）に準拠する
- keepalive のイベント名は `serverTime` → 応答 `pong` を基本とするが、受信イベントドリブンで対応する

## AI実装適性

**Medium** — 参考実装の調査が必要。keepalive のフォーマットが変動しうる

## Human Approval Needed

**Yes** — `startWatching` と keepalive のメッセージフォーマットは、参考実装を元にしているため、実機テストでの検証が必要


---

## 完了時の手順

この Issue の実装が完了したら、以下を行うこと:

1. GitHub Issue にコメントで完了報告を記載する
   - 変更したファイル一覧
   - 実装した内容の要約
   - 意図的に実装しなかった内容
   - テスト結果
   - 残存リスク・フォローアップ事項
2. PR 作成時は、PR 本文に GitHub Issue URL を記載する（例: `Closes https://github.com/sahya/comerune/issues/5`）
3. GitHub Issue をクローズする
