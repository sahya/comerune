# Issue #15 分解: コメント表示E2Eフロー完成（音声読み上げグレーアウト版）

## 方針

Issue #15（全体結合・E2E）の受け入れ基準のうち、音声読み上げ関連を一旦グレーアウトし、コメント表示E2Eフローを先行して完成させる。

---

## 1. 仕様要約

- **feature summary**: Issue #15 のE2E結合を、読み上げ機能をグレーアウトした形で段階的に実現する
- **user-visible behavior**: URL入力 → 接続 → コメント一覧にリアルタイム表示 → 停止/再接続。設定画面は読み上げセクションがグレーアウトされた状態で表示される
- **main flows**: §10.1 基本コメント閲覧、§10.2 接続失敗、§10.3 自動再接続、§10.4 放送終了、§10.5 別放送切り替え
- **data/state impact**: ConnectionSupervisor → SessionWsClient → NDGR/Legacy client → MessageNormalizer → TimelineStore → CommentScreen という全データフローの結合
- **validation/error points**: エラーコード表示（§13.1）、Snackbar（FAILED時）、Wi-Fiアイコン色切替、legacy未対応フォーマット表示

## 2. 不明点 / 曖昧点 / 要確認事項

1. **CommentScreen が2ファイル存在する**: `presentation/comment/comment_screen.dart`（スケルトン）と `presentation/screens/comment_screen.dart`（フル実装）。後者が正と思われるが、main.dart は前者を参照。統合時に整理が必要
2. **Issue #5（SessionWsClient）が未実装**: lib/ に該当ファイルなし。E2E結合の前提条件として先行実装が必須
3. **Issue #6（NdgrClient）が未実装**: lib/ に該当ファイルなし。NDGRコメント取得の前提条件
4. **Issue #8（再接続・バックオフ）が未実装**: ConnectionSupervisor に状態遷移はあるが、実際の再接続ロジック（指数バックオフ、タイマー制御）は未実装
5. **グレーアウトの表現方法が未確定**: `Opacity + IgnorePointer` か `AbsorbPointer` か。オーナー確認が必要
6. **SettingsScreen と CommentScreen 間の設定値受け渡し方法が未確定**: コールバック渡しか shared_preferences 直接参照か
7. **過去コメント取得件数の変更タイミング**: 仕様上「次回接続開始時に反映」だが、TimelineStore.setCapacity() の呼び出しタイミングを明確にする必要がある

## 3. Epic

- **title**: コメント表示E2Eフロー完成（音声読み上げグレーアウト版）
- **goal**: Issue #15 の受け入れ基準のうち読み上げ以外をすべて通過させる。音声読み上げ機能と設定UIはグレーアウトし、コメント表示・接続・停止・再接続・設定（一部）が動作する状態を実現する
- **overall acceptance criteria**:
  - URL入力 → 接続 → コメントがリアルタイムで表示される
  - 停止/再接続/放送終了の各フローが正常に動作する
  - 設定画面が表示され、デバッグモードと過去コメント件数が変更可能
  - 読み上げ関連UIはグレーアウト状態で表示される
  - 瞬断後に自動復帰する

## 4. Issue Breakdown

| Issue | Title | 概要 |
|-------|-------|------|
| #19 | SettingsScreen 構築（読み上げグレーアウト版） | 設定画面UI。読み上げセクションはグレーアウト、コメント表示設定とデバッグモードのみ有効 |
| #20 | 全コンポーネントのDI配線とE2Eフロー結合 | main.dart で全コンポーネントを生成・注入し、URL入力→コメント表示の全体フローを動作させる |
| #21 | コメント表示E2E手動確認とデバッグ | 実機で全ユーザーフロー（§10.1〜10.5）を確認し、バグを修正する |

各 Issue の詳細は以下を参照:
- [issue-19.md](issue-19.md)
- [issue-20.md](issue-20.md)
- [issue-21.md](issue-21.md)

## 5. 実装順序の提案

### 依存グラフ

