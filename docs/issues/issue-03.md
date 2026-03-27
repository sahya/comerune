# Issue #3: ConnectionSupervisor 状態機械の実装

Labels: v1.2, infra

GitHub Issue: https://github.com/sahya/comerune/issues/3

Epic: #1

## Goal

接続ライフサイクルを管理する状態機械（ConnectionSupervisor）を実装する。UIや実際のWebSocket接続とは独立して、状態遷移ロジックを確立する。

## Scope

- 接続状態 enum（IDLE, CONNECTING_SESSION_WS, RESOLVING_ENDPOINTS, STREAMING_NDGR, STREAMING_LEGACY, RECONNECTING, STOPPED, ENDED, FAILED）
- エラーコード enum（LV_PARSE_FAILED, SESSION_WS_CONNECT_FAILED, ENDPOINT_RESOLVE_FAILED, NDGR_STREAM_FAILED, LEGACY_WS_FAILED, SPEECH_BOUYOMI_FAILED, SPEECH_VOICEVOX_FAILED, USER_STOPPED, BROADCAST_ENDED）
- 状態遷移ロジック（統合仕様 §6.2 の遷移ルール）
- Wi-Fiアイコン色の判定ロジック（§6.3）
- 状態変更の通知機構（ChangeNotifier 等）
- 再接続回数カウンタ、最終受信時刻、直近エラーの保持

## Non-scope

- 実際のWebSocket接続処理（Issue #4, #5 で実装）
- UI表示
- 指数バックオフの Timer 実装（Issue #7 で実装）

## Dependencies

- Issue #2（AppMessage モデル）

## Acceptance Criteria

- [ ] 全9状態を持つ enum が定義されている
- [ ] IDLE → CONNECTING_SESSION_WS → RESOLVING_ENDPOINTS → STREAMING_NDGR/LEGACY の正常遷移ができる
- [ ] STREAMING_* → RECONNECTING → CONNECTING_SESSION_WS の再接続遷移ができる
- [ ] ユーザー停止で STOPPED に遷移する
- [ ] 放送終了で ENDED に遷移する（再接続しない）
- [ ] ENDED/FAILED からユーザー操作で IDLE に戻れる
- [ ] Wi-Fiアイコン色が状態に応じて正しく判定される（緑: CONNECTING〜RECONNECTING、赤: IDLE/STOPPED/ENDED/FAILED）
- [ ] 不正な遷移（例: IDLE → STREAMING_NDGR）が防止される

## Validation / Error Handling

- 不正な遷移要求は無視またはログ出力（クラッシュしない）

## Test Expectations

- **unit**: 全遷移パターン、Wi-Fiアイコン色判定、不正遷移の防止
- **widget**: なし
- **integration**: なし

## Assumptions

- 状態通知には `ChangeNotifier` を使用する（既存の状態管理パターンに合わせる）

## AI実装適性

**High** — 遷移ルールが仕様書に明示されており、純粋なロジック

## Human Approval Needed

**No**


---

## 完了時の手順

この Issue の実装が完了したら、以下を行うこと:

1. GitHub Issue にコメントで完了報告を記載する
   - 変更したファイル一覧
   - 実装した内容の要約
   - 意図的に実装しなかった内容
   - テスト結果
   - 残存リスク・フォローアップ事項
2. PR 作成時は、PR 本文に GitHub Issue URL を記載する（例: `Closes https://github.com/sahya/comerune/issues/3`）
3. GitHub Issue をクローズする
