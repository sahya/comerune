# comment_screen.dart 責務分割ロードマップ (Issue #718 / ARCH-3)

> **本書は「実装着手前の計画ドキュメント」です。** 本書は調査・提案にとどまり、実装には踏み込みません。**human owner の承認** を得るまで、ここで提案する分割作業は開始しません。承認後、各分割単位ごとに別 Issue を切り出して段階的に進めます。

---

## 1. ゴールと非ゴール

### 1.1 ゴール
- `lib/presentation/screens/comment_screen.dart` (~5,858 行) の **責務分割の単位・順序・リスク** を整理する。
- PR #704〜#707 が同ファイルに集中させた変更を、将来は **小さく独立した単位に分けて手を入れられる** 状態に持っていくための地図を残す。
- 主要な State フィールド・helper widget・lifecycle hook が、どの責務ユニットに属するかを **対応表** で明示する。

### 1.2 非ゴール (本書では扱わない)
- 実際の分割実装。各分割は別 Issue で扱う。
- Riverpod / GetIt / その他 DI の導入是非。
- `TimelineStore` 等の上位レイヤー API 設計の見直し (Issue #709 等で別途)。
- 他ファイル (`tts_settings_screen.dart` など) のリファクタ。

---

## 2. 現状の概況

| 指標 | 値 |
|---|---|
| 行数 | **5,858 行** |
| トップレベル宣言数 | **18** (class / enum / mixin) |
| `_CommentScreenState` 行範囲 | 566〜4,376 (約 3,810 行) |
| State メソッド数 | 約 **80+** (`_xxx` プレフィックスを含む) |
| State フィールド数 | 約 **40+** |
| 主要な内蔵 widget | `_OverflowMenuRow`, `_ProgramTitleBar`, `_StatusBar` (+`_StatusBarState`), `_BroadcasterIcon`, `_PinnedCommentsSection`, `_PinnedCommentRow`, `_SubcategoryCache`, `_CommentRow` (+`_CommentRowState`), `_MuteBanner`, `_SpeechStatusIcon` |
| 公開 (テスト用) ハーネス | `CommentRowHarness`, `PinnedCommentRowHarness` |

`_CommentScreenState` は単一クラスでありながら、**少なくとも 11 種類の責務領域** を抱えている (詳細は §3)。これが ARCH-3 の根本的な負債源。

---

## 3. 分割単位候補

ファイル全体を読み、State フィールド / メソッド / 内蔵 widget を機能領域でクラスタリングした結果、以下 **11 ユニット** に整理できる。

| # | ユニット名 | 主な責務 | 該当行 (代表) |
|---|---|---|---|
| U1 | **Speech (TTS) 制御** | 読み上げエンジンの初期化・停止・状態追跡・失敗ハンドリング | 1245–1900, 5715–5858 |
| U2 | **Auto-scroll** | 末尾追従・ユーザー操作再開判定 | 3420–3480, 4322–4376 |
| U3 | **NG 保護通知 / NG マッチャ** | 非表示数 badge, snackbar throttle, NgMatcher 構築 | 2187–2410, 3804–3854 |
| U4 | **Search (キーワード検索)** | AppBar 検索 UI, debounce, 正規化マッチ | 3673–3784 |
| U5 | **Mute (AppBar mute)** | AppBar アイコン経由の volume 0 操作と pre-mute slot | (Speech / settings_store と境界共有) |
| U6 | **Comment posting (FAB)** | 投稿入力 UI / 放送者判定 / 投稿フィードバック | 2039–2186 |
| U7 | **Comment list / pinned / 表示行** | タイムライン slice, pin/unpin, sort, displayName 解決 | 1980–2038, 2891–3240, 4795–5677 |
| U8 | **Stats panel & Log save** | 統計シート, 自動/手動ログ保存 | 3870–4296 |
| U9 | **Connection / lifecycle** | ConnectionStatus 監視, 終了処理, AppBar action bar | 3239–3416 |
| U10 | **Wakelock** | 接続状態に応じた wakelock toggle | 3908–3954 |
| U11 | **AppBar / Overflow / Status Bar / Program Title** | AppBar 系 widget 群 | 4377–4672 |

> ユニットは **責務クラスタの目安** であり、最終的な mixin/widget/controller の単位とは必ずしも一致しない。分割実装時に「ユニットを そのまま 1 ファイルに切り出す」「複数ユニットを 1 ファイルに束ねる」といった判断を別 Issue で行う。

---

## 4. 状態フィールド × ユニット 対応表

| State フィールド | 行 | 所属候補ユニット | 備考 |
|---|---|---|---|
| `_scrollController` | 576 | U2 | dispose 必須 |
| `_lastStatus` | 577 | U9 | ConnectionStatus 派生 |
| `_autoScrollEnabled` | 578 | U2 | |
| `_isStoppingForExit` | 579 | U9 | |
| `_isSavingLog` | 580 | U8 | |
| `_endedAt` | 584 | U9 | |
| `_pendingStatsMessages` | 591 | U8 | |
| `_statsPanelExpanded` | 596 | U8 | |
| `_pinnedMessageIds` | 598 | U7 | |
| `_touchActive` | 599 | U7 (or U2) | スクロール再開と兼ねる |
| `_speechInitializing` | 601 | U1 | |
| `_speechInitialized` | 602 | U1 | |
| `_speechStarted` | 603 | U1 | |
| `_speechEngineState` | 604 | U1 | **String 型 / マジック文字列**。Issue #717 (ARCH-2) で enum 化予定 |
| `_consecutiveAndroidTtsFailures` | 612 | U1 | |
| `_wakelockReleaseTimer` | 623 | U10 | |
| `_speechPollTimer` | 628 | U1 | |
| `_speechEventSub` | 629 | U1 | dispose 必須 |
| `_lastSpeechMessageId` | 635 | U1 | |
| `_lastAutoScrollObservedLastId` | 647 | U2 | aliasing 罠の cursor (#670 / #699) |
| `_lastProcessedTailMessageId` | 671 | U7 | |
| `_recentlyProcessedNicknameMessageIds` | 700 | U7 | nickname 自動登録、cap = 200 (`_kRecentlyProcessedNicknameIdsCap`) |
| `_seedNextTailObservationSilently` | 714 | U7 | clear→backfill 抑止 |
| `_speechBaselineTimestamp` | 719 | U1 | |
| `_effectivePresetNgWords` | 720 | U3 | |
| `_effectivePresetCategories` | 729 | U3 | |
| `_ngMatcher` | 735 | U3 | |
| `_commentPostUserSession` | 739 | U6 | |
| `_isBroadcaster` | 743 | U6 | |
| `_commentInputExpanded` | 748 | U6 | |
| `_commentInputSending` | 753 | U6 | |
| `_commentPostContextGeneration` | 760 | U6 | race-cond 用 |
| `_protectedCount` | 773 | U3 | |
| `_lastProtectionNotificationAt` | 777 | U3 | |
| `_lastProtectionInspectedMessageId` | 781 | U3 | aliasing 罠の cursor |
| `_isSearching` | 797 | U4 | |
| `_searchQuery` / `_normalizedSearchQuery` | 798/803 | U4 | |
| `_normalizedContentCache` | 816 | U4 | dispose で clear |
| `_searchController` | 817 | U4 | dispose 必須 |
| `_searchFocusNode` | 818 | U4 | dispose 必須 |
| `_searchDebounceTimer` | 821 | U4 | dispose 必須 |

### 4.1 共有・横断のフィールド

- `widget.messages` (List<AppMessage>) は U1 / U2 / U3 / U7 / U8 すべてが消費する。これは `TimelineStore` 所有のため移管不要だが、**snapshot 化** (Issue #709 案 B) で aliasing 罠を根絶することで、各ユニットの cursor (`_lastSpeechMessageId` 等) を将来統合する余地が生まれる。
- `widget.callbacks` (CommentCallbacks) は U7 / U6 が中心に呼ぶが、テスト性を損なわない範囲で各ユニットへ委譲できる。

---

## 5. 分割順序 (低リスク → 高リスク)

各ユニットの **境界の独立度** と **回帰リスク** で評価し、低リスクから順に切り出すことを推奨する。

| 順 | ユニット | 推定リスク | 理由 |
|---|---|---|---|
| 1 | U10 Wakelock | **極小** | 入出力が `ConnectionStatus` のみ。State フィールドは 1 つ (`_wakelockReleaseTimer`) のみ。境界明確 |
| 2 | U4 Search | **小** | UI と内部状態が閉じている。`_normalizedContentCache` の lifetime も閉じている。回帰確認が widget test で完結 |
| 3 | U8 Stats panel & Log save | **小〜中** | sheet の表示 / 保存ロジックは独立。ただし `_messagesForLog` が U7 と通信する点に注意 |
| 4 | U6 Comment posting | **中** | 既に generation cursor で race を捌けており境界が綺麗。ただし Snackbar 経路を共有しているため UI レイヤ干渉に要注意 |
| 5 | U3 NG 保護通知 / NgMatcher | **中** | `_ngMatcher` の rebuild タイミング (`_rebuildNgMatcher`) を漏らさず再現する必要あり。aliasing 罠 cursor が含まれるため Issue #709 完了後がより安全 |
| 6 | U2 Auto-scroll | **中** | `_isNearBottom`/`_handleScroll*` は `_scrollController` を中心に閉じているが、`_touchActive` の所有が U7 と曖昧 |
| 7 | U7 Comment list / pinned / 表示行 | **大** | 行数が最大、`_CommentRow` widget も含むため切り出し時のテスト面が広い |
| 8 | U9 Connection / lifecycle | **大** | AppBar の bottom action bar まで巻き込む。終了 / 切断 / 復帰系の挙動退化リスク高 |
| 9 | U1 Speech (TTS) 制御 | **特大** | PR #704〜#707 全部の交差点。enum 化 (Issue #717) と SSOT (Issue #716) が先行している前提で着手すべき |
| 10 | U11 AppBar / Overflow / Status Bar / Program Title | **大** | 既に widget は別クラスだが、上位の AppBar 構築コードが build メソッド内に深く埋まっており慎重に剥がす必要 |
| 11 | U5 Mute | **特大** | 厳密には U1 と境界を共有。AppBar mute と pre-mute slot の責務分配は別途 RFC 相当の議論が必要 |

> **注意**: 順序は「依存関係」ではなく「現実的に着手しやすい順」。U1 / U5 は他ユニットが落ち着いてから取り組む方が、スタックの認知負荷を下げられる。

---

## 6. ユニット別 リスクと回帰テスト計画

### U1 Speech (TTS)
- **退化リスク**:
  - native event ↔ Dart cross-screen notifier ↔ init failure ↔ recovery heuristic の 4 source 経路が壊れると ERROR / READY が即座に誤遷移する。
  - PR #707 由来の AppBar mute による両エンジン volume 0 の挙動変化。
- **回帰テスト**:
  - 既存 `comment_screen_speech_test.dart` の波形を必ず維持。
  - enum 化 (#717) と SSOT (#716) 完了後に着手し、その時点で網羅されている境界 (READY / ERROR / UNKNOWN ↔ '') をスナップショット化。
  - `_SpeechStatusIcon` の icon 状態決定を pure function 化 (#717) してから widget 切り出し。

### U2 Auto-scroll
- **退化リスク**: `_isNearBottom` の閾値、`_lastAutoScrollObservedLastId` の cursor 同期、ユーザータッチ中の追従抑制。
- **回帰テスト**: 既存 widget test (auto-scroll resume / pause)。pinned / FAB 表示と組み合わせたインテグレーションシナリオを必ず追加してから移動する。

### U3 NG 保護通知 / NgMatcher
- **退化リスク**:
  - `_protectionSnackBarWindow` (10 秒) のスロットリングが壊れると burst 時に snackbar スパム。
  - `_lastProtectionInspectedMessageId` の cursor は aliasing 罠を踏み得る (#709 案 B 後の再評価対象)。
- **回帰テスト**: 既存 NG protection テスト。`_rebuildNgMatcher` の trigger 条件を変えないこと (preset 反映 / settings 変更時)。

### U4 Search
- **退化リスク**: debounce 期間, 正規化キャッシュの dispose 漏れ。
- **回帰テスト**: 検索状態のクリア, AppBar フォーカス順, 長文 paste 時の TextField 上限 (`_kSearchMaxLength`)。

### U5 Mute
- **退化リスク**: AppBar mute の **両エンジン同時 volume 0** 契約 (PR #707) と、TTS settings 画面 indicator 表示 (Issue #714 で active engine 側のみ) の整合性。
- **回帰テスト**: AppBar mute → settings 画面遷移 → indicator 場所が正しい、を engine 切替で繰り返し検証。

### U6 Comment posting
- **退化リスク**: `_commentPostContextGeneration` を保たないと race で broadcaster フラグが古い結果で上書きされる。
- **回帰テスト**: 高速な lv 切替時の broadcaster 状態維持テスト。

### U7 Comment list / pinned / 表示行
- **退化リスク**: `_CommentRow` の rebuild コスト, pinned の eviction, sort トグル, `_displayNameFor` の優先順位。
- **回帰テスト**: 既存の `_CommentRow` widget test (大量)。`_messagesForLog` の境界テスト (`comment_screen_log_test.dart`) を維持。

### U8 Stats panel & Log save
- **退化リスク**: `_isAutoSaveTrigger` / `_isStatsTrigger` のトリガー条件変化, `_messagesForStatsAndLogs` のフィルタ。
- **回帰テスト**: 自動保存トリガー, シート開閉, minute offset スクロール。

### U9 Connection / lifecycle
- **退化リスク**: dispose 順序 (timer / subscription / wakelock)。
- **回帰テスト**: 既存 connection widget test を必ず維持。終了 / 失敗 / 再接続シナリオ。

### U10 Wakelock
- **退化リスク**: 切断時の wakelock release 遅延 (45 秒 grace) が壊れると即座にスリープ。
- **回帰テスト**: status 遷移ごとの wakelock 状態 fake test。

### U11 AppBar / Overflow / Status Bar
- **退化リスク**: overflow menu のメニュー順, status bar の elapsed timer dispose。
- **回帰テスト**: overflow menu open, status bar collapse / expand。

---

## 7. 想定される追加 Issue (本ロードマップ承認後に切り出す案)

> 番号は仮。承認後に GitHub Issue として正式採番する。

- **ARCH-3a** Wakelock 切り出し (U10)
- **ARCH-3b** Search 切り出し (U4)
- **ARCH-3c** Stats panel & Log save 切り出し (U8)
- **ARCH-3d** Comment posting 切り出し (U6)
- **ARCH-3e** NG 保護通知 / NgMatcher 切り出し (U3)
- **ARCH-3f** Auto-scroll 切り出し (U2)
- **ARCH-3g** Comment list / pinned / 表示行 切り出し (U7)
- **ARCH-3h** Connection / lifecycle 切り出し (U9)
- **ARCH-3i** Speech (TTS) 制御 切り出し (U1) — **#716 / #717 の完了が前提**
- **ARCH-3j** AppBar / Overflow / Status Bar 切り出し (U11)
- **ARCH-3k** Mute 責務の整理 (U5) — **U1 完了後に RFC 相当**

各 Issue は以下を満たすこと:
- 対象ユニットの State フィールド・メソッド・widget の **inventory** をリスト化
- 切り出し前後の挙動比較を可能にする **回帰テストのリスト** を含む
- public な API を変えない (他レイヤーから見える挙動変化なし)
- 1 PR あたり ±300〜±800 行を上限の目安とする

---

## 8. 想定外スコープ

- Riverpod / GetIt / Provider への置き換え: **本書では判断しない**。U1〜U11 すべてが in-place mixin / 専用 controller / extension で切り出せれば、状態管理ライブラリの変更なしに段階的に到達できる。
- VoidCallback ベースの `widget.callbacks` を Stream 化する設計変更。
- `TimelineStore` の API 変更 (Issue #709 で別途扱う)。
- 公開テストハーネス (`CommentRowHarness` 等) の改廃。

---

## 9. 承認フローと完了定義

### 9.1 本書 (Issue #718) の完了定義
本書をリポジトリにマージ → human owner がレビューし、§3 のユニット分割と §5 の順序提案について **承認 / 修正指示 / 棄却** のいずれかを意思表示する → 承認時のみ §7 の追加 Issue を切り出す。

### 9.2 各分割実装 PR の完了定義
- 対象ユニットの State / メソッド / widget が指定モジュールへ移動完了
- 既存テスト 100% パス + 該当ユニットの回帰テストが追加されている
- `flutter analyze` / `dart format .` クリーン
- public な振る舞い変化ゼロ (動作確認スクショ or テストでの担保)

### 9.3 ロールバック方針
1 PR 単位で `git revert` 可能な大きさに留める。コミット粒度を細かくし、機能フラグの導入は原則しない (UI レイヤのため)。

---

## 10. 参考

- Issue #718 (本ロードマップ自体)
- Issue #717 ARCH-2 (`_speechEngineState` enum 化, U1 着手の前提)
- Issue #716 ARCH-1 (`SpeechFailureReason` SSOT, U1 着手の前提)
- Issue #709 (TimelineStore snapshot, U2 / U3 / U7 cursor 群整理の前提)
- PR #704〜#707 (本ファイルへの直近の変更集中, 本 issue の動機)
