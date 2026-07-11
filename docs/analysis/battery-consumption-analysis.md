# バッテリー消費分析と省電力化 詳細設計書

- 対象: comerune v1.2.0 時点の `main` 相当コード
- 目的: 現行実装のうちバッテリー消費が大きくなりそうな箇所を特定し、**機能を落とさずに**省電力化できる改善を設計としてまとめる
- 位置づけ: 実装前の分析・設計ドキュメント。個別の改善は本書の Issue 分解案に沿って別 Issue / 別 PR で行う

---

## 1. 分析の前提: このアプリの電力消費モデル

comerune は「ニコ生コメントの取得・表示・読み上げ」アプリであり、消費電力は大きく次の 4 層に分けられる。

| 層 | 内容 | 支配度 | 削減余地 |
|---|---|---|---|
| ① 画面点灯 | wakelock による常時点灯 | 最大（スマホ全体の消費の過半になり得る） | 機能そのものなので既定では削れない。オプション化は可能 |
| ② 無線（radio） | 常時接続（WS + HTTP streaming）、各種ポーリング | 大 | ストリーミングは機能上必須。**ポーリングは削減余地あり** |
| ③ CPU（重い計算） | VOICEVOX 音声合成（ONNX 推論）、NG 判定、UI 再構築 | 中〜大 | 合成は機能上必須。**NG 判定・再構築の「回数の掛け算」は削減余地あり** |
| ④ CPU（細かい起床） | 周期タイマー（1 秒刻み等）、バックグラウンド中の Dart timer | 小〜中 | **削減余地あり**（特にバックグラウンド読み上げ中は wakelock 下で確実に CPU を起こすため） |

ポイント: ①②③の「機能として必須の消費」は削れないが、その周囲に **「同じ仕事を何度もやり直す」「見えていないのに動き続ける」** という掛け算のコストが存在し、そこが省電力化の主戦場になる。

---

## 2. 現状実装の消費要因インベントリ

### 2.1 画面常時点灯（wakelock）

- `lib/presentation/screens/comment_screen.dart:1210` — CommentScreen の `initState` で無条件に `WakelockPlus.enable()`
- 同 `5256-5295` — 接続ステータスに同期して有効/無効を切り替え。`ENDED` 後は 45 秒の猶予（`_wakelockReleaseDelay`、同 `748`）で解放
- 解放漏れ対策（dispose での disable、再接続時のタイマーキャンセル）はテスト込みで実装済み

**評価**: 「視聴中に画面を消さない」はコメントビューアの中核機能であり、既定動作としては妥当。ただし**読み上げ主体で使うユーザー（画面を見ていない）にも常時点灯が強制される**点に、機能を落とさない省電力オプションの余地がある（→ 提案 P6）。

### 2.2 Foreground Service + WakeLock + WifiLock

- `lib/data/foreground_service/foreground_service_manager.dart:76-77` — `allowWakeLock: true` / `allowWifiLock: true`。FGS 稼働中は PARTIAL_WAKE_LOCK と WifiLock を保持
- `lib/application/foreground_service/foreground_service_controller.dart:96-112` — 接続開始（`connectingSessionWs`）の時点で、アプリが前面か背面かに関わらず FGS を起動
- 同 `27, 149` — 放送終了後は 30 秒の猶予（読み上げキュー完了で早期終了、`notifyQueueDrained`）

**評価**: 画面 OFF でのバックグラウンド受信・読み上げを成立させるために WakeLock/WifiLock は必須。画面 ON 中は PARTIAL_WAKE_LOCK は実質無害（画面点灯自体が CPU を起こしている）なので、FGS の起動タイミング自体は現状維持が妥当（→ 7 章 P9 で「変更しない判断」として記録）。**ただしバックグラウンド滞在中は WakeLock 下で Dart timer が確実に CPU を起こすため、④の周期タイマー削減の価値が上がる**。

### 2.3 常時接続（プロトコル由来・必須）

