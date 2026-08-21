# CI テスト実行時間削減 仕様書

- 対象読者: 本計画の Issue を実施する AI エージェント（Claude Code / Codex 等）および human owner
- 前提文書: [計画書 (plan.md)](./plan.md)。ここには**実施手順・変換規則・検証プロトコル**の詳細のみを書く
- 拘束ルール: `AGENTS.md`（特に「テストファイル肥大化・実行時間ルール」）、`.ai/flutter_rules.md`、`CLAUDE.md`

## 1. 共通事項

### 1.1 実施単位

- 1 PR = 1 Issue（`issues/tt-XX-*.md`）。issue の scope 外の変更を混ぜない。
- ブランチ名: `chore/tt-XX-<short-description>`。Git Flow prefix 規約（`CLAUDE.md`）に
  `perf/` は無いため、テスト・CI 改善は `chore/` を既定とする。
- コミットは Conventional Commits。目安:
  - CI 変更: `ci: split flutter and kotlin test jobs`
  - テスト変換: `perf(test): replace settle waits with single pumps in comment_screen_test`
  - 計測スクリプト: `chore(test): add per-file test timing report script`

### 1.2 環境前提

- Flutter コマンド実行前に `flutter --version` で SDK の存在を確認する（`CLAUDE.md`
  環境前提チェック）。SDK が無い環境では Phase 2 以降の Issue に**着手しない**
  （変換の正当性はテスト実行でしか検証できないため）。
- ローカル実行は `make check`（analyze → format → test）を正とする。

### 1.3 計測プロトコル（全 Issue 共通）

1. 対象を絞った計測: `time flutter test <対象ファイル>` を **3 回**実行し中央値を取る。
2. 全体計測: `time flutter test` を変更前後で各 1 回（参考値）。CI の実測値
   （PR の `Run tests` ステップ時間）を最終判断に使う。
3. 件数取得: `flutter test --file-reporter json:build/test-report.json <対象>` を実行し、
   TT-01 のスクリプト（無ければ後述の jq 相当の手作業）で件数を数える。
4. 判定: 中央値の差が **±5% 未満は「効果なし」**として正直に記録する。
5. PR 本文に §5.2 のテンプレートで before/after を記載する。

## 2. CI 変更仕様（Phase 1）

### 2.1 TT-02: ジョブ分割の目標形

`.github/workflows/test.yml` を以下の 2 ジョブ構成にする。**ステップの中身・コメント・
SHA ピン・バージョンは現行ファイルから変えない**（移動のみ）。行頭コメント（最小権限、
supply-chain anchor 等）は必ず維持する。

以下は目標構成の疑似表記（そのまま貼り付け可能な YAML ではない。実際のステップ定義は
現行 test.yml から移動して使う）:

```text
jobs:
  check:
    name: Analyze, Format, Test        # ← 既存の required check 名を維持する
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - checkout(persist-credentials: false)
      - subosito/flutter-action(flutter-version: 3.44.0, cache: true)   # 現行と同一 SHA ピン
      - flutter pub get
      - dart format --set-exit-if-changed .
      - flutter analyze
      - flutter test

  kotlin-test:
    name: Kotlin Unit Tests
    runs-on: ubuntu-latest
    timeout-minutes: 20                # cold cache の Gradle を考慮
    steps:
      - checkout(persist-credentials: false)
      - actions/setup-java(temurin 17, cache: gradle)   # JDK は Flutter より先（現行コメント通り）
      - subosito/flutter-action(同上)
      - flutter pub get                # .flutter-plugins-dependencies を生成するため必要
      - flutter build apk --config-only
      - cd android && ./gradlew :app:testDebugUnitTest --stacktrace --no-daemon
```

設計上の決定と理由:

- `check` ジョブ名・job id は現行のまま維持し、branch protection の required check
  （`Analyze, Format, Test`）が切れないようにする。**Kotlin 側は新規 check になるため、
  マージ後に owner がリポジトリ設定で required に追加する**（PR 本文で明示的に依頼する）。
- JDK セットアップは Kotlin ジョブのみに移す（Flutter 側の pub get / analyze / test は
  Gradle を起動しない）。これで `check` ジョブから setup-java（0〜25 秒）と
  gradle cache 保存 post（〜20 秒）も消える。
- `permissions: contents: read`、`concurrency`（cancel-in-progress）は workflow レベルの
  現行設定をそのまま維持する。
- workflow レベルの `timeout-minutes: 25` はジョブ別（15 / 20）に置き換える。

### 2.2 TT-03: Gradle 実験の手順と採否基準

**目的**: `:app:testDebugUnitTest` ステップ（実測 152〜308 秒）の内訳を特定し、
キャッシュで縮める。**必ず TT-02 マージ後に実施**（並列化後の Kotlin ジョブが対象）。

手順:

1. 内訳計測: CI 上で一時的に `--profile` を付けた run を 1 回実行し、
   configuration / コンパイル / テスト実行の内訳をログで確認、Issue にメモを残す
   （プロファイル HTML のアーティファクト保存は任意）。
