# Issue #18: リポジトリのセキュリティ設定強化

Labels: chore, security

Epic: #1

## Goal

GitHub リポジトリの設定・CI ワークフロー・自動化ツールを活用して、サプライチェーン攻撃の防止、依存パッケージの自動更新、ブランチ保護、シークレット漏洩検知などのセキュリティ対策を導入する。

## Background

現時点で以下のリポジトリレベルのセキュリティ対策が未整備:

1. **GitHub Actions のアクション参照がタグ指定** — `actions/checkout@v4` のようなタグ指定はタグの上書きによるサプライチェーン攻撃に脆弱。コミット SHA での固定が推奨される
2. **Dependabot が未設定** — 依存パッケージ（pub, GitHub Actions）の脆弱性アラートや自動更新 PR が生成されない
3. **ブランチ保護ルールが未設定** — main ブランチへの直接プッシュが可能な状態
4. **GitHub Actions の権限がデフォルト** — ワークフローに必要最小限の権限が明示されていない
5. **CODEOWNERS が未設定** — PR のレビュー担当が自動アサインされない
6. **Secret scanning の明示的有効化が未確認**

## Scope

### 1. GitHub Actions のアクション参照をコミット SHA で固定

Issue #16 で導入予定の `.github/workflows/flutter_ci.yml` において:

- `actions/checkout@v4` → `actions/checkout@<full-sha>` に変更
- `subosito/flutter-action@v2` → `subosito/flutter-action@<full-sha>` に変更
- SHA の横にバージョンタグをコメントとして併記する（可読性のため）

```yaml
# 例
- uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11 # v4.1.1
- uses: subosito/flutter-action@44ac965b96f18d999802d4b807e3256d5a3f9fa1 # v2.16.0
```

### 2. Dependabot の設定

`.github/dependabot.yml` を作成し、以下を設定:

- **pub** パッケージの weekly 自動更新チェック
- **GitHub Actions** の weekly 自動更新チェック
- PR のラベル自動付与（`dependencies`）
- レビュアーの自動アサイン

### 3. ブランチ保護ルールの設定

main ブランチに以下の保護を適用:

- PR 経由のマージを必須化（直接プッシュの禁止）
- 1 名以上のレビュー承認を必須化
- CI ステータスチェックのパスを必須化（Issue #16 の CI が前提）
- force push の禁止
- ブランチ削除の禁止

### 4. GitHub Actions の権限最小化

ワークフローファイルに `permissions` を明示:

```yaml
permissions:
  contents: read
```

リポジトリ設定でデフォルトの GITHUB_TOKEN 権限を `read` に変更する。

### 5. CODEOWNERS の設定

`.github/CODEOWNERS` を作成:

```
# デフォルトレビュアー
* @sahya
```

### 6. Secret scanning / Push protection の有効化確認

- GitHub の「Code security and analysis」設定で以下が有効であることを確認:
  - Secret scanning
  - Push protection（シークレットを含むプッシュをブロック）
  - Dependabot alerts
  - Dependabot security updates

### 7. CI での脆弱性スキャン統合

`.github/workflows/flutter_ci.yml`（Issue #16）に脆弱性スキャンステップを追加:

```yaml
- name: Check outdated dependencies
  run: dart pub outdated
  continue-on-error: true  # 情報提供のみ、ブロックしない

- name: Run OSV Scanner
  uses: google/osv-scanner-action/osv-scanner-action@<sha>
  with:
    scan-args: |-
      --lockfile=pubspec.lock
  continue-on-error: true  # 初期は警告のみ
```

## Non-scope

- GitHub Advanced Security の有料機能（Code scanning / CodeQL）
- デプロイキーやサービスアカウントの管理
- GitHub Environments の設定（デプロイフローが未定のため）
- 署名付きコミットの強制（gpg-sign）
- IP 許可リストの設定

## Dependencies

- Issue #16（GitHub Actions CI の導入）— CI ワークフローが存在することが前提
- Issue #17（アプリケーションセキュリティ）— pubspec.lock のコミットが完了していること

## Target Files / Areas

| ファイル / ディレクトリ | 変更内容 |
|------------------------|---------|
| `.github/workflows/flutter_ci.yml` | アクション SHA 固定、permissions 追記、脆弱性スキャン追加 |
| `.github/dependabot.yml`（新規） | Dependabot 設定 |
| `.github/CODEOWNERS`（新規） | コードオーナー設定 |

