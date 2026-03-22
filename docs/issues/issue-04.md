# Issue #4: TimelineStore（リングバッファ付きコメント管理）の実装

Labels: v1.2, model

GitHub Issue: https://github.com/sahya/comerune/issues/4

Epic: #1

## Goal

コメントをリングバッファで保持し、重複排除してUIに流す仕組みを作る。

## Scope

- リングバッファ（既定100件、設定で 100/500/1000/10000 に変更可能）
- コメントの追加（古いものから破棄）
- `AppMessage.id` による重複排除
- コメント一覧の取得（古い順）
- コメントクリア機能（別 lv 接続時用）
- 変更通知（ChangeNotifier 等）

## Non-scope

- UI表示（Issue #9 で実装）
- コメントの取得処理（NDGR/legacy クライアントが行う）

## Dependencies

- Issue #2（AppMessage モデル）

## Acceptance Criteria

- [ ] コメントを追加でき、古い順に取得できる
- [ ] バッファ上限に達すると古いものから破棄される
- [ ] 同一 id のコメントは重複追加されない
- [ ] バッファ上限を変更できる
- [ ] コメント一覧をクリアできる

## Validation / Error Handling

- バッファ上限は1以上の値のみ受け付ける

## Test Expectations

- **unit**: 追加・取得・重複排除・上限破棄・クリア・上限変更
- **widget**: なし
- **integration**: なし

## Assumptions

なし

## AI実装適性

**High** — データ構造の実装。仕様が明確

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
2. PR 作成時は、PR 本文に GitHub Issue URL を記載する（例: `Closes https://github.com/sahya/comerune/issues/4`）
3. GitHub Issue をクローズする
