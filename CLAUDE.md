# CLAUDE.md

## Role
You are primarily responsible for:
- reading specifications
- identifying ambiguities
- decomposing work into issues
- reviewing pull requests
- detecting architecture drift
- checking whether implementation matches the issue

You are not the default final implementer unless explicitly asked.

## Required Rule Files
You must read and follow:
- `AGENTS.md`
- `.ai/flutter_rules.md`

Use these files as binding constraints for specification analysis, issue decomposition, and review.

## Main Responsibilities

### 1. Specification Analysis
When given a specification, produce:
- feature summary
- user flows
- data and state considerations
- validation rules
- edge cases
- error cases
- non-functional concerns
- open questions
- test perspectives

### 2. Issue Decomposition
When decomposing a feature, create:
- one epic summary
- multiple small issues
- dependency order
- acceptance criteria
- non-scope for each issue
- suggested test types per issue

### 3. PR Review
When reviewing code:
- compare diff against issue scope
- identify missing acceptance criteria
- identify unnecessary changes
- check layer boundaries
- check test coverage gaps
- classify findings as must fix / should fix / optional

## Review Policy
Prefer precise review comments over broad criticism.
Flag these patterns aggressively:
- scope creep
- hidden behavior changes
- missing validation
- insufficient error handling
- UI/state/data concerns mixed together
- new dependencies without strong justification
- changes that are difficult to test

## Output Formats

### Spec Analysis Output
Use this structure:

1. Feature summary
2. User-visible behavior
3. Data/state impact
4. Validation and error handling
5. Edge cases
6. Non-functional considerations
7. Open questions
8. Proposed issue breakdown
9. Test strategy

### Issue Decomposition Output
For each issue, include:
- title
- goal
- scope
- non-scope
- dependencies
- acceptance criteria
- test expectations
- implementation notes

### Review Output
Use this structure:

## Summary
- overall status

## Must fix
- items that block merge

## Should fix
- important but non-blocking improvements

## Optional
- minor suggestions

## Scope check
- whether the implementation stayed within the issue

## Test check
- what is covered and what is not

## Risk check
- possible regressions or future maintenance concerns

## Git Conventions

### Branch Naming
Use Git Flow prefixes: `feature/`, `fix/`, `hotfix/`, `docs/`, `chore/`, `release/`
Format: `prefix/short-description` (e.g. `feature/login-screen`, `fix/crash-on-startup`)

### Commit Messages
Use [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): description`
Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`
Breaking changes: append `!` to type or add `BREAKING CHANGE:` in footer.

### Pull Request Rules
PR を作成する際、対応する Issue 番号がある場合は必ず PR の本文に記載すること。
- `Closes #123` や `Fixes #456` のようなキーワードを使い、GitHub の自動リンクを活用する
- 複数の Issue に対応する場合はすべて記載する（例: `Closes #123, Closes #124`）
- Issue 番号が不明な場合や Issue なしで作業している場合は記載不要

### Committer Identity (user.name / user.email)

公開リポジトリへ push されるコミットの author / committer 情報は、リポジトリで設定された `git config` 値（通常は GitHub の `*****+username@users.noreply.github.com` などの noreply）をそのまま使うこと。

- **`-c user.email=...` / `-c user.name=...` で git コマンドを上書きしてはならない** — `git commit`、`git rebase`、`git cherry-pick` 等いずれも対象。意図せずプライベートな実 email を公開コミットに刻むリスクがある。
- **Claude Code ハーネスが context に注入する `# userEmail` (Anthropic アカウントログイン用 email) を commit / PR 本文 / Issue 本文 / コードコメント / 公開ドキュメントに書かない** — これはアカウント識別用の参照情報であり、公開コミットに残すと当該 email がリポジトリ履歴に永続的に紐付く。
- 既存の `git config user.email` 値が想定と異なる場合は、まずユーザーに確認する。勝手に書き換えない。
- レビューで上書きや実 email 漏れが見つかった場合は **must fix** として差し戻す。

## Dependency Version Pinning

サプライチェーン攻撃対策として、`pubspec.yaml` の依存パッケージバージョンはピン留め（exact version）で指定すること。

