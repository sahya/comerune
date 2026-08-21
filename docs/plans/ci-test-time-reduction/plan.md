# CI テスト実行時間削減 計画書

- 作成日: 2026-08-21
- ステータス: 計画（実施前）
- 関連文書: [仕様書 (spec.md)](./spec.md) / 個別 Issue 案: [issues/](./issues/)
- 実行 Skill: `.claude/commands/test-perf-refactor.md`（Claude Code 用。Codex 等で実施する場合は spec.md と issue ファイルを直接プロンプトに渡す）

## 1. 目的

PR ごとの CI（`.github/workflows/test.yml`）の所要時間を短縮する。
**テストのカバレッジ（コード網羅・意図網羅）と品質は落とさない**ことを絶対条件とし、
小さな PR の積み重ねで段階的に実施する。

## 2. 現状分析（実測データ）

### 2.1 CI ジョブのステップ別実測（2026-08-21 時点の直近 run）

単一ジョブ `Analyze, Format, Test` に全ステップが直列で入っている。

| ステップ | run 2265 (main, cache 保存あり) | run 2269 (PR, warm cache) | run 2266 (PR, cold 気味) |
|---|---:|---:|---:|
| checkout + Java + Flutter SDK 準備 | 66s | 45s | 66s |
| `flutter pub get` | 10s | 1s | 10s |
| `dart format --set-exit-if-changed .` | 2s | 2s | 2s |
| `flutter analyze` | 15s | 15s | 14s |
| **`flutter test`** | **142s** | **135s** | **140s** |
| `flutter build apk --config-only` | 1s | 1s | 1s |
| **Kotlin unit tests (`gradlew :app:testDebugUnitTest --no-daemon`)** | **308s** | **152s** | **299s** |
| post 処理（cache 保存等） | 31s | 2s | 31s |
| **合計** | **9分39秒** | **5分57秒** | **9分26秒** |

（run ID: 32519015923 / 32523210380 / 32519144330。GitHub Actions の job steps API から取得）

### 2.2 テストスイートの静的統計

| 項目 | 値（grep による参考値） |
|---|---:|
| Dart テストファイル数 | 157 |
| Dart テスト総行数 | 約 78,000 行 |
| `testWidgets` 定義数 | 897 |
| `test()` 定義数 | 1,987 |
| `pumpAndSettle` 呼び出し箇所 | 1,231 |
| Kotlin テストファイル数 / 行数 | 27 / 約 7,500 行 |

`pumpAndSettle` の上位集中ファイル:

| ファイル | 箇所数 | 行数 |
|---|---:|---:|
| `test/presentation/screens/comment_screen_speech_test.dart` | 214 | 6,232 |
| `test/presentation/screens/comment_screen_test.dart` | 187 | 9,042 |
| `test/presentation/screens/tts_settings_screen_test.dart` | 130 | 3,259 |
| `test/presentation/select/select_screen_test.dart` | 105 | 3,597 |
| `test/presentation/screens/comment_screen_end_broadcast_menu_test.dart` | 78 | 866 |
| `test/presentation/screens/settings_screen_test.dart` | 57 | 1,221 |

### 2.3 ボトルネックの帰属（結論）

1. **ジョブ構造が直列**であること自体が最大の要因。Flutter 系（format/analyze/test）と
   Kotlin 系（Gradle）は独立して実行できるのに、合算で wall time になっている。
2. **Kotlin テストステップが最大かつ最も変動が大きい**（152〜308 秒）。テスト実体は
   27 ファイル・7,500 行と小さく、時間の大半は Gradle の起動・configuration・Kotlin
   コンパイルとみられる（`--no-daemon`・build cache 未活用）。
3. **`flutter test` は約 2 分 20 秒で安定**。約 2,900 テストに対して極端に遅いわけでは
   ないが、`pumpAndSettle` の広範な使用（1,231 箇所、大半は画面系テスト）と
   1 ファイル = 1 isolate のオーバーヘッド（157 ファイル）に削減余地がある。
4. SDK セットアップ・キャッシュ復元/保存は warm 時 約 45〜60 秒で、削減余地は小さい。

## 3. 戦略

3 トラックを「効果の大きい順・リスクの低い順」に進める。全トラック共通の原則:

- **計測ファースト**: 変更前後を同一条件で計測し、効果を PR に記録する。効果が出なかった
  施策は「効果なし」と正直に記録してクローズする（無理に取り込まない）。
- **1 PR = 1 Issue**: 機械的・可逆的な小さい変更のみ。revert が常に容易であること。
- **品質ガード**: テスト件数の維持（§6）、アサーション変更禁止、`skip` 禁止。

| トラック | 内容 | 期待効果（wall time） | リスク |
|---|---|---|---|
| A: CI 構造 | ジョブ並列化・Gradle キャッシュ活用 | **−2〜4 分**（最大） | 低（テストコード無変更） |
| B: Dart テスト衛生 | `pumpAndSettle` 適正化・重い setUp 共有・fake 統一 | −20〜60 秒 + ローカル開発の高速化 | 低〜中（決定表で機械化） |
| C: 構造整理 | 小ファイル統合（isolate 削減）※実測ゲート付き | −10〜30 秒（実測次第） | 中（実測で効果確認後のみ） |

