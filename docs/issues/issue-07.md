# Issue #7: LegacyCommentClient（legacy コメント取得クライアント）の実装

Labels: v1.2, infra

GitHub Issue: https://github.com/sahya/comerune/issues/7

Epic: #1

## Goal

入口WSから取得した legacy wss URL に接続し、JSON から `chat` キーでコメントを抽出して AppMessage に変換する。

## Scope

- legacy wss URL への WebSocket 接続
- 受信 JSON の `chat` キーからコメント抽出（content, userId, timestamp）
- AppMessage への正規化（MessageNormalizer の legacy 部分）
- `chat` キーが存在しないメッセージの処理:
  - コメント一覧にシステム行「legacy: 未対応フォーマット」を追加
  - デバッグログに raw JSON を出力
  - 読み上げ対象外
- 抽出部を差し替え可能な設計

## Non-scope

- 再接続ロジック（Issue #8）
- UI表示
- `chat` 以外のキーの抽出（v1.3 予定）

## Dependencies

- Issue #2（AppMessage モデル）
- Issue #4（TimelineStore）

## Acceptance Criteria

- [ ] legacy wss URL に WebSocket 接続できる
- [ ] `chat` キーを含む JSON からコメント本文・userId・timestamp を抽出できる
- [ ] `chat` キーが無い JSON は「legacy: 未対応フォーマット」として AppMessage を生成する
- [ ] 未対応フォーマットの AppMessage は読み上げ対象外として区別できる
- [ ] 抽出ロジックが差し替え可能な構造になっている
- [ ] アプリがクラッシュしない（未知フォーマットへの耐性）

## Validation / Error Handling

- JSON パース失敗 → ログ出力してスキップ
- WS切断 → エラー通知

## Test Expectations

- **unit**: chat キー有りの抽出、chat キー無しの処理、JSON パース失敗
- **widget**: なし
- **integration**: なし（legacy サーバの実サンプルが未確定のため）

## Assumptions

- legacy の JSON 構造は `{"chat": {"content": "...", "user_id": "...", ...}}` に近い形を想定するが、実サンプルでの検証が必要

## AI実装適性

**High** — `chat` キーのみの抽出は単純。差し替え可能設計もインターフェース分離で対応可能

## Human Approval Needed

**Yes** — legacy の JSON 構造が未確定のため、実サンプルによる検証後に抽出ロジックの妥当性を確認する必要がある


---

## 完了時の手順

この Issue の実装が完了したら、以下を行うこと:

1. GitHub Issue にコメントで完了報告を記載する
   - 変更したファイル一覧
   - 実装した内容の要約
   - 意図的に実装しなかった内容
   - テスト結果
   - 残存リスク・フォローアップ事項
2. PR 作成時は、PR 本文に GitHub Issue URL を記載する（例: `Closes https://github.com/sahya/comerune/issues/7`）
3. GitHub Issue をクローズする
