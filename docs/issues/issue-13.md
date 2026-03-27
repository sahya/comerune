# Issue #13: BouyomiEngine（棒読みちゃん TCP 連携）の実装

Labels: v1.2, speech

GitHub Issue: https://github.com/sahya/comerune/issues/13

Epic: #1

## Goal

棒読みちゃんに TCP でコメントを送信して読み上げさせる。

## Scope

- `SpeechEngine` を実装する `BouyomiEngine` クラス
- TCP接続（1発話=1接続）
- 15byte 固定ヘッダ + 本文のプロトコル実装
- 接続先: 設定画面のホスト + ポート 50001（固定）
- speed / tone / volume / voice / charset の設定適用
- 接続失敗・タイムアウト時は発話をスキップ（キューを詰まらせない）

## Non-scope

- UI（設定画面は Issue #12 で実装済み）
- キュー制御・フィルタ（Issue #11 で実装済み）

## Dependencies

- Issue #11（SpeechEngine 基盤）
- Issue #12（設定値の取得）

## Acceptance Criteria

- [ ] 棒読みちゃんが動作する PC にコメントを送信できる
- [ ] 15byte ヘッダが正しく構成される
- [ ] speed / tone / volume / voice が設定値通りに送信される
- [ ] 接続失敗時は発話をスキップし、次のコメントの処理が続行される
- [ ] タイムアウト時もスキップして続行される

## Validation / Error Handling

- TCP 接続失敗 → ログ出力、発話スキップ
- タイムアウト → ログ出力、発話スキップ

## Test Expectations

- **unit**: ヘッダ構築ロジック、パラメータ適用
- **widget**: なし
- **integration**: 実際の棒読みちゃんへの接続テスト（手動）

## Assumptions

- 棒読みちゃんの TCP プロトコルは Qiita 参考記事（統合仕様 §16.5）に準拠する

## AI実装適性

**High** — TCPプロトコルが参考記事で明確に定義されている

## Human Approval Needed

**No**


---

## 完了時の手順

この Issue の実装が完了したら、以下を行うこと:

1. GitHub Issue にコメントで完了報告を記載する
   - 変更したファイル一覧
   - 実装した内容の要約
   - 意図的に実装しなかった内容
   - テスト結果
   - 残存リスク・フォローアップ事項
2. PR 作成時は、PR 本文に GitHub Issue URL を記載する（例: `Closes https://github.com/sahya/comerune/issues/13`）
3. GitHub Issue をクローズする
