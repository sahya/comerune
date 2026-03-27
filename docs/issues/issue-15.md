# Issue #15: 全体結合・E2E フローの確認とデバッグ

Labels: v1.2, integration

GitHub Issue: https://github.com/sahya/comerune/issues/15

Epic: #1

## Goal

Issue #2〜#14 の全コンポーネントを結合し、統合仕様 §14 の受け入れ基準をすべて通過することを確認する。

## Scope

- ConnectionSupervisor による全体の接続フロー結合（SessionWsClient → NDGR/legacy 判別 → コメント取得 → 表示 → 読み上げ）
- 画面遷移フロー（SelectScreen → CommentScreen → SettingsScreen）
- 全ユーザーフロー（UI仕様 §10.1〜10.5）の動作確認
- エラーフロー（接続失敗、瞬断、放送終了）の動作確認
- 読み上げフロー（棒読みちゃん、VOICEVOX）の動作確認
- 設定の永続化確認

## Non-scope

- 新規機能の追加
- パフォーマンスチューニング

## Dependencies

- Issue #2〜#14 すべて

## Acceptance Criteria

- [ ] URL 貼り付けで lv が抽出される
- [ ] 接続開始でコメントが流れる（NDGR）
- [ ] legacy 接続時に chat キーのコメントが表示される
- [ ] legacy 接続時に chat キー無しでクラッシュせず「legacy: 未対応フォーマット」が表示される
- [ ] 接続停止で確実に停止する
- [ ] Wi-Fi アイコンが状態に応じて赤/緑で切り替わる
- [ ] 新着で自動スクロール（ユーザースクロール中は停止）
- [ ] 棒読みちゃんで読み上げが動作する
- [ ] VOICEVOX で読み上げが動作する
- [ ] 瞬断後に自動復帰する（通常30秒以内）
- [ ] デバッグ情報が揃っている

## Validation / Error Handling

- 全エラーコードの表示確認

## Test Expectations

- **unit**: なし（各 Issue でテスト済み）
- **widget**: なし（各 Issue でテスト済み）
- **integration**: 実機での E2E テスト（手動）

## Assumptions

なし

## AI実装適性

**Low** — 実機テストとデバッグが中心。実際の放送サーバへの接続が必要

## Human Approval Needed

**Yes** — 最終的な動作確認はオーナーが行う必要がある


---

## 完了時の手順

この Issue の実装が完了したら、以下を行うこと:

1. GitHub Issue にコメントで完了報告を記載する
   - 変更したファイル一覧
   - 実装した内容の要約
   - 意図的に実装しなかった内容
   - テスト結果
   - 残存リスク・フォローアップ事項
2. PR 作成時は、PR 本文に GitHub Issue URL を記載する（例: `Closes https://github.com/sahya/comerune/issues/15`）
3. GitHub Issue をクローズする
