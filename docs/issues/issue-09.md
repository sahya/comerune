# Issue #9: SelectScreen（接続先選択画面）の実装

Labels: v1.2, ui

GitHub Issue: https://github.com/sahya/comerune/issues/9

Epic: #1

## Goal

放送IDまたはURLを入力して接続を開始する画面を作る。

## Scope

- AppBar（アプリ名「comerune」を表示）
- テキスト入力欄（プレースホルダー「lv番号またはURLを入力」、`TextInputType.url`）
- 接続ボタン（IDLE/STOPPED/FAILED/ENDED で有効、接続中は無効）
- Enter キーで接続開始（IME の送信/完了アクション）
- lv 抽出失敗時の Snackbar 通知（「放送IDが見つかりません」）
- 空入力時はボタン無効化
- 接続成功時の CommentScreen への画面遷移

## Non-scope

- CommentScreen の実装（Issue #10）
- 設定画面の実装（Issue #12）
- フォローリスト表示（将来拡張）

## Dependencies

- Issue #2（LvParser）
- Issue #3（ConnectionSupervisor — 接続開始の呼び出し）

## Acceptance Criteria

- [ ] lv番号を入力して接続ボタンを押すと CommentScreen に遷移する
- [ ] URL を入力して接続ボタンを押すと lv が抽出されて接続される
- [ ] Enter キーで接続が開始される
- [ ] 不正入力時に Snackbar「放送IDが見つかりません」が表示される
- [ ] 空入力時は接続ボタンがグレーアウトする
- [ ] 接続中（CONNECTING〜RECONNECTING）は接続ボタンが無効化される

## Validation / Error Handling

- `LV_PARSE_FAILED` → Snackbar 通知、IDLE のまま

## Test Expectations

- **unit**: なし（LvParser は Issue #2 でテスト済み）
- **widget**: ボタン有効/無効切替、Snackbar表示、Enter キー動作、画面遷移
- **integration**: なし

## Assumptions

なし

## AI実装適性

**High** — 標準的なフォーム画面。仕様が明確

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
2. PR 作成時は、PR 本文に GitHub Issue URL を記載する（例: `Closes https://github.com/sahya/comerune/issues/9`）
3. GitHub Issue をクローズする