2. 実験候補（効果が出た時点で残りは任意）:
   - a. `org.gradle.caching=true`（build cache）を CI 実行時のみ有効化
     （`gradlew -Dorg.gradle.caching=true` 等、ローカルの挙動を変えない形を優先）。
     setup-java の `cache: gradle` は `~/.gradle/caches` を保存するため、
     コンパイル結果の build cache がヒットすれば 2 回目以降の run が縮む。
   - b. `--configuration-cache` の試行。Flutter Gradle プラグインが非対応の場合は
     エラーになるので、**その場で不採用と判定**し記録する（無理に回避しない）。
3. 判定: warm cache の run 同士で比較し、中央値 **30 秒以上**の短縮が確認できた施策のみ
   採用。効果 30 秒未満の施策は revert し「効果なし」と記録する。

禁止: テストの分割実行・除外、`testOptions` の変更、Kotlin ソースへの変更。

## 3. Dart テスト変換カタログ（Phase 2）

### 3.1 T1: `pumpAndSettle` の適正化（TT-04〜08）

`pumpAndSettle()` は「スケジュール済みフレームが無くなるまで 100ms 刻みで pump し続ける」
ため、アニメーション完了が assertion の前提でない場所では過剰。以下の決定表に従い、
**サイトごとに**置換可否を判断する。

| # | サイトの状況 | 置換 | 備考 |
|---|---|---|---|
| 1 | setState / notifyListeners / Stream イベントの反映を待つだけ | `pump()` | 1 フレームで再ビルドされる。反映が 2 段なら `pump()` を 2 回 |
| 2 | `tester.tap` / `enterText` 後、**遷移やアニメ完了に依存しない** assert（テキスト出現、コールバック記録、リスト件数等） | `pump()` | ripple 等の進行中アニメは disposal で消えるため残ってよい |
| 3 | Timer / debounce / `Future.delayed` の消化待ち | `pump(該当 Duration)` | 待ち時間が仕様上明確な場合のみ。フェイク時間なので実時間コストはない |
| 4 | ルート遷移の完了後 UI を**操作**する（dialog / menu / bottom sheet / 画面遷移後に tap 等） | **維持** | 遷移アニメ完了前の hit test は失敗リスクがある |
| 5 | アニメーション完了状態そのものが assert 対象 | **維持** | AGENTS.md の規約どおり本来の用途 |
| 6 | 判断に迷う・置換後にテストが fail する | **維持（元に戻す）** | 安全側に倒す。無理に置換しない |

手順（1 ファイルにつき）:

1. ベースライン計測（§1.3）。
2. 決定表 #1〜#3 に該当するサイトを置換。**1 サイトずつではなく group 単位で置換 →
   対象ファイルを実行 → fail したテスト内のサイトだけ元に戻す**、を繰り返す
   （失敗は決定的なので二分探索が効く）。
3. よくある失敗と対処:
   - `A Timer is still pending` → そのテストに未消化タイマーがある。該当 Duration の
     `pump(Duration)` を足すか、そのサイトは pumpAndSettle に戻す。
   - `finder found nothing`（遷移未完了） → 決定表 #4 に該当。維持に戻す。
4. 再計測 → §5 の検証 → PR。
5. 置換判断の知見（この画面はここで settle が要る等）が得られたら、本決定表の備考へ
   追記する PR に含めてよい（spec.md の同時更新は可）。

**禁止**: expect の変更・削除、テストの統合や並べ替え、`pumpAndSettle` の一括置換
（sed 等での盲目的置換）、タイムアウト引数の追加。

### 3.2 T2: `testWidgets` → `test` の格下げ（TT-09 の一部）

対象条件（すべて満たす場合のみ）:

- 本文が `tester` / `WidgetTester` / binding / `find` を一切使わない
- Widget を構築せず、純粋ロジック（モデル・正規化・フォーマッタ等）のみを検証している

該当したら `test()` に変更する（Flutter binding 起動分が浮く）。既存スイートは大半が
適切に使い分けているため、該当は少数の見込み。grep 例:

```
grep -l "testWidgets(" test -r | xargs grep -L "tester\."
```

### 3.3 T3: 重い setUp の `setUpAll` 化（TT-09）

| 共有してよいもの | 共有してはいけないもの |
|---|---|
| `rootBundle.loadString` / fixture ファイル読み込みの**結果（immutable）** | fake / mock のインスタンス（テスト間で呼び出し記録が汚染される） |
| パース済みの定数データ（List/Map は不変として扱うこと） | `SharedPreferences.setMockInitialValues` 等のグローバル状態設定 |
| 高価な純関数の計算結果 | Widget / controller / notifier のインスタンス |

`TestWidgetsFlutterBinding` に依存する初期化（channel mock 等）は各テストの独立性を守る
ため `setUp` に残す。判断に迷ったら共有しない。

### 3.4 T4: fake の重複排除（TT-09）

- 2 ファイル以上にインラインで同一内容の `class _FakeXxx` / `class _InMemoryXxx` がある
  場合、`test/helpers/fake_<class>.dart` に抽出して両者から import する（AGENTS.md 規約）。