- Session WS: `lib/domain/connection/session_ws_client.dart:577` — keepSeat をサーバー指定間隔（`keepIntervalSec`）で送信。間隔はサーバー主導であり削減不可
- NDGR: HTTP chunked streaming（`lib/domain/connection/ndgr_client.dart`）。`HttpClient` は再利用されており（同 `483-499`）、接続の張り直しコストは抑制済み
- 再接続バックオフ: `lib/domain/connection/connection_supervisor.dart:165` — `[1,2,4,6,8,10,15,20,30]` 秒 + 上限回数。障害時に無線を焼き続けない設計になっており妥当

**評価**: この層は機能そのもの。改善対象外。

### 2.4 ポーリング（無線の間欠起床）

無線は「一度起きると数秒間高電力状態に留まる」ため、ポーリングは本数と頻度がそのまま電池に効く。

| ポーリング | 間隔 | ライフサイクル制御 | 根拠 |
|---|---|---|---|
| フォロー中番組 + 自分の番組（`_fetchAllPrograms`） | 60 秒 | **なし**（背面でも、CommentScreen が上に乗っていても継続） | `lib/presentation/select/select_screen.dart:314`, `1778-1783` |
| お気に入りユーザー放送チェック | 前面 15 秒 / 背面・視聴中 120 秒 | あり（前面/背面/CommentScreen 表示中で切替） | 同 `315-330`, `1798-1826` |
| GitHub Releases 更新チェック | 起動時のみ | — | `lib/main.dart:256`, `app_update_gate` |

`FavoriteUserLiveChecker`（`lib/data/follow/favorite_user_live_checker.dart`）は既に電池配慮が実装済み: 同時リクエスト 3 本上限、10 秒キャッシュ、on-air 既知ユーザーの隔回スキップ、429 バックオフ + ジッター。

**問題点**:
1. `_fetchAllPrograms`（60 秒）はライフサイクル制御が一切なく、**アプリが背面にいる間も 1 分ごとに無線を起こし続ける**。視聴中（CommentScreen 表示中）もフォロー一覧は見えていないのに毎分取得している
2. お気に入りチェック（背面 120 秒）とフォロー取得（60 秒）の**タイマーが独立していて、無線の起床タイミングが揃わない**（起床回数が足し算になる）
3. 背面中のお気に入りチェックは、復帰時に即時再取得（`_refreshFavoritesNowAndReschedule`、同 `1833-1837`）があるため、UI 用途に限れば背面中の継続自体が不要の可能性がある

→ 提案 P3。

### 2.5 周期タイマー（CPU の細かい起床）

| タイマー | 間隔 | 稼働条件 | 根拠 |
|---|---|---|---|
| NDGR ストール検出 | **1 秒 periodic** | ストリーミング中ずっと | `lib/domain/connection/ndgr_client.dart:77, 457-469` |
| StatusBar 経過時間表示 | 1 秒 periodic | 放送中ずっと（背面でも継続） | `lib/presentation/screens/comment_screen.dart:6110` |
| 残り時間表示（配信者のみ） | 1 秒 periodic | パネル表示中 | `lib/presentation/widgets/broadcast_control_panel.dart:434` |
| 統計アクティブユーザー purge | 30 秒 periodic | コメントがある間（空になると自動停止） | `lib/application/statistics/statistics_store.dart:78, 96-98` |
| keepSeat | サーバー指定（数十秒） | 接続中 | 必須 |

**問題点**:
1. ストール検出はしきい値 15 秒に対して**毎秒**チェックしている。1 時間の視聴で約 3,600 回の起床。しかも `_markReceivedAndEnsureTimer` はコメント受信のたびに呼ばれるが、タイマー自体は張りっぱなしで、受信が途絶えない限りチェックは常に「異常なし」を空振りし続ける
2. StatusBar の 1 秒 tick は背面滞在中も動き続ける。背面ではフレームは描かれない（setState は実質無駄）が、**FGS の WakeLock 下では毎秒の isolate 起床コストが確実に発生**する。バックグラウンド読み上げは数時間に及び得るユースケースであり、積算が無視できない

→ 提案 P4 / P5。

