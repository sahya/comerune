# TT-10: 小ファイル統合の実測評価（isolate オーバーヘッド削減）

## Goal
`flutter test` は 1 ファイル = 1 isolate（AGENTS.md）であり、157 ファイルには
ファイル数比例の固定費がある。TT-01 の実測データで固定費を定量化し、
`CLAUDE.md`「統合・分割の数値基準」を満たす統合候補**のみ**を統合する。

## Scope
- ステップ 1（評価）: TT-01 のレポートから 1 ファイルあたり固定費を推定し、
  統合候補一覧（`CLAUDE.md` の基準表に適合するもの）と削減見込みを作成して
  **owner の承認を得る**（見込み 10 秒未満なら「実施しない」と結論して終了）
- ステップ 2（実施。承認後のみ）: spec.md §3.5 の手順で候補を統合。
  1 PR あたり統合 3 組まで

## Non-scope
- 2,000 行超のファイル（comment_screen_test 等）への追記・統合
- テスト本文の編集（group の verbatim 移動と import 整理のみ許可）
- 基準表を満たさないファイルの統合（「ついで統合」禁止)

## Dependencies
TT-01（必須）。TT-04〜09 完了後（対象ファイルが安定してから）。

## Acceptance criteria
- [ ] 評価結果（固定費の実測値・候補一覧・削減見込み）が Issue コメントまたは
      PR 本文に記録され、owner の Go/No-Go 判断を得ている
- [ ] （実施時）テスト件数一致に加え、**テスト名一覧の完全一致**を JSON レポートの
      突き合わせで確認している
- [ ] （実施時）`flutter test` 全体時間の before/after が記録されている
- [ ] plan.md §5 の進捗表が更新されている

## Test expectations
- 既存テスト全パス + テスト名一覧一致（本 Issue のみ強化ガード）

## Implementation notes
- 候補例（基準表への適合を評価すること。ここでの列挙は確定ではない）:
  同一画面の補助テストが分散している `comment_screen_auto_extend_menu_test.dart` と
  `comment_screen_auto_extend_behavior_test.dart` の関係など
- 統合先が 2,000 行を超える場合はその候補を除外する