## Acceptance Criteria

- [ ] GitHub Actions の全アクション参照がコミット SHA で固定されている
- [ ] `.github/dependabot.yml` が作成され、pub と GitHub Actions の更新チェックが設定されている
- [ ] main ブランチに保護ルールが適用されている（PR 必須、レビュー必須、CI 必須）
- [ ] ワークフローに `permissions: contents: read` が明示されている
- [ ] `.github/CODEOWNERS` が作成されている
- [ ] Secret scanning と Push protection が有効であることが確認されている
- [ ] CI に脆弱性スキャンステップが追加されている（continue-on-error で警告のみ）

## Validation / Error Handling

- Dependabot 設定は YAML のバリデーションエラーが出やすいため、GitHub 上で設定ファイルが正しくパースされることを確認する
- ブランチ保護は適用後にテスト PR で動作確認する
- 脆弱性スキャンは `continue-on-error: true` で導入し、安定したら `false` に切り替える

## Test Expectations

- **unit**: なし（設定ファイルの変更のため）
- **widget**: なし
- **integration**: なし
- **手動確認**:
  - Dependabot が PR を生成することを確認（設定後の次回スキャンサイクルで）
  - ブランチ保護が main への直接プッシュをブロックすることを確認
  - CI ワークフローでアクションが SHA 指定で正しく解決されることを確認
  - CODEOWNERS によりレビュアーが自動アサインされることを確認

## Constraints

- Issue #16 の CI ワークフローが先に導入されていること（または同一 PR で対応）
- リポジトリ設定の変更（ブランチ保護、Secret scanning）は GitHub Web UI での手動設定が必要
- Dependabot の動作確認には設定後 24 時間以内の自動実行を待つ必要がある

## Implementation Notes

### dependabot.yml の設定例

```yaml
# .github/dependabot.yml
version: 2
updates:
  # Dart/Flutter パッケージ
  - package-ecosystem: "pub"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
    labels:
      - "dependencies"
    reviewers:
      - "sahya"
    open-pull-requests-limit: 10

  # GitHub Actions
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
    labels:
      - "dependencies"
      - "ci"
    reviewers:
      - "sahya"
    open-pull-requests-limit: 5
```

### ブランチ保護の設定手順

GitHub Web UI で設定:

1. Settings → Branches → Add branch protection rule
2. Branch name pattern: `main`
3. 有効にする項目:
   - ✅ Require a pull request before merging
     - ✅ Require approvals (1)
   - ✅ Require status checks to pass before merging
     - ✅ Require branches to be up to date before merging
     - Status check: `ci`（Issue #16 のジョブ名）
   - ✅ Do not allow force pushes
   - ✅ Do not allow deletions

### GitHub リポジトリセキュリティ設定の確認手順

Settings → Code security and analysis:

1. **Dependabot alerts**: Enable
2. **Dependabot security updates**: Enable
3. **Secret scanning**: Enable
4. **Push protection**: Enable
5. **GitHub Actions permissions**:
   - Actions → General → Workflow permissions → Read repository contents（デフォルトを制限）

## AI実装適性

**Medium** — ファイルの作成・編集は AI で対応可能。ただし GitHub Web UI での設定（ブランチ保護、Secret scanning）はオーナーの手動操作が必要

## Human Approval Needed

**Yes** — 以下はオーナーの手動対応が必要:
- ブランチ保護ルールの設定（GitHub Web UI）
- Secret scanning / Push protection の有効化（GitHub Web UI）
- GitHub Actions のデフォルト権限変更（GitHub Web UI）
- CODEOWNERS のレビュアー指定の確認
- 脆弱性スキャンを `continue-on-error: false` に切り替えるタイミングの判断

---

## 完了時の手順

この Issue の実装が完了したら、以下を行うこと:

1. GitHub Issue にコメントで完了報告を記載する
   - 変更したファイル一覧
   - 実装した内容の要約
   - GitHub Web UI での手動設定が必要な項目のチェックリスト
   - 意図的に実装しなかった内容
   - 残存リスク・フォローアップ事項
2. PR 作成時は、PR 本文に GitHub Issue URL を記載する
3. GitHub Issue をクローズしない（オーナーが確認後にクローズする）