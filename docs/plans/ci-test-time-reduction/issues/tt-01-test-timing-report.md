# TT-01: テスト実行時間の計測レポート基盤

## Goal
`flutter test` のファイル別実行時間と総件数を機械的に取得できるようにし、
以降の全 TT Issue の効果測定と件数ガードの共通基盤を作る。

## Scope
- `scripts/test_timing_report.dart` を新規追加（仕様: spec.md §4。標準ライブラリのみ）
- `Makefile` に `test-timing` ターゲットを追加
- （任意）CI の `Run tests` ステップを `--file-reporter json:` 付きに変更し、
  step summary にファイル別時間の上位を出力
- ベースライン計測結果（ローカルまたは CI）を PR 本文に記録

## Non-scope
- テストコードの変更（1 行も変更しない）
- 新規パッケージの追加（禁止）
- 時間バジェットによる fail / warning 機構（別途候補として plan.md に記載済み）

## Dependencies
なし（最初に実施する）

## Acceptance criteria
- [ ] `make test-timing` がファイル別所要時間の降順表と総件数を出力する
- [ ] スクリプトは `pubspec.yaml` に変更を加えていない
- [ ] `flutter analyze` / `make format` / `flutter test` 全パス、テスト件数不変
- [ ] ファイル別時間の上位 20 とファイルあたり固定オーバーヘッドの見積もり
      （小さいファイルの所要時間の分布から推定）が PR 本文に記録されている
      （TT-10 の実測ゲートで使う）

## Test expectations
- スクリプト自体の単体テスト: `test/scripts/` に JSON フィクスチャを使った
  パーステストを 1 ファイル追加（`test/scripts/test_timing_report_test.dart`、
  pure Dart なので `test()` で書く）

## Implementation notes
- JSON reporter のイベント形式は `package:test` の JSON reporter プロトコルに従う
  （`suite` / `testStart` / `testDone` / `done`。`testDone.time` は run 開始からの ms）
- スイート時間の近似方法は spec.md §4 のとおり。厳密さより安定した比較可能性を優先
