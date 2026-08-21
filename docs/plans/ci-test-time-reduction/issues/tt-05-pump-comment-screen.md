# TT-05: pumpAndSettle 適正化 — comment_screen_test.dart

## Goal
`test/presentation/screens/comment_screen_test.dart`（9,042 行・`pumpAndSettle`
187 箇所・testWidgets 204 件）の待ち方を spec.md §3.1 の決定表に従って適正化する。

## Scope / Non-scope / Acceptance criteria / Test expectations
TT-04 と同一（対象ファイルのみ読み替え）。手順・ガードはすべて spec.md §3.1 / §5 に従う。

## Dependencies
TT-01。TT-04 の完了後に着手（決定表へ追記された知見を引き継ぐため）。

## Implementation notes
- このファイルはメニュー・ダイアログ操作の flow が多く、決定表 #4（遷移完了待ち →
  維持）の比率が高い見込み。維持判断を無理に減らさないこと
- 9,000 行超のため、group 単位で区切って作業し、1 コミットに収まらない場合も
  PR は 1 本にまとめる（レビュー単位を issue と一致させる）
