# TT-08: pumpAndSettle 適正化 — 残り上位 3 ファイル

## Goal
以下 3 ファイルの待ち方を spec.md §3.1 の決定表に従って適正化する:

- `test/presentation/screens/comment_screen_end_broadcast_menu_test.dart`（78 箇所）
- `test/presentation/screens/settings_screen_test.dart`（57 箇所）
- `test/presentation/widgets/comment_input_bar_test.dart`（46 箇所）

## Scope / Non-scope / Acceptance criteria / Test expectations
TT-04 と同一。ただし本 Issue のみ 3 ファイルを 1 PR で扱う（各ファイルの規模が
小さいため）。計測・件数確認はファイルごとに行い、PR 本文に 3 行で記録する。

## Dependencies
TT-04〜07 の完了後（決定表が十分に成熟してから、まとめて実施する）。

## Implementation notes
- ここまでの TT で `flutter test` 全体の短縮が頭打ち（累計で ±5% 未満）になっている
  場合は、着手前に plan.md の進捗表へその旨を記録し、本 Issue を「効果なし見込み・
  保留」として owner に判断を返してよい（規約適合目的だけで進めるかは owner 判断）
