# Issue #10: CommentScreen（コメント閲覧画面）の実装

Labels: v1.2, ui

GitHub Issue: https://github.com/sahya/comerune/issues/10

Epic: #1

## Goal

接続中の放送のコメント一覧、ステータスバー、操作ボタンを表示する画面を作る。

## Scope

- AppBar（lv 表示、オーバーフローメニュー ⋮ で設定画面への導線）
- ステータスバー:
  - Wi-Fiアイコン色（緑/赤）
  - 通常表示（lv、最終受信時刻、再接続回数、直近エラー）
  - デバッグモード時の追加表示（接続方式、接続フェーズ）
- コメント一覧（`ListView.builder`、古い順、自動スクロール）
  - 自動スクロール停止（ユーザーが上方向にスクロール中）
  - 最下部に戻ると自動スクロール再開
  - コメント種別の背景色区別（chat: 通常、operator: 薄い黄色、notification: 薄い青色）
  - 「legacy: 未対応フォーマット」のシステム行表示
- 操作ボタン:
  - 接続中: 「接続停止」ボタン → STOPPED → SelectScreen に戻る
  - ENDED/FAILED: 「再接続」ボタン → 同一 lv で再接続
- 戻る操作時の全接続停止
- 同一 lv 再接続時のコメント保持、別 lv 接続時のクリア

## Non-scope

- 設定画面の実装（Issue #12）
- 読み上げ処理（Issue #11）
- コメント行のタップ操作（v1.2 未割当）

## Dependencies

- Issue #3（ConnectionSupervisor — 状態監視）
- Issue #4（TimelineStore — コメント一覧データ）
- Issue #9（SelectScreen — 画面遷移元）

## Acceptance Criteria

- [ ] Wi-Fiアイコンが状態に応じて緑/赤で表示される
- [ ] ステータスバーに lv / 最終受信時刻 / 再接続回数 / 直近エラーが表示される
- [ ] デバッグモード ON 時に接続方式・接続フェーズが追加表示される
- [ ] コメントが古い順に一覧表示される
- [ ] 新着コメントで自動スクロールする
- [ ] ユーザーが上にスクロールすると自動スクロールが停止する
- [ ] 最下部に戻ると自動スクロールが再開する
- [ ] operator コメントが薄い黄色背景で表示される
- [ ] notification コメントが薄い青色背景で表示される
- [ ] 接続停止ボタンで全停止し SelectScreen に戻る
- [ ] ENDED/FAILED で再接続ボタンが表示される
- [ ] 戻る操作で全接続が停止される
- [ ] 同一 lv 再接続時はコメントが保持される
- [ ] 別 lv 接続時はコメントがクリアされる

## Validation / Error Handling

- FAILED 遷移時に Snackbar で原因カテゴリを表示
- 断続的エラーはデバッグ欄更新のみ（Snackbar は出さない）

## Test Expectations

- **unit**: なし
- **widget**: Wi-Fiアイコン色、ステータスバー表示、ボタン有効/無効、自動スクロール動作、コメント種別の背景色、再接続ボタン表示
- **integration**: なし

## Assumptions

- `FAB（新着あり）` の実装は推奨事項であり、実装判断に委ねる

## AI実装適性

**Medium** — UIの状態マトリクスが多い。自動スクロール制御は実装上の考慮が必要

## Human Approval Needed

**Yes** — UI の見た目（配色、レイアウト）について確認が望ましい


---

## 完了時の手順

この Issue の実装が完了したら、以下を行うこと:

1. GitHub Issue にコメントで完了報告を記載する
   - 変更したファイル一覧
   - 実装した内容の要約
   - 意図的に実装しなかった内容
   - テスト結果
   - 残存リスク・フォローアップ事項
2. PR 作成時は、PR 本文に GitHub Issue URL を記載する（例: `Closes https://github.com/sahya/comerune/issues/10`）
3. GitHub Issue をクローズする