## 4. 目標値（KPI）

| 指標 | 現状 | 目標 |
|---|---|---|
| PR CI 全体（warm cache） | 約 6 分 | **4 分 30 秒以下** |
| PR CI 全体（cold 気味） | 約 9 分 30 秒 | **7 分以下** |
| `flutter test` ステップ | 約 2 分 20 秒 | **2 分以下** |
| テスト件数（Dart + Kotlin） | 約 2,900 + Kotlin | **減少ゼロ**（追加は歓迎） |
| 既存テストの意図・アサーション | — | **変更ゼロ** |

## 5. Issue 一覧と進捗

ID は本計画ローカルの通し番号（TT = Test Time）。GitHub Issue 化は human owner が行い、
Issue 番号が付いたら「GitHub #」列に記入する。各 TT の詳細（scope / non-scope / AC）は
`issues/tt-XX-*.md` を参照。

| ID | タイトル | フェーズ | 依存 | 期待効果 | GitHub # | 状態 |
|----|---------|:---:|------|---------|:---:|:---:|
| [TT-01](./issues/tt-01-test-timing-report.md) | テスト実行時間の計測レポート基盤 | 0 | – | 可視化（前提） | | 未着手 |
| [TT-02](./issues/tt-02-ci-job-split.md) | CI ジョブ分割（Flutter / Kotlin 並列化） | 1 | – | −2〜4 分 | | 未着手 |
| [TT-03](./issues/tt-03-gradle-test-speedup.md) | Kotlin テストジョブの Gradle 高速化実験 | 1 | TT-02 | −30 秒〜2 分 | | 未着手 |
| [TT-04](./issues/tt-04-pump-comment-screen-speech.md) | pumpAndSettle 適正化: comment_screen_speech_test | 2 | TT-01 | −数秒〜十数秒 | | 未着手 |
| [TT-05](./issues/tt-05-pump-comment-screen.md) | pumpAndSettle 適正化: comment_screen_test | 2 | TT-01 | −数秒〜十数秒 | | 未着手 |
| [TT-06](./issues/tt-06-pump-tts-settings.md) | pumpAndSettle 適正化: tts_settings_screen_test | 2 | TT-01 | −数秒 | | 未着手 |
| [TT-07](./issues/tt-07-pump-select-screen.md) | pumpAndSettle 適正化: select_screen_test | 2 | TT-01 | −数秒 | | 未着手 |
| [TT-08](./issues/tt-08-pump-remaining-top.md) | pumpAndSettle 適正化: 残り上位 3 ファイル | 2 | TT-04〜07 | −数秒 | | 未着手 |
| [TT-09](./issues/tt-09-setupall-fake-audit.md) | 重い setUp の setUpAll 化・fake 重複の監査と抽出 | 2 | TT-01 | −0〜10 秒 + 保守性 | | 未着手 |
| [TT-10](./issues/tt-10-file-consolidation-eval.md) | 小ファイル統合の実測評価（isolate 削減） | 3 | TT-01, TT-04〜09 | −10〜30 秒（実測次第） | | 未着手 |

### 追加候補（効果測定後に Issue 化を判断。今は着手しない）

- **paths filter による Kotlin ジョブのスキップ**（Dart のみの変更時）: required check の
  扱い（skipped ジョブの合格判定）と、`pubspec.lock` 変更がプラグイン経由で Android 側に
  影響するケースの扱いを整理してから。TT-02 の安定稼働後に判断。
- **`flutter test --concurrency` チューニング**: ubuntu-latest は 4 vCPU。既定値からの
  変更で改善するかを CI 上で 2/4/6 比較。効果が ±5% 未満なら不採用。
- **テスト時間バジェットの soft warning**: TT-01 のレポートを使い、`flutter test` が
  閾値超過したら PR に警告コメント。運用が回り始めてから。

## 6. 品質ガードレール（全 Issue 共通の受け入れ条件）

各 PR で以下をすべて満たすこと。詳細な確認手順は spec.md §5。

1. **テスト件数が減っていない**: `flutter test --file-reporter json:...` の件数を
   変更前後で比較し、PR 本文に before/after を記載する。
2. **アサーション・テスト意図を変更しない**: expect の削除・緩和、`skip`、
   テスト削除は禁止。pumpAndSettle → pump 等の待ち方の変更のみ許可。
3. **必須チェックが green**: `flutter analyze` / `dart format`（`make format`）/
   `flutter test` 全パス。
4. **計測結果の記録**: 変更前後の実行時間（3 回計測の中央値）を PR 本文に記載。
   ±5% 未満の差は「効果なし」と記載してよい（それでも可読性・規約適合の価値が
   あれば取り込み可、なければクローズ）。
5. **スコープ遵守**: 1 PR = 1 Issue。対象ファイル以外の変更（おまけ修正）を混ぜない。
6. **`CLAUDE.md` のセルフレビュー**（多視点レビュー）を実施する。`/flutter-check` で代替可。

