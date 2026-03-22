# Issue #1: Epic: comerune v1.2 — ニコ生コメント取得・表示・読み上げアプリ

Labels: epic, v1.2

GitHub Issue: https://github.com/sahya/comerune/issues/1

## Goal

ニコ生の放送IDを入力してコメントをリアルタイム表示し、棒読みちゃん/VOICEVOXで読み上げできるAndroidアプリを完成させる。

## Overall Acceptance Criteria

- [ ] URL貼り付けで lv が抽出され、接続でコメントが流れる
- [ ] NDGR/legacy を自動判別して接続できる
- [ ] Wi-Fiアイコンが状態に応じて赤/緑で切り替わる
- [ ] 新着で自動スクロール（ユーザースクロール中は停止）
- [ ] 棒読みちゃん（TCP）とVOICEVOX（HTTP API）の両方で読み上げが動作する
- [ ] 瞬断後に自動復帰する（通常30秒以内）
- [ ] デバッグ情報が揃っている

## Issue Breakdown

| # | Title | 依存 |
|---|-------|------|
| #2 | AppMessage モデルと LvParser の実装 | なし |
| #3 | ConnectionSupervisor 状態機械の実装 | #2 |
| #4 | TimelineStore（リングバッファ付きコメント管理）の実装 | #2 |
| #5 | SessionWsClient（入口WebSocket接続）の実装 | #2 |
| #6 | NdgrClient（NDGR コメント取得クライアント）の実装 | #2, #4 |
| #7 | LegacyCommentClient（legacy コメント取得クライアント）の実装 | #2, #4 |
| #8 | 再接続・指数バックオフ・ストール検出の実装 | #3, #5, #6, #7 |
| #9 | SelectScreen（接続先選択画面）の実装 | #2, #3 |
| #10 | CommentScreen（コメント閲覧画面）の実装 | #3, #4, #9 |
| #11 | 読み上げ基盤（SpeechEngine / キュー制御 / フィルタ）の実装 | #2 |
| #12 | SettingsScreen（設定画面）の実装 | #10 |
| #13 | BouyomiEngine（棒読みちゃん TCP 連携）の実装 | #11, #12 |
| #14 | VoicevoxEngine（VOICEVOX HTTP API 連携 + 音声再生）の実装 | #11, #12 |
| #15 | 全体結合・E2E フローの確認とデバッグ | #2〜#14 |

## 並列実装可能なグループ

| グループ | Issues | 前提 |
|---------|--------|------|
| A: データモデル層 | #2, #3, #4 | #2 完了後に #3, #4 は並列可能 |
| B: 接続クライアント層 | #5, #6, #7 | #2, #4 完了後に #5, #6, #7 は並列可能 |
| C: UI層 | #9, #10 | #3, #4 完了後に着手。#9 → #10 は順序依存 |
| D: 読み上げ層 | #11, #13, #14 | #2 完了後に #11 着手。#11, #12 完了後に #13, #14 は並列可能 |

## リスク

### Architecture Risk
- Protobuf ライブラリ選定（Dart の length-delimited stream decode 対応）
- DI なしの手動組み立ての破綻可能性

### Requirement Risk
- legacy コメントの JSON 構造が未確定
- 入口WS のメッセージフォーマット変動
- NDGR の .proto 定義が非公開（参考実装からの推定）
- 再接続上限回数が未定義

### Testing Risk
- 実際の放送サーバへの接続テストが必須
- 棒読みちゃん/VOICEVOX の結合テストは CI 困難

## 参照仕様書
- `docs/specs/Integrated_Requirements_and_Specification.md`
- `docs/specs/UI_Specification.md`


---

## 完了時の手順

この Issue の実装が完了したら、以下を行うこと:

1. GitHub Issue にコメントで完了報告を記載する
   - 変更したファイル一覧
   - 実装した内容の要約
   - 意図的に実装しなかった内容
   - テスト結果
   - 残存リスク・フォローアップ事項
2. PR 作成時は、PR 本文に GitHub Issue URL を記載する（例: `Closes https://github.com/sahya/comerune/issues/1`）
3. GitHub Issue をクローズする