### 2.6 コメント 1 件あたりの UI 再構築コスト（前面時の CPU/GPU 主要因）

コメント 1 件到着時のパスは次の通り:

1. `lib/main.dart:633-652` — `_timelineStore.add(message)` → `notifyListeners()`（1 回目）、続けて `_statisticsStore.recordComment(message)` → `notifyListeners()`（**2 回目**）
2. `lib/presentation/select/select_screen.dart:764-786` — `Listenable.merge` した `ListenableBuilder` が **CommentScreen ウィジェット全体を再構築**（timeline と statistics の通知で計 2 回）
3. `lib/presentation/screens/comment_screen.dart:3302-3316` — build のたびに `widget.messages.where(_shouldDisplayMessage).toList()` で**タイムライン全件**（上限 15,000 件 = `historyCount` + `timelineLiveCommentBufferSize` 5,000、`lib/domain/models/app_settings.dart:197, 255`）を NG フィルタし、降順時はさらに `reversed.toList()` でコピー（同 `4178-4184`）
4. `_shouldDisplayMessage`（同 `4441-4503`）は 1 件ごとに `_ngMatcher.shouldBlockDisplay(message.content, ...)` を呼び、`NgMatcher.match`（`lib/domain/matchers/ng_matcher.dart:213-231`）は**毎回**入力テキストを 8 段正規化（`lib/domain/normalizers/ng_word_text_normalizer.dart:33-44`: 全角折り畳み→半角カナ変換→不可視除去→類字変換→カナ→かな→小文字化→記号除去→連続圧縮）してから NG 語エントリを線形走査する
5. `TimelineStore._publishSnapshot`（`lib/application/timeline/timeline_store.dart:141-144`）はコメント 1 件ごとに O(N) のスナップショット再確保
6. 自動スクロールは 1 件ごとに 180ms の `animateTo`（`comment_screen.dart:5869-5873`）→ 高頻度ストリームでは実質常時アニメーション

**規模感**: タイムライン 15,000 件・NG 語 E 個・毎秒 10 コメントの放送では、
**正規化 15,000 回 × 2 rebuild × 10 = 毎秒 300,000 回の 8 段正規化 + 15,000 × E × 20 の substring 走査**が発生し得る。正規化は 1 回あたり文字列を 7〜8 回作り直すため、GC 圧も比例して増える。これが**前面視聴時の CPU 消費の最大の掛け算**である。

なお、緩和策の一部は既に存在する:
- 検索用の正規化には `_normalizedContentCache`（`comment_screen.dart:1165, 5078-5100`、上限つき）があるが、**NG 判定側はこのキャッシュを通らない**（`NgMatcher` 内部で毎回正規化）
- `recordReceivedAt(notify: false)`（`main.dart:636-642`）で supervisor 通知の 3 重化は既に回避済み
- 読み上げ投入は build に依存しない直接リスナー（Issue #762、`comment_screen.dart:1293, 2540-2556`）になっており、**通知をコアレッシングしても読み上げ経路は壊れない**構造が既にある

→ 提案 P1 / P2 / P7。

### 2.7 VOICEVOX 音声合成（機能上必須の CPU 消費）

- ネイティブ側（`android/.../speech/`）は event-driven ワーカー（`SpeechControllerImpl.kt:400-458`）で busy-wait なし
- キュー上限 20 + 重複テキスト拒否（`InMemorySpeechQueueManager.kt`）により、**溢れたコメントは合成前に破棄**される — 合成の無駄撃ちは構造的に発生しない
- NG 語・読み上げ対象判定は Flutter 側で投入前に済ませており、不要な合成は行われない
- `docs/voicevox-performance-guide.md` の通り、合成そのものが CPU 消費の中心

**評価**: パイプライン設計は電池観点で既に健全。合成自体は機能なので改善対象外（合成エンジンのスレッド数チューニング等は品質影響があるため本書のスコープ外とする）。

### 2.8 その他（軽微・確認事項）

