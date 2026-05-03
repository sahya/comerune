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

## テストファイル肥大化防止ルール

`flutter test` は 1 ファイル = 1 isolate 起動のため、ファイル数の増加は CI 実行時間と保守コストに直接跳ね返る。**テストカバレッジ（網羅性）は件数ではなく「コード網羅率と意図網羅性」で測る** ため、ファイルを増やさずに件数を増やす方針を取ること。

### 新規テストファイル作成前の判断順

テストを追加する前に、必ず次の順で判断する:

1. **同じ対象に対するテストファイルの存在確認** — `find test -name "<target>_test.dart"` で検索
2. **既存ファイルがあれば `group()` 追加で対応** — 別ファイル化は最後の手段
3. **新規 `<target>_test.dart` 作成は「対象自体が新規」のときのみ**

### 1 対象 = 1 ファイル原則

- 同じ画面・クラス・関数に対するテストは 1 ファイルに集約する
- ファイル名は対象と一致させる: `<target>_test.dart`
- 物理分割は次の例外条件のみ許可:
  - 1 ファイルが **2,000 行を超え**、かつテスト視点が明確に分離できる場合（観点を明示するサフィックスを付ける。例: `comment_screen_speech_test.dart`）
- 単一補助テスト（純粋関数・データクラスのデフォルト値検証）は対象画面のテストに `group()` で同居させる。`<target>_config_test.dart` のような細切れファイルは作らない
- **小規模ファイル（1 group + 100 行未満）は単独では問題ない** — 別ターゲットの pure function テストなど、統合先となる関連ファイルが存在しない場合は単独維持してよい

### ルール適用範囲（forward-looking）

本ルール群は **新規追加・新規変更されるテスト** に対する規約。既存テストへの retrofit（過去の違反クリーンアップ）は別 Issue で段階対応する。本ルールを根拠に既存ファイルの修正を feature PR に混ぜないこと。

### 横断的観点のテスト

- WCAG コントラスト・i18n キー網羅・全テーマ走査など、複数のクラスを横断する観点別テストは「**観点 = ファイル**」で集約する
  - 良い例: `message_background_contrast_test.dart` で gift / nicoad / notification / operator を全て扱う
  - 悪い例: `gift_contrast_test.dart` + `nicoad_contrast_test.dart` のような対象別分割

### Fake / Mock の配置

- 2 ファイル以上で同じ fake クラスを必要とする場合、必ず `test/helpers/` に抽出する
- インラインで `class _FakeXxx` を再定義しない
- ヘルパー名はクラス名と一致させる（`fake_<class>.dart`）

## テスト実行時間短縮ルール

網羅性を維持したまま実行時間を短縮するため、テストを書く際は次を遵守する:

### `testWidgets` と `test` の使い分け

- 純粋ロジック（フォーマッタ・正規化・パーサ・データクラス）は **必ず `test()` を使う**
- `testWidgets()` は Flutter binding を起動するため `test()` より重い
- 「画面の中で使う関数だから」という理由で `testWidgets` を使わない

### `pumpAndSettle` の濫用禁止

- `pumpAndSettle` は全アニメーションが完了するまで待機する（数十〜数百 ms のオーバーヘッド）
- 次の場合は `pump()` または `pump(Duration(milliseconds: N))` を使う:
  - アニメーション完了を確認する目的ではない
  - 単に setState() の反映を待ちたいだけ
  - フレーム更新を 1 回挟みたいだけ
- `pumpAndSettle` は「アニメーション完了が assertion の前提」のときだけ使う

### 重い setUp の共有

- `rootBundle.loadString` などのアセットロードは `setUpAll` で 1 回だけ実行する（プライム後はキャッシュされる）
- `setUp` で毎テスト走らせない

### 実時間 sleep の禁止

- `Future.delayed`（実時間待機）でタイマー処理をテストしない
- 代わりに `fake_async` パッケージ または `WidgetTester.pump(Duration)` でフェイク時間を進める

### レビュー観点

PR レビュー時は次を必ず指摘する:
- 既存 `<target>_test.dart` がある状態で新規 `<target>_xxx_test.dart` が追加されていないか
- 1 件の追加要件のために新ファイルを作っていないか
- 既存 fake と類似したインライン fake 定義が混入していないか
- 1 group しかない超小型テストファイルが追加されていないか
- 純粋ロジックのテストに不必要な `testWidgets` が使われていないか
- `pumpAndSettle` が assertion の前提なく使われていないか

肥大化や速度劣化が判明した場合は、別 PR で統合・最適化する（feature PR にリファクタリングを混ぜない）。

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