```
[先行必須: Issue #5, #6, #8 — 未実装]
        │
        ▼
  Issue #19 ──────────┐
 (SettingsScreen)      │
        │              │
        ▼              ▼
     Issue #20
 (全コンポーネント配線)
        │
        ▼
     Issue #21
 (E2E動作確認)
```

### 順序依存が強い Issue

- **Issue #20 → Issue #21**: 配線完了後にE2E確認を行う（厳密な順序依存）
- **Issue #5, #6, #8 → Issue #20**: 未実装の前提コンポーネントが #20 のブロッカー

### 並列実装できる Issue

- **Issue #19（SettingsScreen）** は Issue #5, #6, #8 と並列実装可能（UIのみで接続ロジックに依存しない）
- **Issue #5, #6, #8** は互いに並列実装可能（各コンポーネントは独立）

### 推奨タイムライン

```
Phase 0 (並列): Issue #5 + Issue #6 + Issue #8 + Issue #19
Phase 1 (直列): Issue #20（全コンポーネント配線）
Phase 2 (直列): Issue #21（E2E確認）
```

## 6. リスク

### Architecture risk

- **CommentScreen の重複ファイル**: `presentation/comment/` と `presentation/screens/` に2つの CommentScreen が存在する。統合時にどちらを正とするか（`screens/` が正と推定）、import の整理が必要。間違えると既存テストが壊れる可能性がある
- **設定値の受け渡し方法**: 現在の CommentScreen は `debugMode` を外部 prop で受け取る設計だが、main.dart からの受け渡しチェーンが長くなる。v1.2 では DI ライブラリなしの設計のため、prop drilling が深くなる可能性がある

### Requirement risk

- **Issue #5, #6, #8 が未実装**: E2E の最大のブロッカー。これらのインターフェースが確定しないと Issue #20 の設計が決まらない。特に SessionWsClient のイベント通知方式（Stream? Callback? ChangeNotifier?）が配線方法に直接影響する
- **NDGR の Protobuf 対応**: NdgrClient は Protobuf length-delimited stream のデコードが必要。Flutter で使用する Protobuf ライブラリの選定が Issue #6 のスコープだが、未確定の場合は配線時に影響する

### Testing risk

- **実機テスト依存**: E2E 確認は実際のニコニコ生放送サーバへの接続が必要。テスト用の放送がないと確認できない項目がある（特に NDGR 接続、瞬断復帰）
- **legacy 接続のテスト困難性**: legacy 接続が発生する条件（NDGR 非対応の放送）が限定的であり、テスト機会が少ない可能性がある

## 7. 実装済み / 未実装の現状

### 実装済み（Issue #15 の前提条件）

| Issue | 内容 | 状態 |
|-------|------|------|
| #2 | AppMessage モデル + LvParser | 完了 |
| #3 | ConnectionSupervisor 状態機械 | 完了 |
| #4 | TimelineStore リングバッファ | 完了 |
| #7 | LegacyCommentClient + MessageNormalizer | 完了 |
| #9 | SelectScreen | 完了 |
| #10 | CommentScreen UI | ほぼ完了（`presentation/screens/comment_screen.dart` にフル実装あり） |

### 未実装（ブロッカー）

| Issue | 内容 | 影響 |
|-------|------|------|
| #5 | SessionWsClient（入口WS） | 接続フローの起点。これがないと何も繋がらない |
| #6 | NdgrClient（NDGR コメント取得） | NDGR モードのコメント表示不可 |
| #8 | 再接続・バックオフロジック | 瞬断復帰・自動再接続不可 |
| #12 | SettingsScreen | → Issue #19 で代替（グレーアウト版） |

### グレーアウト対象（後回し）

| Issue | 内容 | 理由 |
|-------|------|------|
| #11 | SpeechEngine / Queue / Filter 基盤 | 読み上げ機能 |
| #13 | BouyomiEngine（棒読みちゃんTCP） | 読み上げ機能 |
| #14 | VoicevoxEngine（VOICEVOX HTTP） | 読み上げ機能 |
