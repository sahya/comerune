# Issue #19: SettingsScreen 構築（読み上げセクションはグレーアウト）

Labels: v1.2, ui

GitHub Issue:

Epic: #1

## Goal

UI仕様書 §8 に基づいて設定画面を構築する。読み上げ関連セクションはUIとして配置するが操作不可（グレーアウト）とし、コメント表示設定とデバッグモードのみ操作可能にする。

## Scope

- SettingsScreen のレイアウト構築（スクロール可能な単一カラム、セクション区切り）
- **有効セクション**:
  - コメント表示: 過去コメント取得件数（`DropdownButton`, 選択肢: 100 / 500 / 1000 / 全部（上限あり））
  - デバッグ: デバッグモード ON/OFF（`SwitchListTile`）
- **グレーアウトセクション**（UI配置のみ、操作不可）:
  - 読み上げ: 自動読み上げ ON/OFF, エンジン選択ラジオ
  - 棒読みちゃん: ホスト, 速度, 音程, 音量, 声質
  - VOICEVOX: 話者, 話速, 音高, 抑揚, 音量
  - 読み上げキュー: キュー上限, 最大遅延
  - 読み上げフィルタ: URL省略, 連投抑制, NGワード
- `shared_preferences` による有効セクションの永続化
- AppBar に「設定」タイトルと戻る矢印

## Non-scope

- グレーアウトセクションの実際の動作実装・永続化
- 音声読み上げ機能との連携
- CommentScreen からの遷移配線（Issue #20 で行う）

## Dependencies

- なし（独立して実装可能）

## Acceptance Criteria

- [ ] SettingsScreen が表示され、全セクションが UI仕様書 §8.3 のレイアウト通りに配置されている
- [ ] 「過去コメント取得件数」ドロップダウンで 100 / 500 / 1000 / 全部（上限あり） を選択できる
- [ ] 「デバッグモード」トグルを ON/OFF できる
- [ ] 有効な設定値がアプリ再起動後も保持される（shared_preferences）
- [ ] 読み上げ関連セクション（読み上げ、エンジン固有、キュー、フィルタ）が視覚的にグレーアウトされており、タップしても反応しない
- [ ] グレーアウトセクションのラベル・UIパーツは仕様通りに配置されている（将来有効化時にレイアウト変更不要な状態）
- [ ] 戻るボタン（AppBar / Android back）で前の画面に戻れる

## Validation / Error Handling

- 過去コメント取得件数: ドロップダウンのため不正値は入力不可
- デバッグモード: トグルのため不正値は入力不可

## Test Expectations

- **unit**: shared_preferences の読み書きヘルパーのテスト
- **widget**: SettingsScreen のレイアウト検証、トグル操作でstate変更、ドロップダウン選択で値変更、グレーアウトセクションのタップが無効であること
- **integration**: なし

## Assumptions

- グレーアウトは `Opacity(opacity: 0.38)` + `IgnorePointer` で実現する（Material Design の disabled opacity に準拠）
- グレーアウトセクションは仕様の既定値をそのまま表示する（棒読みちゃん: 速度 -1 等）
- エンジン選択ラジオの連動（棒読み/VOICEVOX セクション切り替え）はグレーアウト状態では固定表示とし、棒読みちゃんセクションを既定表示する

## AI実装適性

**High** — UI構築と shared_preferences 連携は定型的な作業

## Human Approval Needed

**Yes** — グレーアウトの見た目・UIレイアウトがオーナーの想定と合っているか確認が必要


---

## 完了時の手順

この Issue の実装が完了したら、以下を行うこと:

1. GitHub Issue にコメントで完了報告を記載する
   - 変更したファイル一覧
   - 実装した内容の要約
   - 意図的に実装しなかった内容
   - テスト結果
   - 残存リスク・フォローアップ事項
2. PR 作成時は、PR 本文に GitHub Issue URL を記載する（例: `Closes https://github.com/sahya/comerune/issues/19`）
3. GitHub Issue をクローズする
