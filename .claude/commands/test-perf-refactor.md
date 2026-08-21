あなたは CI テスト実行時間削減計画（docs/plans/ci-test-time-reduction/）の 1 Issue を、
計測 → 変換 → 検証 → 記録の手順で安全に実施するスキルです。

対象の指定: $ARGUMENTS

- 引数が GitHub Issue 番号/URL の場合: その Issue 本文（元は `issues/tt-XX-*.md`）に従う
- 引数が `docs/plans/ci-test-time-reduction/issues/tt-XX-*.md` のパスの場合: その内容に従う
- 引数が無い場合: `docs/plans/ci-test-time-reduction/plan.md` §5 の進捗表から、
  依存を満たす最初の「未着手」Issue を選び、着手前にユーザーへ対象を報告する

## ステップ 0: 前提確認（必須）

1. `flutter --version` を実行し Flutter SDK の存在を確認する。無ければ**作業を中断し**、
   CLAUDE.md「環境前提チェック」に従ってユーザーに確認する。テスト実行できない環境で
   テスト変換 Issue（TT-04 以降）を進めてはならない
2. 以下を読み込む（すべて拘束ルール）:
   - `docs/plans/ci-test-time-reduction/plan.md`（特に §6 品質ガードレール）
   - `docs/plans/ci-test-time-reduction/spec.md`（手順・決定表・禁止事項）
   - 対象 Issue ファイル（scope / non-scope / AC）
   - `AGENTS.md` / `.ai/flutter_rules.md`
3. GitHub Issue とローカル issue ファイルの内容が食い違う場合は GitHub Issue を優先し、
   不一致を報告する（CLAUDE.md Issue Source Rules）
4. AGENTS.md「Required Pre-Implementation Output」（Goal / Scope / Non-scope /
   変更予定ファイル / リスク / 手順）を出力してから着手する

## ステップ 1: ベースライン計測

spec.md §1.3 のプロトコルに従う:

1. `time flutter test <対象ファイル>` を 3 回実行し中央値を記録
2. `flutter test --file-reporter json:build/test-report.json` でテスト件数を記録
   （TT-01 実施済みなら `make test-timing` / `dart run scripts/test_timing_report.dart`）
3. 計測値はあとで PR 本文に載せるためメモしておく

## ステップ 2: 変換の実施

- 対象 Issue の scope **のみ**を実施する。non-scope に書かれたことは行わない
- テスト変換（TT-04〜08）は spec.md §3.1 の決定表にサイトごとに従う。
  一括置換（sed 等）は禁止。迷ったサイトは元のまま維持する
- group 単位で置換 → `flutter test <対象ファイル>` → fail したテスト内のサイトだけ
  元に戻す、を繰り返す
- 絶対禁止（spec.md §6）: expect の変更・削除、`skip` 追加、テスト削除、
  `lib/` の変更、`pubspec.yaml` への依存追加、scope 外ファイルの変更

## ステップ 3: 検証（spec.md §5.1 チェックリスト）

1. `make check`（analyze → format → test）が全パスするまで修正
2. テスト件数 before == after を確認（TT-10 はテスト名一覧の完全一致まで）
3. 再計測（3 回中央値）→ 差分を算出。±5% 未満は「効果なし」と正直に判定する
4. `git diff --stat` で scope 外ファイルに差分がないことを確認

## ステップ 4: セルフレビュー

/flutter-check を実行する（CLAUDE.md の多視点セルフレビュー要件を満たす）。
指摘が出たら修正し、ステップ 3 を再実行する。

## ステップ 5: 記録とコミット

1. `plan.md` §5 の進捗表の対象行を更新（`実施中` → `完了` または `効果なし・クローズ`）
2. 変換で得た判断知見があれば spec.md の決定表（備考）に追記
3. Conventional Commits でコミット（例は spec.md §1.1）。ブランチは `chore/tt-XX-...`
4. PR 本文は spec.md §5.2 のテンプレートを使用。対応する GitHub Issue があれば
   `Closes #NNN` を記載
5. AGENTS.md「Required Post-Implementation Output」を出力して完了報告する。
   Issue のクローズは行わない（human owner のみが閉じる）

## 失敗時の振る舞い

- 置換後の fail が解消できないサイトは維持に戻す（減点ではない。維持数を記録する）
- `make check` を全パスにできない場合、コミット・PR 作成をせず、状況と差分を報告して
  ユーザーの判断を仰ぐ
- 計測で悪化（+5% 超）が出た場合は変更を revert し、「悪化のため不採用」と記録する
