# TT-04: pumpAndSettle 適正化 — comment_screen_speech_test.dart

## Goal
`test/presentation/screens/comment_screen_speech_test.dart`（6,232 行・`pumpAndSettle`
214 箇所・testWidgets 122 件）の待ち方を spec.md §3.1 の決定表に従って適正化し、
実行時間を短縮する。アサーション・テスト意図は一切変えない。

## Scope
- 対象ファイル 1 本のみ。決定表 #1〜#3 に該当する `pumpAndSettle()` サイトを
  `pump()` / `pump(Duration)` へ置換
- 決定表 #4〜#6 該当サイトは維持（維持数と代表理由を PR 本文に記録）
- spec.md §1.3 の計測（before/after、3 回中央値）

## Non-scope
- 他のテストファイル・`lib/` の変更
- expect の変更、テストの統合・並べ替え・リネーム
- sed 等による一括置換（サイトごとの判断が必須）

## Dependencies
TT-01（計測基盤。件数確認とファイル別時間の取得に使う）

## Acceptance criteria
- [ ] テスト件数 before == after（JSON レポートで確認、PR 本文に記載）
- [ ] `flutter analyze` / `make format` / `flutter test` 全パス
- [ ] 対象ファイル単体の実行時間 before/after（中央値）が PR 本文に記録され、
      改善または「効果なし（±5% 未満）」が明示されている
- [ ] `git diff --stat` の変更ファイルが対象ファイル（+ plan.md 進捗表 + 必要なら
      spec.md 決定表への知見追記）のみ
- [ ] plan.md §5 の進捗表が更新されている

## Test expectations
- 既存テスト全パスが唯一の検証。新規テスト追加は不要

## Implementation notes
- この画面のテストは読み上げ（speech）のタイマー・キュー処理を多く含むため、
  決定表 #3（Timer 消化 → `pump(該当 Duration)`）の該当が多い見込み。
  タイマー間隔はプロダクションコードの定数を参照して Duration を決めること
- 置換 → group 単位で実行 → fail したテストだけ戻す、の反復手順は spec.md §3.1
- 得られた判断知見は spec.md の決定表の備考へ追記し、TT-05 以降に引き継ぐ