- **`audioplayers` 依存が Dart コードから未参照**: `pubspec.yaml:26` に宣言があるが、`lib/` に import が 1 件もない（ネイティブ再生は AudioTrack / MediaPlayer / Android TTS で完結）。プラグインはアプリ起動時に registrant 経由で初期化されるため、消費はごく軽微だが、依存削減（サプライチェーン面でも）候補（→ P8）
- デバッグログは `kDebugMode` ゲート済み（`lib/app_logging.dart:6`）で release では消費しない
- `UserNameResolver` はキャッシュ + 200ms debounce + 同時 3 本制限（`lib/data/user/user_name_resolver.dart`）で健全
- コメントログ自動保存は接続終了トリガーのみ（`comment_screen.dart:4246-4249`）で、コメント毎のディスク書き込みはない
- 行単位の `MediaQuery` 購読回避（textScaler の prop 渡し、`comment_screen.dart:3326-3334`）など、リビルド抑制の配慮が既に随所にある

---

## 3. 改善提案（機能を落とさない省電力化）詳細設計

優先度は「期待削減量 × 実装リスクの低さ」で付与。P1/P2 が前面視聴時、P3/P4/P5 がバックグラウンド・待機時の主対策。

### P1. コメント到着通知のコアレッシング（優先度: 高）

**目的**: コメント 1 件ごとに 2 回発生する CommentScreen 全体再構築を、高頻度時に最大でも一定レートまで抑える。

**設計**:
- `TimelineStore` に leading + trailing throttle を導入する:
  - 直近 `window`（初期値 200ms）以内に通知していなければ**即時通知**（閑散時のレイテンシゼロを維持）
  - 通知済みなら trailing タイマー（1 本の one-shot）を張り、窓の終端でまとめて 1 回通知
- `StatisticsStore.recordComment` の `notifyListeners` にも同じ throttle を適用する（表示は StatusBar のカウンタのみで、200ms 遅延は知覚不能）
- テスト容易性: `window: Duration.zero` で従来の同期通知に退化させられるようにし、既存テストへの影響を局所化する。`clock`/`fake_async` は既に依存にある
- **読み上げ経路への影果**: `_onTimelineStoreChanged` は同じ notifier を購読しているため、読み上げ投入も最大 200ms 遅延する。合成時間（数百 ms〜数秒）に対して十分小さく、体感差はない。`_submitNewCommentsForSpeech` は tail カーソル方式（`comment_screen.dart:2558-2581`）なのでまとめ通知でも取りこぼさない
- **注意点**: `clear()` / `setCapacity()` は従来通り即時通知とする（画面遷移・再接続の応答性を守る）。dispose 時は pending タイマーを必ず flush ではなく cancel する（dispose 後の notify は不可）

**期待効果**: 毎秒 10 コメント時に再構築 20 回/秒 → 最大 5 回/秒（-75%）。`_publishSnapshot` の O(N) 再確保、`where().toList()`、`reversed.toList()`、auto-scroll `animateTo` の起動回数も同率で減る。

### P2. NG 表示判定のメモ化（優先度: 高）

**目的**: 再構築のたびにタイムライン全件へ 8 段正規化 + 線形走査を再実行している掛け算を消す。

**設計**:
- `_CommentScreenState` に `Map<String, bool> _displayVerdictCache`（message.id → 表示可否）を追加。`_shouldDisplayMessage` の NG 判定部分（`ngUserIds` / `shouldBlockDisplay`）の結果をキャッシュする
- **無効化条件**（いずれかが変わったら全クリア）: NgMatcher の再構築時 / `ngUserIds` 変更時 / `ngDisplayPreferences` 変更時 / gift・nicoad 等の表示トグル変更時。select_screen 側に既にある「フィルタ世代カウンタ」（`_toggleNgGeneration`、`select_screen.dart:304`）と同じ世代方式にすると didUpdateWidget での検知が単純になる
- サイズ上限は `_normalizedContentCache` と同じ ceiling + wholesale clear 方式（`comment_screen.dart:5091-5100`）を踏襲。タイムライン上限 15,000 に対し bool キャッシュは十分軽量
- 併せて `NgMatcher` に `matchNormalized(String normalizedText)` を**追加**（既存 `match` は残す・挙動不変）し、CommentScreen 側は `_normalizedContentFor(message)`（既存キャッシュ）を渡して正規化の二重実行（検索用と NG 用）を統合する。正規化関数は共有のまま（Kotlin 側との一致契約は変更しない、`ng_matcher.dart:139-145` 参照）

