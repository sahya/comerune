# TT-06: pumpAndSettle 適正化 — tts_settings_screen_test.dart

## Goal
`test/presentation/screens/tts_settings_screen_test.dart`（3,259 行・`pumpAndSettle`
130 箇所・testWidgets 80 件）の待ち方を spec.md §3.1 の決定表に従って適正化する。

## Scope / Non-scope / Acceptance criteria / Test expectations
TT-04 と同一（対象ファイルのみ読み替え）。手順・ガードはすべて spec.md §3.1 / §5 に従う。

## Dependencies
TT-01。TT-04 完了後（知見引き継ぎ）。TT-05 とは独立に実施可。

## Implementation notes
- 設定画面はスライダー・トグル操作後の状態反映が中心のため、決定表 #1〜#2
  （`pump()` 化）の該当が多い見込み