カバレッジについて: 本リポジトリの CI はカバレッジ計測を行っていないため、
「カバレッジを落とさない」は **テスト件数の維持 + アサーション不変** で担保する
（待ち方だけを変える変換では実行される検証内容が変わらないため）。TT-10（統合）のみ、
移動前後で group / テスト名の完全一致を追加で確認する。

## 7. 実施順序

```
Phase 0:  TT-01（計測基盤）
Phase 1:  TT-02（ジョブ分割） → TT-03（Gradle 実験）      ← 最大の削減。先行実施
Phase 2:  TT-04 → TT-05 → TT-06 → TT-07 → TT-08 → TT-09   ← 1 ファイル 1 PR で順次
Phase 3:  TT-10（統合。Phase 2 完了後に実測データで判断）
```

- Phase 1 と Phase 2 は独立しており並行可能。ただし**計測の比較可能性のため、
  Phase 2 の各 PR は他の TT と同一 PR に混ぜない**。
- Phase 2 の順序は pumpAndSettle 箇所数の多い順。1 件実施して得た知見
  （置換可否の判断例）は spec.md の決定表に追記して次に活かす。

## 8. リスクと対策

| リスク | 対策 |
|---|---|
| ジョブ分割で branch protection の required check 名が変わる | Flutter 側ジョブ名を現行の `Analyze, Format, Test` のまま維持し、Kotlin 側を新名で追加。**owner がリポジトリ設定で required checks に Kotlin 側ジョブを追加する**（TT-02 の AC に明記） |
| pumpAndSettle → pump 置換でタイマー未消化（"Timer is still pending"）や未完了アニメによる fail | 置換はローカルで対象ファイルを実行して検証。fail したサイトは元に戻す（spec.md の決定表に「迷ったら維持」を明記）。失敗は決定的（flaky ではない）ため CI で検出可能 |
| setUpAll 共有によるテスト間の状態リーク | 共有は immutable なデータ読み込みのみに限定（spec.md §3.3 の条件表）。可変状態は setUp のまま |
| Gradle の configuration cache が Flutter Gradle プラグインと非互換 | TT-03 は「実験」として実施し、非互換なら build cache のみ採用。採否基準と計測方法を issue に明記 |
| 統合（TT-10)でテストの取りこぼし | group 単位の verbatim 移動 + 件数・テスト名一致の機械的確認。効果が実測で小さければ実施しない |
| 計測のマシンノイズによる誤判断 | 3 回計測の中央値 + ±5% 閾値。CI 上の判断は同条件（warm cache）の run 同士で比較 |

## 9. 運用方法（Opus / Codex での実施手順)

### Claude Code（Opus 等）の場合

1. human owner が `issues/tt-XX-*.md` を GitHub Issue 化する（そのままコピーで可）
2. セッションで `/test-perf-refactor <GitHub Issue URL または issues/tt-XX-*.md のパス>` を実行
3. Skill が spec.md の手順（計測 → 変換 → 検証 → 記録）を実施し、PR を作成
4. レビューは通常の PR レビュー（`CLAUDE.md` のレビュー方針）に従う

### Codex 等（このリポジトリの Skill を読まないエージェント）の場合

プロンプトに以下を渡す:

```
リポジトリの AGENTS.md と .ai/flutter_rules.md に従うこと。
docs/plans/ci-test-time-reduction/spec.md の手順・決定表・ガードレールに厳密に従い、
docs/plans/ci-test-time-reduction/issues/tt-XX-....md の scope だけを実施すること。
non-scope に書かれたことは行わないこと。完了時は spec.md §5 のチェックリストと
PR 本文テンプレートを使うこと。
```

### 進捗管理

- 各 TT の PR がマージされたら、本書 §5 の表の「状態」を更新する（実施 PR 内で更新して
  よい）。値: `未着手` / `実施中` / `完了` / `効果なし・クローズ`
- Issue のクローズは human owner のみが行う（`CLAUDE.md` Issue Lifecycle）

## 10. 効果見積の根拠と不確実性

- **TT-02 の −2〜4 分**は実測の直列合計から機械的に導出（wall = 合計 → max(2 系統)）。
  最も確度が高い。
- **TT-03** は Gradle のどの工程が支配的か（configuration か Kotlin コンパイルか）を
  まだ分離計測していないため、幅が大きい。TT-03 冒頭で `--profile` による内訳計測を行う。
- **Phase 2（pumpAndSettle）**の削減は 1 サイトあたり数〜十数フレームの描画削減 ×
  約 1,200 サイトの積み上げで、`flutter test` 全体 140 秒のうち **10〜30 秒程度**と
  見積もる（不確実性大）。ここは CI 短縮よりも**ローカル開発ループの高速化と
  AGENTS.md「実行時間」規約への適合**が主目的であり、CI の主削減は Phase 1 が担う。
- **TT-10** は 1 ファイルあたりの isolate 起動・カーネルコンパイルのオーバーヘッド実測
  （TT-01 のレポートで取得）に完全に依存するため、実測ゲートを置いた。