**期待効果**: 定常時の NG 判定は「新着分のみ」になり、再構築 1 回あたりのフィルタコストが O(全件 × 正規化) → O(全件 × Map lookup) に低下。P1 と乗算で効く。

**リスクと対策**: 無効化漏れが唯一の懸念。無効化条件を 1 箇所（世代カウンタ比較）に集約し、「NG 語追加→既存コメントが隠れる」「表示トグル切替→即反映」の回帰テストを既存 `comment_screen_test.dart` の該当 group に追加する。

### P3. SelectScreen ポーリングのライフサイクル制御と整列（優先度: 高）

**目的**: 見えていない画面のための定期的な無線起床をやめる。

**設計**:
1. `_fetchAllPrograms` の再スケジュール（`select_screen.dart:1778-1783`）に、お気に入りチェックと同じゲートを追加する:
   - `!_isInForeground` または `_isCommentScreenActive` の間は**タイマーを張らない**（停止）
   - 前面復帰・CommentScreen から戻ったタイミングで即時 fetch + 再スケジュール（お気に入り側の `_refreshFavoritesNowAndReschedule` と同じパターン。復帰フックは `didChangeAppLifecycleState`（同 `421-444`）と CommentScreen pop 後の既存処理に相乗りする）
   - これにより「一覧を開けば常に最新」という**ユーザー可視の挙動は不変**
2. お気に入りチェックの背面継続（120 秒）は、現状その結果を消費するのが SelectScreen の UI だけであることを確認の上、**背面中は停止**に変更する（復帰時即時再取得が既にあるため可視挙動は不変）。※通知など UI 以外の用途を将来足す構想があるなら現状維持 — 7 章 Open Question 2
3. 前面時のフォロー取得（60 秒）とお気に入りチェック（15 秒）は、60 秒周期の方をお気に入りチェックの 4 回に 1 回へ**相乗り**させ、無線起床の回数・タイミングを揃える（radio の高電力滞留を共有する）

**期待効果**: 背面滞在中の定期無線起床がゼロになる（現状: 60 秒毎 + 120 秒毎）。読み上げを使わず単に他アプリへ切り替えた場合の待機消費が大きく下がる。

### P4. NDGR ストール検出の one-shot 化（優先度: 中）

**目的**: 受信が続いている限り空振りし続ける毎秒タイマーをやめる。

**設計**:
- `NdgrClient` の periodic 1 秒タイマー（`ndgr_client.dart:459`）を one-shot 方式に変更する:
  - `markReceived` 時: タイマーが未armなら `threshold`（15 秒）後に発火する one-shot を張る。**armed 済みなら何もしない**（コメント毎の cancel/re-arm churn を避ける — 現行の「timer == null のときだけ start」ガード（同 `476-481`）と同じ発想）
  - 発火時: `elapsedSinceLastReceived()` を評価し、しきい値未達なら**残り時間**で再 arm、達していれば stalled を通知して停止（通知済みフラグは既存 `NdgrStallDetector.shouldNotifyStall` を流用）
- `NdgrStallDetector` 自体は純粋ロジックのまま変更しない（変更は timer 管理のみ）
- 検出遅延は最悪ケースでも現行と同じ「threshold + α」に収まる（one-shot の再 arm は残り時間ベースのため精度はむしろ向上）

**期待効果**: 起床回数がストリーミング 1 時間あたり約 3,600 回 → 受信が続く限り約 240 回（15 秒毎）以下。前面では微差だが、**FGS + WakeLock 下のバックグラウンド受信では実削減**になる。

### P5. UI 秒針タイマーのライフサイクル一時停止（優先度: 中）

