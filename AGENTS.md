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

If `AGENTS.local.md` exists at the repository root, agents must also read and follow it as a supplemental private rule file.
If instructions conflict, prefer direct user/developer instructions first; otherwise prefer the more restrictive repository rule unless explicitly overridden by the issue.

## Product Context
- This is a Flutter application.
- The human owner is not expected to design the full architecture by hand.
- Therefore, agents must avoid large structural changes unless explicitly requested.
- If a requirement is ambiguous, do not silently invent product behavior. Record assumptions clearly.

## Default Workflow
For every issue, follow this order:
1. Read the GitHub Issue first (URL or issue number)
2. Summarize the goal, scope, non-scope, and acceptance criteria
3. Inspect related files before editing
4. Propose implementation approach briefly
5. Implement only the approved scope
6. Run formatting, static analysis, and tests
7. Summarize changed files, behavior, and any remaining risks

## Issue Source Rules
- GitHub Issue is the primary source of truth for scope and acceptance criteria.
- Local issue files (for example `docs/issues/issue-xx.md`) are optional support materials.
- If GitHub Issue and local issue files conflict, follow the GitHub Issue and report the mismatch.

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

### Plugins with Native-Side Behavioural Coupling
Some plugins encode behavioural contracts in native code or `AndroidManifest.xml`
that are NOT visible from Dart APIs alone. When upgrading any of these to a new
**major** version, re-verify the behaviour against the native source and update
the linked tests / comments before merging the upgrade PR.

| Plugin | Coupled native artefact | Why |
|---|---|---|
| `flutter_foreground_task` | `AndroidManifest.xml` `<service android:stopWithTask="true">` and the comment in `lib/data/foreground_service/foreground_service_manager.dart` | The Dart-level `ForegroundTaskOptions.stopWithTask` and the manifest attribute have *different* runtime effects in 9.x (the Dart option wires `TrackVisibilityUtils` and stops the service on every Activity pause). The fix for issue #869 relies on this distinction. See `test/android/android_manifest_foreground_service_test.dart`. |

## Optional Reference Two-Stage Fallback

Public repo — referenced code/resources/config may be **absent** in some clones. Dependent code MUST be two-stage:

1. **Primary** — call the real implementation when available
2. **Fallback** — when unavailable, first try an alternative built on the repo's **internal (public) APIs**. If no alternative exists and the reference is functionally required, swallow the error and **leave only an error log**, then continue (no-op)

**Forbidden**: absence breaking build / static analysis / startup / unrelated features; assuming "always present"; names, comments, or error messages that hint at a private artifact (use neutral terms like `optional integration`).

**Techniques**: conditional `import`; `try`/`catch` around the optional access; feature flag or DI swapping in a no-op; runtime symbol-presence check.

**Review checklist**: fallback on every path touching the optional reference; absence covered by a test or documented manual check; user-visible messages/logs do not leak internal structure.

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

## テストファイル肥大化・実行時間ルール

`flutter test` は 1 ファイル = 1 isolate のため、ファイル数増は CI 時間と保守コストに直結する。**カバレッジは件数ではなくコード網羅率と意図網羅性で測る**。本ルールは新規追加・新規変更テストに適用（forward-looking）、既存違反は別 Issue で段階対応する（feature PR に retrofit を混ぜない）。レビュー観点は `CLAUDE.md` を参照。

### ファイル構成

- **1 対象 = 1 ファイル**: 同じ画面・クラス・関数のテストは `<target>_test.dart` に集約
- **新規ファイル作成前**: `find test -name "<target>_test.dart"` で既存検索 → あれば `group()` 追加で対応
- **物理分割は 2,000 行超 + 視点分離可** のときのみ（例: `comment_screen_speech_test.dart`）
- **横断的観点は「観点 = ファイル」**（例: `message_background_contrast_test.dart` に gift / nicoad / notification / operator を集約）
- **小規模単独 OK**: 別 domain ターゲットの pure function テスト（例: `nico_icon_url_test.dart`）は 1 group + 100 行未満でも単独維持してよい

### Fake / Mock の配置

- 2 ファイル以上で同じ fake を使うなら `test/helpers/fake_<class>.dart` に抽出
- インライン `class _FakeXxx` の再定義禁止

### 実行時間

- **`testWidgets` vs `test`**: 純粋ロジックは必ず `test()`（`testWidgets` は Flutter binding 起動分重い）
- **`pumpAndSettle` の濫用禁止**: アニメーション完了が assertion の前提のときだけ使う。setState 反映待ち / 1 フレーム挿入は `pump()` または `pump(Duration)` で済ます
- **重い setUp は `setUpAll` で共有**: `rootBundle.loadString` 等は 1 回だけ
- **実時間 sleep 禁止**: `Future.delayed` 不可、`fake_async` または `pump(Duration)` でフェイク時間を進める

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

### Committer Identity (user.name / user.email)

公開リポジトリへ push されるコミットの author / committer 情報は、リポジトリで設定された `git config` 値（通常は GitHub の `*****+username@users.noreply.github.com` などの noreply）をそのまま使うこと。

