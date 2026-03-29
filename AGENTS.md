# AGENTS.md

## Purpose
This repository is developed with AI agents. Agents must prioritize:
1. preserving architecture consistency
2. implementing only the approved issue scope
3. keeping changes small, testable, and reviewable
4. explaining intent before and after changes

## Required Rule Files
Agents must read and follow:
- `AGENTS.md`
- `.ai/flutter_rules.md`

If instructions conflict, prefer the more restrictive rule unless explicitly overridden by the issue.

## Product Context
- This is a Flutter application.
- The human owner is not expected to design the full architecture by hand.
- Therefore, agents must avoid large structural changes unless explicitly requested.
- If a requirement is ambiguous, do not silently invent product behavior. Record assumptions clearly.

## Default Workflow
For every issue, follow this order:
1. Read the issue document
2. Summarize the goal, scope, non-scope, and acceptance criteria
3. Inspect related files before editing
4. Propose implementation approach briefly
5. Implement only the approved scope
6. Run formatting, static analysis, and tests
7. Summarize changed files, behavior, and any remaining risks

## Architecture Rules
- Respect the existing directory structure and layering.
- Do not introduce a new architecture pattern without approval.
- Do not replace state management, routing, dependency injection, or networking libraries unless the issue explicitly requires it.
- Keep presentation, state, domain logic, and data access concerns separated.
- Do not mix unrelated refactors into feature work.
- Avoid "cleanup" changes unless explicitly requested.

## Dependency Rules
- Do not add a new package unless required by the issue.
- If adding a package is necessary, explain:
  - why it is needed
  - what alternatives were considered
  - what files will depend on it
- Prefer small and well-maintained dependencies.
- Avoid adding multiple packages for a single small feature.

## Change Scope Rules
- One issue should correspond to one main responsibility.
- If the issue appears too large, say so and propose a split before implementation.
- Do not modify unrelated files.
- Do not rename files, folders, public APIs, or core models unless required by the issue.

## Coding Rules
- Follow existing naming, null-safety, and style conventions.
- Prefer simple and explicit code over clever abstractions.
- Keep methods short where practical.
- Add comments only when the intent is not obvious from code.
- Do not leave dead code, commented-out code, or temporary debug statements.

## Testing Rules
For each implementation, agents must consider:
- unit tests for pure logic
- widget tests for UI behavior
- integration tests only when required by the issue

Minimum expectation:
- new logic should have tests when practical
- bug fixes should include a regression test when practical

## Required Pre-Implementation Output
Before writing code, output:
1. Goal
2. Scope
3. Non-scope
4. Files likely to change
5. Risks / assumptions
6. Implementation steps

## Required Post-Implementation Output
After writing code, output:
1. Files changed
2. What was implemented
3. What was intentionally not implemented
4. Test/status results
5. Remaining risks or follow-up suggestions

## Required Commands
Run these if available:
- dart format .
- flutter analyze
- flutter test

If any command cannot be run, state that clearly.

## Review Rules
When reviewing code, classify findings as:
- must fix
- should fix
- optional

Review against:
- issue scope
- acceptance criteria
- architectural consistency
- test sufficiency
- regression risk
- readability and maintainability

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

## Issue Lifecycle
- Agents must not close issues.
- Only the human owner may close an issue, after confirming the implementation satisfies the acceptance criteria.
- When implementation is complete, the agent should state that the issue is ready for human review and closure, not close it directly.

## リリースノート作成ルール

リリースノートを作成する際は、外部公開を前提として以下を遵守すること:

- PR番号・Issue番号を記載しない
- API名・エンドポイント名・内部実装の詳細を記載しない
- ツール固有名（CI/CDツール名、スキャナー名等）を記載しない
- セキュリティ修正の具体的な脆弱性内容を記載しない
- 認証・認可の実装詳細（ストレージ方式、Cookie処理等）を記載しない
- ユーザー向けの平易な表現を使い、技術的パラメータは必要最低限にする
- カテゴリは「新機能」「UI改善」「品質・安定性向上」等のユーザー視点で分類する

## Forbidden Behavior
Agents must not:
- invent major product requirements
- make unapproved architecture migrations
- bundle refactors with feature delivery
- skip explaining assumptions
- claim tests passed if they were not actually run
- mark work complete when acceptance criteria are not satisfied
- close issues on behalf of the human owner