**目的**: 背面滞在中（フレームが描かれない間）の毎秒起床を止める。

**設計**:
- `_StatusBarState`（`comment_screen.dart:6100-6157`）に `WidgetsBindingObserver` を追加し、`paused/hidden` で `_elapsedTimer` を cancel、`resumed` で再開する。表示値は wall clock（`formatElapsed(widget.beginAt)`、`lib/domain/utils/elapsed_formatter.dart:19-29`）から毎回導出しているため、**停止→再開でズレは発生しない**（tick は再描画トリガーに過ぎない）
- `_RemainingTimeIndicator`（`broadcast_control_panel.dart:428-446`)も同一パターンを適用
- CommentScreen 本体は既に `WidgetsBindingObserver`（auto-extend 用）を持つため、observer の増設はライフサイクル既存導線に揃える

**期待効果**: バックグラウンド読み上げ数時間のセッションで毎秒 1〜2 回の isolate 起床が消える。実装コストが小さく回帰リスクも低い。

### P6. 画面常時点灯のオプション化（優先度: 中 / 要オーナー判断）

**目的**: 「読み上げ中心で画面を見ない」ユーザーに、機能（接続・読み上げ継続）を落とさず最大の消費源（画面）を切る選択肢を与える。

**設計**:
- `AppSettings` に `keepScreenOnWhileConnected`（bool、**デフォルト true = 現行挙動**）を追加
- `_syncWakelockForStatus` / `initState` の `WakelockPlus.enable()` を設定値でゲート。false の場合は画面が OS 設定通りにスリープし、接続・読み上げは既存の FGS 経路がそのまま維持する（この経路は既にバックグラウンド読み上げとして実証済み）
- 設定 UI は既存の表示設定画面に SwitchListTile を 1 つ追加
- **CLAUDE.md の設定項目ルールに従い、Export/Import 対応が必須**: `toJson`/`fromJson` にキー追加、欠損時はデフォルト true にフォールバック（古い Export ファイルの Import で挙動が変わらないこと）。`settings_store.dart` の永続化キー追加も同時に行う
- 設定変更が接続中に行われた場合は即時反映（notifier 経由で `_syncWakelockForStatus` を再評価）

**期待効果**: 有効化したユーザーにとっては最大の削減。デフォルト挙動は完全に不変。

### P7. 降順表示の reversed コピー除去（優先度: 低）

**目的**: 再構築ごとの O(N) リストコピー（最大 15,000 要素、`comment_screen.dart:4178-4184`）を削る。

**設計**: `_applySortOrder` でコピーを作る代わりに、`itemBuilder` 内で `sortedMessages[sortedMessages.length - 1 - index]` のインデックス写像を使う（`ListView.reverse: true` はスクロール anchoring・自動スクロール判定（`_isNearTop/_isNearBottom`）に波及するため採用しない）。フィルタ済みリスト（`visibleMessages`）の生成は P1/P2 で頻度・コストが下がるため、本件は仕上げの位置づけ。

### P8. 未使用依存 `audioplayers` の削除（優先度: 低 / 要確認）

`pubspec.yaml:26` の `audioplayers: 6.8.1` は Dart コードから参照ゼロ。過去に Flutter 側再生で使っていた名残とみられる（現行再生はネイティブ AudioTrack/MediaPlayer/Android TTS）。削除すれば起動時のプラグイン初期化と APK サイズが減る（電池への直接効果は軽微、依存削減・サプライチェーン面が主目的）。**削除前に**: ビルド設定・extension 経由の利用がないこと、削除後の `flutter pub get` で `pubspec.lock` 差分をレビューすること（CLAUDE.md の依存ピン留めルール準拠）。

### P9. 【変更しない判断】FGS の起動タイミング

FGS は前面での接続開始時点から起動し WakeLock/WifiLock を保持するが、これは**意図的に現状維持とする**:
- 画面 ON 中は PARTIAL_WAKE_LOCK の追加消費は実質ゼロ（画面が CPU を起こしている）
- 「背面移行時に初めて FGS を起動する」方式は Android 12+ の background FGS start 制限とのレースを抱え、**接続維持という中核機能の信頼性を落とすリスク**が省電力の利得に見合わない