- 抽出は**リネーム最小限**（`_Fake…` → `Fake…` の公開化のみ）。挙動変更禁止。
- 検出例: `grep -rn "class _Fake\|class _InMemory\|class _Recording" test --include="*_test.dart"`
  の結果をクラス名で突き合わせる。

### 3.5 T5: ファイル統合（TT-10。実測ゲート付き）

**前提**: TT-01 のレポートで「1 ファイルあたりの固定オーバーヘッド」を確認し、
統合で削れる時間（対象ファイル数 × 固定費）が **10 秒以上**と見積もれる場合のみ実施。

- 統合可否は `CLAUDE.md`「統合・分割の数値基準」の表に**厳密に**従う
  （統合候補: 同一対象に別ファイル + どちらかが 1 group + 100 行未満 / 同一画面の
  補助テスト分散 / 同一観点の対象別分割。2,000 行超のファイルへの追記はしない）。
- 手順: 移動元の group を**一字一句そのまま**移動先の `group()` として追加 → 移動元
  ファイル削除 → 件数・テスト名の完全一致を JSON レポートで確認（§5.1 手順 3）。
- import の整理と `_Fake` 類の衝突解消のみ許可。テスト本文の編集は禁止。

## 4. TT-01: 計測レポートスクリプト仕様

- 配置: `scripts/test_timing_report.dart`（既存の `scripts/*.dart` の慣例に合わせる）
- 依存: Dart 標準ライブラリのみ（`dart:io` / `dart:convert`）。**パッケージ追加禁止**
  （`CLAUDE.md` の依存ピン留め方針に抵触させない）
- 入力: `flutter test --file-reporter json:build/test-report.json` が生成する
  JSON lines ファイルのパス（引数 1）
- 出力（stdout, Markdown）:
  1. スイート（= テストファイル）ごとの所要時間の降順表: パス / テスト件数 / 時間(ms)。
     時間は「そのスイートに属す最初のイベント time と最後の `testDone` の time の差」で
     近似する
  2. 合計テスト件数（`testDone` のうち `hidden: false` のもの）と合計時間
  3. `--top N` で上位のみ表示（既定 20）
- Makefile ターゲット追加: `test-timing`（`flutter test --file-reporter …` 実行 →
  スクリプトで表示）
- CI 統合（同 Issue 内・任意）: `Run tests` ステップを
  `flutter test --file-reporter json:build/test-report.json` に変え、
  `always()` でレポートを step summary（`$GITHUB_STEP_SUMMARY`）へ出力する。
  アーティファクト upload を足す場合、新規 action は SHA ピン留め必須（pinact 管理）。
  コンソール出力が読みにくくなる等の問題があれば CI 統合は見送り、ローカル専用でよい。

## 5. 検証プロトコル（全 Issue 共通）

### 5.1 チェックリスト

実施エージェントは PR 作成前に以下を**順番に**実施し、結果を PR 本文に記載する:

1. `flutter --version`（環境前提チェック）
2. `make check` 相当（`flutter analyze` → `make format` → `flutter test`）が全パス
3. テスト件数 before == after（TT-10 はテスト名一覧の一致まで確認）:
   ```
   flutter test --file-reporter json:build/test-report.json
   grep -o '"testDone"' build/test-report.json | wc -l   # 簡易確認
   # TT-01 実施後は: dart run scripts/test_timing_report.dart build/test-report.json
   ```
4. 計測（§1.3）: before/after の中央値と判定（改善 / 効果なし）
5. 差分セルフチェック: 対象 Issue の scope 外ファイルに差分がないこと
   （`git diff --stat` を確認）
6. `CLAUDE.md` の多視点セルフレビュー（`/flutter-check` で代替可）

### 5.2 PR 本文テンプレート

```markdown
## 概要
docs/plans/ci-test-time-reduction/issues/tt-XX-....md の実施。
（GitHub Issue があれば: Closes #NNN）

## 計測結果
| 項目 | before | after |
|---|---|---|
| 対象ファイル単体 (median of 3) | XX.Xs | XX.Xs |
| flutter test 全体（参考） | XXXs | XXXs |
| テスト件数 | N | N（一致） |

判定: 改善 / 効果なし（±5% 未満）

## 変更内容
- （置換したサイト数、維持したサイト数とその理由の要約）

## 非スコープ
- （issue の non-scope をそのまま記載）

## 品質ガード
- [ ] analyze / format / test 全パス
- [ ] テスト件数・アサーション不変
- [ ] scope 外ファイルへの差分なし
- [ ] plan.md の進捗表を更新
```

### 5.3 ロールバック方針

- 各 PR は独立 revert 可能に保つ（他 TT との混在禁止の理由）。
- マージ後に CI 時間が悪化・flaky 化した場合は、当該 PR を revert してから原因調査する。

## 6. 変更してはいけないもの（全 Issue 共通）

- `lib/` 配下（プロダクションコード）。テスト都合での `lib/` 変更が必要になったら
  その Issue は中断し、owner に判断を返す
- テストの expect / assert の内容、テスト名、`skip` の追加
- `pubspec.yaml` への依存追加（exact pin 方針のため計測系も標準ライブラリで賄う）
- 既存 workflow のセキュリティ設定（permissions / persist-credentials / SHA ピン）