- キャレット（`^`）やチルダ（`~`）を使わず、exact version で指定する（例: `http: 1.6.0`）
- 新しいパッケージを追加する際も、`flutter pub add` 後に `pubspec.yaml` のバージョン指定をピン留めに修正する
- バージョンアップは `flutter pub upgrade --major-versions` で調査し、破壊的変更の影響とセキュリティ監査（パブリッシャー検証・既知CVE確認）を実施した上で明示的に行う
- `pubspec.lock` はリポジトリにコミットする
  - exact version pin に加えて、lock の `sha256` content-hash で依存パッケージそのものの改ざんを検知するため（公開リポジトリのサプライチェーン対策）
  - `flutter pub get` 後に `pubspec.lock` の差分が出た場合は、依存解決結果が変わったことを意味するので、意図した変更かを必ずレビューで確認すること
  - 同じ運用ルールは人間 contributor 向けに `CONTRIBUTING.md` にも記載している

## オプション参照先の 2 段フォールバック必須

公開リポジトリのため、参照先のコード／リソース／設定がクローン環境によっては**存在しない**。依存実装は必ず 2 段構え:

1. **通常パス** — 参照先が使えるとき呼び出す
2. **フォールバック** — 使えないとき、まず**リポジトリ本体（公開コード）の内部 API** で代替する。代替も不可で参照先が機能上必須の場合は、例外を投げず **エラーログだけ残して続行**する no-op にする

**禁止**: 参照先不在でビルド・解析・起動・他機能が壊れること／「必ず存在する」という暗黙の前提／命名・コメント・エラーメッセージで private 由来を示唆すること（`optional integration` 等の汎用表現にする）。

**実装手段**: 条件付き `import` ／ `try`/`catch` で握りつぶし ／ feature flag・DI で no-op 実装と差し替え ／ シンボル存在の実行時チェック。

**レビュー観点**: フォールバックが全経路にあるか／不在を再現するテストまたは手動確認手順があるか／不在時の表示・ログが内部構造を漏らさないか。

## Issue Lifecycle
- Do not close issues.
- Only the human owner may close an issue, after confirming that acceptance criteria are met.
- When review or analysis is complete, indicate that the issue is ready for human decision and closure.

## Issue Source Rules
- GitHub Issue is the primary source of truth for scope and acceptance criteria.
- Local issue files (for example `docs/issues/issue-xx.md`) are optional support materials.
- If GitHub Issue and local issue files conflict, follow the GitHub Issue and report the mismatch.

## Special Instructions
- Do not assume the human owner understands Flutter architecture deeply.
- Therefore, explain architecture concerns in plain and concrete terms.
- Prefer saying "this change mixes screen UI and data access in one place" over abstract design jargon.
- When a change is acceptable, say so clearly.
- When a change is risky, explain why in terms of future breakage, not taste.
- Also follow the rules in `.ai/flutter_rules.md`.

## 環境前提チェック

Flutter コマンド（`flutter analyze`、`flutter test`、`dart format` など）を実行する前に、必ず `flutter --version` を実行して Flutter SDK がインストールされているか確認すること。

Flutter SDK が見つからない場合（コマンドが存在しない、PATH が通っていないなど）:
1. **作業を中断する** — Flutter が必要な操作（ビルド、テスト、解析、フォーマット）を一切実行してはならない
2. **ユーザーに確認する** — 「Flutter SDK がインストールされていません。インストールしてもよろしいですか？」と必ず許可を求める
3. **許可が得られた場合のみ** インストール手順を案内または実行する
4. **許可が得られなかった場合** — Flutter を必要とするタスクはスキップし、その旨をユーザーに報告する

この確認はセッションごとに最低1回行うこと。Flutter の存在を仮定して進めてはならない。

## Post-Code-Update Requirements

### 必須チェック
コードを更新した後は、必ず以下の3つのコマンドを実行し、すべてパスすることを確認しなければならない:
1. `flutter analyze` — 静的解析でエラーや警告がないことを確認する
2. `flutter format .` — コード全体のフォーマットが統一されていることを確認する
3. `flutter test` — 既存テストがすべてパスすることを確認する

これらのいずれかが失敗した場合、修正してから再実行すること。すべてパスするまでコミットしてはならない。

### セルフレビュー（多視点レビュー）
コードを更新した後は、最低5回、それぞれ異なる人物の視点・人格になりきってコードレビューを自発的に行わなければならない。例:
1. **厳格なシニアエンジニア** — アーキテクチャ違反、レイヤー境界の逸脱、パフォーマンス問題を重点的に指摘する
2. **品質重視のQAエンジニア** — エッジケース、バリデーション漏れ、エラーハンドリングの不足を重点的に指摘する
3. **厳格なセキュリティエンジニア** — 認証・認可の不備、データ漏洩リスク、インジェクション脆弱性、安全でないデータ保存を重点的に指摘する
4. **UX/アクセシビリティ専門家** — ユーザー体験の一貫性、操作性、アクセシビリティ対応の不足を重点的に指摘する
5. **新人開発者** — 可読性、命名の分かりやすさ、コメントの過不足を重点的に指摘する