---

## 4. 期待効果まとめ

| 提案 | 効くシナリオ | 削減対象 | 概算 |
|---|---|---|---|
| P1 通知コアレッシング | 前面・高頻度放送 | 再構築回数 | 再構築 -50〜75%（10 コメ/秒時） |
| P2 NG 判定メモ化 | 前面・高頻度 × 大タイムライン | 再構築 1 回あたりの CPU | フィルタコストを O(N×正規化) → O(N×lookup) に |
| P3 ポーリング制御 | 背面滞在・視聴中 | 無線起床 | 背面の定期起床ゼロ化 |
| P4 ストール検出 one-shot | 受信中全般（特に背面） | CPU 起床 | 3,600 回/h → ≦240 回/h |
| P5 秒針タイマー停止 | 背面読み上げ | CPU 起床 | 毎秒 1〜2 回 → 0 |
| P6 常時点灯オプション | 読み上げ主体ユーザー | 画面 | オプトインで最大 |
| P7 reversed 除去 | 前面・降順表示 | アロケーション/GC | 小 |
| P8 依存削除 | 起動時 | 初期化・サイズ | 微小 |

---

## 5. 計測方法（実装 Issue の受け入れ確認用）

各改善の前後で以下を比較する。絶対値より**同一シナリオでの相対差**を見る。

- **シナリオ定義**:
  - S1: 前面視聴 30 分（コメント高頻度の放送、読み上げ ON）
  - S2: バックグラウンド読み上げ 60 分（画面 OFF）
  - S3: SelectScreen 放置 60 分（前面）→ 背面 60 分
- **測定手段**:
  - `adb shell dumpsys batterystats --reset` → シナリオ実行 → `dumpsys batterystats` / Battery Historian（wakeup 回数・radio active 時間・partial wakelock 時間）
  - Flutter DevTools Performance（S1 の frame build 回数・build 時間分布）
  - `adb shell dumpsys alarm` / Perfetto（S2 の CPU 起床頻度）
- **回帰確認**: コメント表示遅延（P1 の窓 200ms が体感に出ないこと）、ストール検出遅延（P4 で 15 秒 + α を超えないこと）、復帰時の一覧鮮度（P3 で復帰即時 fetch が走ること）

---

## 6. Issue 分解案

依存順に並べる。1 Issue = 1 PR を想定。

### Issue 1: TimelineStore / StatisticsStore の通知コアレッシング（P1）
- **goal**: コメント到着時の notifyListeners を leading+trailing throttle 化（窓 200ms、`Duration.zero` で従来挙動）
- **scope**: `timeline_store.dart`, `statistics_store.dart`, 既存テストの追随
- **non-scope**: CommentScreen 側の変更、NG 判定キャッシュ
- **AC**: 窓内の連続 add が 1 通知に集約される / 閑散時（窓経過後の単発 add）は即時通知 / `clear`・`setCapacity` は即時通知 / dispose 後に通知されない / 読み上げ投入の取りこぼしなし（tail カーソルのユニットテスト）
- **test**: `test/application/timeline/timeline_store_test.dart` と statistics_store の既存テストファイルに `fake_async` ベースの group を追加

### Issue 2: NG 表示判定のメモ化と正規化の一本化（P2）
- **goal**: `_displayVerdictCache` 導入 + `NgMatcher.matchNormalized` 追加
- **依存**: Issue 1 と独立（並行可）
- **non-scope**: Kotlin 側正規化の変更（一切しない）、NG 判定の結果仕様変更
- **AC**: NG 語・表示設定変更で既存コメントの表示可否が即時再評価される / 判定結果が変更前後で完全一致（既存テストが全て通る）/ キャッシュ上限到達時に wholesale clear
- **test**: 既存 `comment_screen_test.dart` の NG フィルタ group に追加（新規テストファイルは作らない）

