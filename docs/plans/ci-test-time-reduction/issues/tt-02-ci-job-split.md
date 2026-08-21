# TT-02: CI ジョブ分割（Flutter / Kotlin 並列化）

## Goal
`.github/workflows/test.yml` の単一ジョブを Flutter 系と Kotlin 系の 2 並列ジョブに分割し、
PR CI の wall time を実測 2〜4 分短縮する。テストの内容・実行コマンドは一切変えない。

## Scope
- `test.yml` を spec.md §2.1 の目標形（`check` / `kotlin-test` の 2 ジョブ）に再構成
- JDK セットアップと Gradle cache を `kotlin-test` ジョブへ移動
- ジョブ別 `timeout-minutes`（check: 15 / kotlin-test: 20）の設定
- 既存のコメント（最小権限、supply-chain anchor、`--no-daemon` の理由等）と
  action の SHA ピンをすべて維持

## Non-scope
- 実行コマンド自体の変更（`flutter test` / `gradlew` の引数変更は TT-03）
- paths filter による条件スキップ（別候補。plan.md 参照）
- 新規 action の導入

## Dependencies
なし（TT-01 と並行可）

## Acceptance criteria
- [ ] 2 ジョブが並列に走り、両方 green
- [ ] Flutter 側ジョブの name が現行の required check 名 `Analyze, Format, Test` と一致
- [ ] warm cache の PR で CI 全体が従来比 2 分以上短縮（run のタイムスタンプで確認し
      PR 本文に before/after の run URL を記載）
- [ ] PR 本文に「owner がリポジトリ設定の required checks へ `Kotlin Unit Tests` を
      追加する必要がある」ことが明記されている（この設定変更自体は owner の作業）
- [ ] `permissions: contents: read` / `concurrency` / `persist-credentials: false` /
      SHA ピンが変更されていない

## Test expectations
- ワークフロー変更のため Dart/Kotlin テストの追加は不要
- 検証は本 PR 自身の CI run（並列実行・所要時間）で行う

## Implementation notes
- `github-actions-lint.yml` が workflow を lint するため、push 前に構文に注意
- Kotlin ジョブにも `flutter pub get` が必要（`.flutter-plugins-dependencies` を
  Flutter Gradle プラグインが読む。現行 test.yml のコメント参照）
- 分割により Flutter 側ジョブから gradle cache の保存 post（最大 20 秒程度）も消える
