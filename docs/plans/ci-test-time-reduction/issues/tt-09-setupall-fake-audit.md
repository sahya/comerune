# TT-09: 重い setUp の setUpAll 化・fake 重複の監査と抽出

## Goal
テストスイート全体を監査し、(1) テストごとに繰り返されている高価な immutable 読み込みを
`setUpAll` に共有、(2) 複数ファイルにインライン重複している fake を `test/helpers/` に
抽出、(3) 純粋ロジックに誤って使われている `testWidgets` を `test()` に格下げする。

## Scope
- 監査: spec.md §3.2〜§3.4 の grep 手順で全 `test/` を走査し、候補一覧を作る
- 修正: 候補のうち spec.md の条件表を満たすもののみ。該当ゼロの観点は
  「該当なし」と PR 本文に記録して終了してよい
- 計測: 修正したファイルのみ before/after（spec.md §1.3)

## Non-scope
- fake の挙動変更・機能追加（配置移動と公開化のみ）
- 可変状態・mock インスタンスの `setUpAll` 共有（spec.md §3.3 の禁止列）
- pumpAndSettle の置換（TT-04〜08 の領分）

## Dependencies
TT-01。TT-04〜08 とは独立に実施可（同一ファイルを同時に触らないよう、
実施中の TT と対象が重なる場合はそのファイルを後回しにする）。

## Acceptance criteria
- [ ] 監査結果の一覧（観点 × 候補 × 採否と理由）が PR 本文にある
- [ ] テスト件数 before == after、analyze / format / test 全パス
- [ ] 抽出した fake は `test/helpers/fake_<class>.dart` 命名で、元のインライン定義が
      すべて削除されている
- [ ] 修正ファイルごとの計測結果（改善 / 効果なし）が記録されている
- [ ] plan.md §5 の進捗表が更新されている

## Test expectations
- 既存テスト全パス。fake 抽出はコンパイルが通り全テストが従来どおり通ることが検証

## Implementation notes
- 候補が多い場合は「fake 抽出だけで 1 PR」「setUpAll 化だけで 1 PR」に分割してよい
  （その場合は本 Issue を分割し、plan.md の表に行を足す）
- `test/helpers/` には既に 12 個のヘルパーがある。命名・作りはそれらに合わせる
