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

## Issue Lifecycle
- Do not close issues.
- Only the human owner may close an issue, after confirming that acceptance criteria are met.
- When review or analysis is complete, indicate that the issue is ready for human decision and closure.

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