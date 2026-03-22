# Issue #8: 再接続・指数バックオフ・ストール検出の実装

Labels: v1.2, infra

GitHub Issue: https://github.com/sahya/comerune/issues/8

Epic: #1

## Goal

ConnectionSupervisor に再接続制御を組み込み、回線断やストール時に自動復帰する仕組みを完成させる。

## Scope

- 指数バックオフ（1,2,4,8,16,30秒 + jitter）
- NDGR 再接続:
  - 入口WS切断 → 入口WS再接続 → view URI 再取得 → ストリーム張り替え
  - ストール（15秒無受信） → 同一 view URI で再接続
- legacy 再接続:
  - legacy WS 切断 → 同一URLへ再接続
  - 3回連続失敗 → 入口WS から URL を取り直す
- 再接続回数のカウント・通知
- ConnectionSupervisor と SessionWsClient / NdgrClient / LegacyCommentClient の結合

## Non-scope

- UI表示（Issue #10 で実装）
- Foreground Service（v1.2 非ゴール）

## Dependencies

- Issue #3（ConnectionSupervisor 状態機械）
- Issue #5（SessionWsClient）
- Issue #6（NdgrClient）
- Issue #7（LegacyCommentClient）

## Acceptance Criteria

- [ ] NDGR ストリームが停止した場合、自動再接続が行われる
- [ ] legacy WS が切断した場合、自動再接続が行われる
- [ ] legacy で3回連続失敗した場合、入口WSから URL を取り直す
- [ ] 指数バックオフが正しく適用される（1,2,4,8,16,30秒 + jitter）
- [ ] 放送終了時は再接続しない
- [ ] ユーザー停止時は再接続しない
- [ ] 再接続回数が正しくカウントされる
- [ ] 瞬断後30秒以内に復帰する（通常時）

## Validation / Error Handling

- 再接続上限超過時は FAILED に遷移

## Test Expectations

- **unit**: バックオフ計算、再接続判定ロジック、停止/終了時の再接続抑制
- **widget**: なし
- **integration**: ネットワーク断シミュレーションによる再接続テスト（可能であれば）

## Assumptions

- 再接続の上限回数は明示されていないため、仮に10回とする（**要確認**）

## AI実装適性

**Medium** — バックオフとタイマー制御は定型だが、各クライアントとの結合パターンが複雑

## Human Approval Needed

**Yes** — 再接続上限回数の決定が必要


---

## 完了時の手順

この Issue の実装が完了したら、以下を行うこと:

1. GitHub Issue にコメントで完了報告を記載する
   - 変更したファイル一覧
   - 実装した内容の要約
   - 意図的に実装しなかった内容
   - テスト結果
   - 残存リスク・フォローアップ事項
2. PR 作成時は、PR 本文に GitHub Issue URL を記載する（例: `Closes https://github.com/sahya/comerune/issues/8`）
3. GitHub Issue をクローズする