- **`-c user.email=...` / `-c user.name=...` でプライベートな実 email を渡して git コマンドを上書きしてはならない** — `git commit`、`git rebase`、`git cherry-pick` 等いずれも対象。意図せずアカウント特定可能な email を公開履歴に刻むリスクがある。
- **Claude Code ハーネスが context に注入する `# userEmail` (Anthropic アカウントログイン用 email) を commit / PR 本文 / Issue 本文 / コードコメント / 公開ドキュメントに書かない** — これはアカウント識別用の参照情報であり、公開コミットに残すと当該 email がリポジトリ履歴に永続的に紐付く。
- 既存の `git config user.email` 値が想定と異なる場合は、まずユーザーに確認する。勝手に書き換えない。
- レビューで上書きや実 email 漏れが見つかった場合は **must fix** として差し戻す。

#### 許容される committer 値

下記の noreply / agent identity であれば commit・author・committer に設定して構わない（`-c` での明示指定もこの範囲内なら可）:

- リポジトリで設定済みの `git config user.email`（GitHub `*****+username@users.noreply.github.com` 形式の noreply 等）
- `Claude <noreply@anthropic.com>` — Web/Cloud 上で動く Claude Code が既定で使用する agent identity。`git config` がデフォルトのままだったり empty な実行環境ではこの値を `-c user.name=Claude -c user.email=noreply@anthropic.com` で明示してよい
- その他 `*@users.noreply.github.com` 系の GitHub noreply

要するに **NG なのは「個人特定可能な実 email を上書きで渡すこと」**であって、noreply / agent identity の明示は問題ない。

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

## 設定項目の変更時の注意

設定項目を追加・変更・削除する際は、Export/Import 設定機能との整合性を必ず確認すること。

- 追加時: Export に含めるか判断し、含めるなら Import で復元できるようにする
- 変更時: 過去の Export ファイルを Import しても壊れないか（キー名・型・デフォルト値の後方互換性）を確認する
- 削除時: 古い Export ファイルに該当キーが残っていても安全に無視できるようにする

## ライセンスページの applicationName / applicationVersion

`showLicensePage` / `AboutDialog` の `applicationName` `applicationVersion` をハードコードしないこと。`pubspec.yaml` との同期漏れでバージョン表示が古くなるリスクがあるため、`package_info_plus` 等で動的取得する。`pubspec.yaml` の `version` を変更する PR では、これらの表示が正しく更新されるかも併せて確認する。

## UI 文字列の追加（i18n 対応準備）

UI に新たに日本語文字列を追加する際は、原則として `lib/presentation/strings/app_strings.dart` の `AppStrings` 配下にまとめてから参照すること。将来の多言語対応時に一括で差し替えやすくするための準備。

追加手順:
1. 対象画面のスコープに合う `XxxStrings` ネストクラス（無ければ新設）に `camelCase` の getter を追加する
2. 引数を含む文字列（例: `'$count件'`）は `String` を返すメソッドとして追加する（`const` 展開による文法崩れを避ける）
3. API 応答・例外テキストなど**動的**なメッセージは UI 定数ではないため、ここには入れない
4. 既定ロケール（日本語）の表示がバイト単位で変わらないよう、既存 widget テストと `test/presentation/strings/app_strings_test.dart` を併せて確認する

スコープ（Issue #476 Phase 1 時点）: `SettingsScreen`（設定画面ルート）のみ集約済み。下位画面（コメント表示設定・読み上げ設定・ユーザー管理設定）、コメント画面系、ダイアログ・SnackBar は継続課題として段階的に追加する。

## Error handling

詳細な error handling 方針は `.ai/flutter_rules.md` の Error Handling Rules を参照。本セクションは特に「`Exception` だけ catch して `Error` を素通りさせる」落とし穴の回避を強調する。

### 永続化値のパースを含む load 経路

永続化値のパースを含む load 経路（例: `SettingsStore.load()`）では `on Exception catch` ではなく `on Object catch (e, st)` を使うこと。Dart では `Exception` と `Error` が独立階層で、`TypeError` / `StateError` / `ArgumentError` / `RangeError` 等の `Error` 系は `on Exception catch` を素通りする。旧バージョンが保存した値を新バージョンが読めないアップデート時に `Error` が伝播すると、`settings`/`settingsError` が共に null のまま画面が `CircularProgressIndicator` で永久に固まる事故が発生する。

レビュー観点:
- 永続化値・外部入力をパースする `try`/`catch` で `on Exception catch` のみになっていないか
- 旧形式データを再現するテスト（`Error` 系を投げるスタブ）で永続スピナーが出ないことを確認しているか
- `catch (e)` で握りつぶす場合も、`developer.log(name: '<source>', error: e, stackTrace: st)` で stackTrace と error を残し、再現可能にしているか

## Forbidden Behavior
Agents must not:
- invent major product requirements
- make unapproved architecture migrations
- bundle refactors with feature delivery
- skip explaining assumptions
- claim tests passed if they were not actually run
- mark work complete when acceptance criteria are not satisfied
- close issues on behalf of the human owner
