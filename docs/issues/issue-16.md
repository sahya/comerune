# Issue #16: GitHub Actions による Flutter CI の導入

Labels: chore, ci

GitHub Issue: https://github.com/sahya/comerune/issues/16

Epic: #1

## Goal

プルリクエストおよびメインブランチへのプッシュ時に、Flutter の静的解析・フォーマットチェック・テストを自動実行する GitHub Actions ワークフローを導入する。

## Scope

- `.github/workflows/flutter_ci.yml` の新規作成
- 以下の3ステップを CI で実行する:
  1. `dart format . --set-exit-if-changed`（フォーマット違反を検出）
  2. `flutter analyze`（静的解析）
  3. `flutter test`（ユニット・ウィジェットテスト）
- トリガー: `push` および `pull_request`（対象ブランチ: `main`）
- Flutter バージョンは `pubspec.yaml` の `environment.sdk` 制約に合わせた stable チャンネルを使用

## Non-scope

- integration テストの CI 実行（実機・エミュレータ不要）
- コードカバレッジのレポート・アップロード
- デプロイ・リリースの自動化
- キャッシュの最適化（初版は省略可）

## Dependencies

- なし（他 Issue に依存しない独立した chore）

## Acceptance Criteria

- [ ] `dart format . --set-exit-if-changed` がフォーマット違反のあるコードで CI を失敗させる
- [ ] `flutter analyze` が警告・エラーのあるコードで CI を失敗させる
- [ ] `flutter test` が失敗するテストがある場合に CI を失敗させる
- [ ] すべて通過するコードで CI が緑になる
- [ ] ワークフローが `push` と `pull_request` の両方でトリガーされる

## Validation / Error Handling

- 各ステップは独立して失敗ログを出力する（`continue-on-error: false` のデフォルト動作）
- `flutter pub get` の失敗はそれ自体がジョブ失敗として表面化する

## Test Expectations

- **unit**: なし（CI 設定ファイルのため）
- **widget**: なし
- **integration**: なし
- **手動確認**: ワークフローファイルを push して GitHub Actions の実行結果を目視確認

## Implementation Notes

```yaml
# .github/workflows/flutter_ci.yml の骨格例
name: Flutter CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      - run: dart format . --set-exit-if-changed
      - run: flutter analyze
      - run: flutter test
```

- `subosito/flutter-action@v2` を使用（最も広く使われている Flutter セットアップ Action）
- `flutter-version` は省略し `channel: stable` で最新 stable を使用。固定が必要なら `pubspec.yaml` の SDK 制約に合わせて指定する

## Assumptions

- リポジトリは GitHub 上でホストされており、GitHub Actions が有効である
- `flutter test` が実行できるテストファイルが存在する（存在しない場合、ステップはスキップされるか空のテスト結果で成功する）

## AI実装適性

**High** — 設定ファイルの新規作成のみ。ロジック変更なし

## Human Approval Needed

**Yes** — GitHub Actions の実行結果をオーナーが目視確認し、CI が正しく動作することを確認する

---

## 完了時の手順

この Issue の実装が完了したら、以下を行うこと:

1. GitHub Issue にコメントで完了報告を記載する
   - 変更したファイル一覧
   - 実装した内容の要約
   - 意図的に実装しなかった内容
   - テスト結果
   - 残存リスク・フォローアップ事項
2. PR 作成時は、PR 本文に GitHub Issue URL を記載する（例: `Closes https://github.com/sahya/comerune/issues/16`）
3. GitHub Issue をクローズしない（オーナーが確認後にクローズする）