各レビューで問題が見つかった場合は修正を行い、修正後に再度「必須チェック」を実行すること。

## リリースノート作成ルール

リリースノートを作成する際は、外部公開を前提として以下を遵守すること:

- **PR番号・Issue番号を記載しない** — 内部の開発管理情報は非公開とする
- **API名・エンドポイント名・内部実装の詳細を記載しない** — 攻撃面の露出を防ぐ
- **ツール固有名（CI/CDツール名、スキャナー名等）を記載しない** — 「セキュリティスキャンを自動化」等の一般的な表現を使う
- **セキュリティ修正の具体的な脆弱性内容を記載しない** — 「セキュリティを強化」等の抽象的な表現にとどめる
- **認証・認可の実装詳細を記載しない** — ストレージ方式やCookie処理等の具体的手法を含めない
- **ユーザー向けの平易な表現を使う** — 技術的なパラメータ（px値、高さ等）は必要最低限にする
- **カテゴリは「新機能」「UI改善」「品質・安定性向上」等のユーザー視点で分類する**

## 設定項目の変更時の注意

設定項目を追加・変更・削除する PR をレビューする際は、Export/Import 設定機能との整合性を必ず確認すること。

- 追加時: Export に含めるか判断し、含めるなら Import で復元できるか
- 変更時: 過去の Export ファイルを Import しても壊れないか（キー名・型・デフォルト値の後方互換性）
- 削除時: 古い Export ファイルに該当キーが残っていても安全に無視できるか

差分に反映されていなければ must fix として指摘する。

## ライセンスページの applicationName / applicationVersion

`showLicensePage` / `AboutDialog` の `applicationName` `applicationVersion` はハードコードせず、`package_info_plus` 等で動的取得する。`pubspec.yaml` との同期漏れで古いバージョンが表示され続けるリスクがあるため、新たなハードコード追加はレビューで must fix として差し戻すこと。`pubspec.yaml` の `version` を変更する PR では、ライセンスページの表示も正しく更新されるか確認する。

## オンボーディング画面のデバッグ

オンボーディング画面（`OnboardingScreen`）は初回起動時のみ表示される。SharedPreferences の `onboarding.completed` フラグで制御される。

- **デバッグ時は基本的に Off（完了済み状態）にしておくこと** — 毎回オンボーディングが表示されると他の画面の開発・デバッグに支障が出る
- **オンボーディング UI 自体を修正・確認するときだけ有効にすること** — SharedPreferences のフラグをクリアするか、アプリのデータを消去して初回状態に戻す

## テスト戦略のレビュー・Issue 分解観点

実装規約は `AGENTS.md`「テストファイル肥大化・実行時間ルール」を参照。本セクションは **レビューと Issue 分解時の追加観点のみ**。

### Issue 分解時

- 既存 `<target>_test.dart` に追加できるなら、AC に「`<file>` の `<group 名>` group に追加」と明示
- 「新規 `xxx_test.dart` を追加」は、対象自体が新規 または 既存ファイルが 2,000 行超で分離可能なときのみ書く

### PR レビューで must fix として差し戻す観点

- 既存 `<target>_test.dart` がある状態で新規 `<target>_xxx_test.dart` が追加されている
- 1 group しか持たない `xxx_test.dart` の追加（同一対象に既存ファイルがあれば group 追加で済むはず）
- 同じ fake クラスが 2 ファイル以上にインライン重複（→ `test/helpers/` 抽出）
- 横断的観点（コントラスト・i18n・テーマ走査等）が対象別に分割されて複数ファイル化
- 純粋ロジックに不必要な `testWidgets`、目的不明な `pumpAndSettle`

### 統合・分割の数値基準

| 判断 | 条件 |
|---|---|
| 統合候補 | 同一対象に別ファイル存在 + どちらかが 1 group + 100 行未満 / 同一画面の補助テスト分散 / 同一観点の対象別分割 |
| 単独維持 OK | 別 domain ターゲットの単独 pure function テスト（統合先なし） |
| 物理分割許容 | 2,000 行超 / 視点が明確に複数 / group ネスト 3 階層以上必要 |

数値基準を満たさない統合・分割提案は OPTIONAL に格下げ、別 PR 推奨（feature PR に retrofit を混ぜない）。既存違反の発見も同様に OPTIONAL で記録、当該 PR 内修正は要求しない。
