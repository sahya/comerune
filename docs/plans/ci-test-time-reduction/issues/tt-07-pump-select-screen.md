# TT-07: pumpAndSettle 適正化 — select_screen_test.dart

## Goal
`test/presentation/select/select_screen_test.dart`（3,597 行・`pumpAndSettle` 105 箇所・
testWidgets 75 件）の待ち方を spec.md §3.1 の決定表に従って適正化する。

## Scope / Non-scope / Acceptance criteria / Test expectations
TT-04 と同一（対象ファイルのみ読み替え）。手順・ガードはすべて spec.md §3.1 / §5 に従う。

## Dependencies
TT-01。TT-04 完了後（知見引き継ぎ）。TT-05 / TT-06 とは独立に実施可。

## Implementation notes
- このファイルは既に `pump(const Duration(seconds: N))` によるフェイク時間送りを
  多用している（例: 2,600 行目付近）。既存のフェイク時間パターンと整合する形で
  置換すること（フェイク時間は実時間コストゼロなので削減対象ではない）