### Issue 3: SelectScreen ポーリングのライフサイクル制御（P3）
- **goal**: `_fetchAllPrograms` の背面/視聴中停止 + 復帰時即時 fetch、お気に入り背面停止、前面時の周期整列
- **AC**: 背面移行後にネットワーク呼び出しが発生しない（fake timer で検証）/ 前面復帰で即時 fetch / CommentScreen から戻った際に一覧が更新される
- **open question 2 の回答が「背面継続が必要」の場合**: お気に入り側は現状維持し、フォロー取得のみ制御する

### Issue 4: NDGR ストール検出の one-shot 化（P4）
- **goal**: periodic 1s → one-shot 残時間再 arm 方式
- **AC**: 受信継続中はタイマー発火が threshold 間隔以下 / 受信停止から threshold ± 検出許容内で stalled が 1 回だけ発火 / stop/dispose でタイマーが残らない
- **test**: 既存 `ndgr_client` / `ndgr_stall_detector` のテストファイルに group 追加（`fake_async`）

### Issue 5: 秒針タイマーのライフサイクル停止（P5）
- **goal**: `_StatusBar` / `_RemainingTimeIndicator` の背面 pause / 前面 resume
- **AC**: paused 遷移でタイマー停止、resumed で表示が正しい経過時間に即時復帰（ズレなし）
- **test**: 既存 `comment_screen_test.dart` / broadcast_control_panel のテストに group 追加

### Issue 6: 画面常時点灯のオプション化（P6）※オーナー判断後
- **goal**: `keepScreenOnWhileConnected` 設定（デフォルト true）
- **scope**: AppSettings + settings_store + Export/Import + 設定 UI + wakelock ゲート
- **AC**: デフォルトで従来と完全同一挙動 / false で wakelock を一切取得しない / 接続中の設定変更が即時反映 / **旧 Export ファイルの Import で true にフォールバック** / Export に新キーが含まれ round-trip する
- **test**: settings round-trip テスト（既存の settings 系テストファイルに追加）+ `FakeWakelockPlusPlatform` による取得回数検証

### Issue 7: 仕上げ（P7 + P8）
- reversed コピー除去、`audioplayers` 削除（利用皆無の確認と `pubspec.lock` 差分レビューを AC に含める）

---

## 7. Open Questions（オーナー確認事項）

1. **P1 のコアレッシング窓 200ms は許容か？** 新着コメントの表示・読み上げ開始が最大 200ms 遅れる（体感差はほぼない想定）。もっと保守的にするなら 100ms でも効果は十分ある
2. **お気に入りユーザーの放送チェックを背面中も続ける必要はあるか？** 現状は結果を SelectScreen の UI でしか使っていない。将来「お気に入りが放送開始したら通知」等を予定しているなら P3 のお気に入り側は現状維持にする
3. **ストール検出の遅延許容**: one-shot 化で検出タイミングは「最終受信から 15〜16 秒程度」になる（現行は 15〜16 秒 + 最大 1 秒）。実質同等だが、仕様として明文化してよいか
4. **P6（常時点灯オプション）を設定項目として追加する方針か？** 設定が 1 つ増える UX コストとのトレードオフ。追加する場合、初期リリースでは「詳細設定」の階層に置くことを推奨
5. **`audioplayers` を残している意図はあるか？**（将来の Flutter 側再生の構想など）意図がなければ削除候補

---

## 8. まとめ

- 支配的な消費（画面点灯・ストリーミング・音声合成）は機能そのものであり、パイプライン設計（キュー上限・重複排除・event-driven ワーカー・接続再利用・バックオフ）は既に電池観点で健全
- 削減余地は「同じ仕事のやり直し」と「見えていない間の稼働」に集中している:
  1. **コメント 1 件 → 2 回の全画面再構築 → タイムライン全件の NG 再判定**という掛け算（P1 + P2）
  2. **背面でも止まらないポーリングと秒針タイマー**（P3 + P4 + P5）
- いずれもユーザー可視の挙動を変えずに実装可能で、P6 のみ新設定（デフォルト現行維持）としてオーナー判断を仰ぐ
