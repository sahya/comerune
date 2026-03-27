# Issue #20: 全コンポーネントのDI配線とコメント表示E2Eフロー結合

Labels: v1.2, integration

GitHub Issue:

Epic: #1

## Goal

SelectScreen でURLを入力し接続を押すと、SessionWsClient → NDGR/Legacy判別 → コメント取得 → TimelineStore → CommentScreen という一連のフローが動作し、画面にコメントが表示されるようにする。読み上げフローは配線しない。

## Scope

- **main.dart の更新**:
  - 全コンポーネントの生成と注入（ConnectionSupervisor, TimelineStore, SessionWsClient, NdgrClient, LegacyCommentClient）
  - SettingsScreen 用の設定値（debugMode, pastCommentCount）を管理し画面間で受け渡す仕組み
- **SelectScreen の更新**:
  - 接続開始時に SessionWsClient.connect() を呼び出す
  - フル実装版 CommentScreen（`presentation/screens/comment_screen.dart`）への切り替え
  - messages, onStopAllConnections, onReconnectSameLv, onDifferentLvConnected, onOpenSettings, debugMode, connectionMethod の受け渡し
- **接続フロー配線**:
  - SelectScreen.connect → SessionWsClient → endpoint検出 → ConnectionSupervisor 状態遷移
  - NDGR endpoint検出 → NdgrClient.subscribe → MessageNormalizer → TimelineStore
  - Legacy endpoint検出 → LegacyCommentClient.connect → TimelineStore
  - TimelineStore.messages → CommentScreen.messages
- **停止フロー配線**:
  - 停止ボタン → SessionWsClient / NDGR or Legacy client 停止 → ConnectionSupervisor.stopByUser() → SelectScreen に pop
  - 戻るボタン → 同上の全停止処理
  - 再接続ボタン（ENDED/FAILED）→ ConnectionSupervisor.retryConnectionFromTerminal() → 同一lv再接続
- **SettingsScreen 連携**:
  - CommentScreen ⋮メニュー → SettingsScreen への Navigator.push
  - debugMode → CommentScreen.debugMode に反映
  - 過去コメント取得件数 → TimelineStore.setCapacity() / NdgrClient の初期ロード件数に反映
- **ファイル整理**:
  - `presentation/comment/comment_screen.dart`（スケルトン）を削除
  - `presentation/screens/comment_screen.dart` を正とし、import を修正

## Non-scope

- 読み上げフロー（SpeechEngine, キュー, フィルタ）の結合
- SessionWsClient / NdgrClient / 再接続ロジックの新規実装（実装済みの前提）
- SettingsScreen の読み上げセクション有効化
- パフォーマンスチューニング

## Dependencies

- **Issue #5（SessionWsClient）** — 未実装・先行必須
- **Issue #6（NdgrClient）** — 未実装・先行必須
- **Issue #8（再接続・バックオフロジック）** — 未実装・先行必須
- **Issue #19（SettingsScreen グレーアウト版）**

## Acceptance Criteria

- [ ] URL貼り付けで lv が抽出され、CommentScreen のデバッグ欄に反映される
- [ ] 接続開始で NDGR コメントが CommentScreen のリストに流れる
- [ ] legacy 接続時に chat キーのコメントが表示される
- [ ] legacy 接続時に chat キー無しで「legacy: 未対応フォーマット」が表示され、クラッシュしない
- [ ] 停止ボタンで全接続が停止し、SelectScreen に戻る
- [ ] 戻るボタン（Android back / AppBar back）で全停止してから SelectScreen に戻る
- [ ] ENDED / FAILED 時に「再接続」ボタンで同一 lv への再接続ができる
- [ ] Wi-Fi アイコンが状態に応じて赤/緑で切り替わる
- [ ] 新着コメントで自動スクロール（ユーザースクロール中は停止、最下部復帰で再開）
- [ ] 瞬断後に自動復帰する
- [ ] デバッグモード ON で接続方式（NDGR/legacy）・接続フェーズが表示される
- [ ] 過去コメント取得件数の設定が次回接続時に反映される
- [ ] 同一 lv 再接続時はコメント一覧が保持される
- [ ] 別 lv 接続時はコメント一覧がクリアされる
- [ ] `presentation/comment/comment_screen.dart`（スケルトン）が削除されている

## Validation / Error Handling

- FAILED 遷移時に Snackbar 表示（エラー原因カテゴリ + 「再接続ボタンで再試行できます」）
- 断続的エラー（RECONNECTING中）は Snackbar 非表示、デバッグ欄の「直近エラー」のみ更新
- 読み上げ失敗エラー（SPEECH_*）は配線対象外のため発生しない

## Test Expectations

- **unit**: DI配線の結合テストは不要（各コンポーネントは個別テスト済み）
- **widget**: SelectScreen → CommentScreen 遷移テスト（モック使用で messages 受け渡し確認）
- **integration**: 実機E2Eテスト（手動、Issue #21 で実施）

## Assumptions

- Issue #5, #6, #8 が実装済みで、インターフェースが確定している前提
- 設定値管理は簡易的な方法（StatefulWidget のstate、またはコールバック経由での受け渡し）で実装する。v1.2 では DI ライブラリを導入しない（統合仕様 §3）
- NdgrClient の過去コメント取得件数は connect 時のパラメータとして渡す設計を想定

## AI実装適性

**Medium** — 配線自体はパターン的だが、各コンポーネントのインターフェース整合と実機動作検証が必要

## Human Approval Needed

**Yes** — 全体フローの動作確認、画面遷移の挙動がオーナーの意図通りか確認が必要


---

## 完了時の手順

この Issue の実装が完了したら、以下を行うこと:

1. GitHub Issue にコメントで完了報告を記載する
   - 変更したファイル一覧
   - 実装した内容の要約
   - 意図的に実装しなかった内容
   - テスト結果
   - 残存リスク・フォローアップ事項
2. PR 作成時は、PR 本文に GitHub Issue URL を記載する（例: `Closes https://github.com/sahya/comerune/issues/20`）
3. GitHub Issue をクローズする
