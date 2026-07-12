# バッテリー消費分析と省電力化 詳細設計書

- 対象: comerune v1.2.0 時点の `main` 相当コード
- 目的: 現行実装のうちバッテリー消費が大きくなりそうな箇所を特定し、**機能を落とさずに**省電力化できる改善を設計としてまとめる
- 位置づけ: 実装前の分析・設計ドキュメント。個別の改善は本書の Issue 分解案に沿って別 Issue / 別 PR で行う
- 改訂: rev.2 — オーナー回答（コアレッシング窓 200ms 承認 / お気に入り背面チェックは継続 / P6 は見送り / audioplayers 削除可）を反映し、実装用コード例を追加

---

## 1. 分析の前提: このアプリの電力消費モデル

comerune は「ニコ生コメントの取得・表示・読み上げ」アプリであり、消費電力は大きく次の 4 層に分けられる。

| 層 | 内容 | 支配度 | 削減余地 |
|---|---|---|---|
| ① 画面点灯 | wakelock による常時点灯 | 最大（スマホ全体の消費の過半になり得る） | 機能そのものなので既定では削れない |
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

**評価**: 「視聴中に画面を消さない」はコメントビューアの中核機能であり、既定動作としては妥当。読み上げ主体ユーザー向けのオプション化（P6）はオーナー判断により**見送り（バックログ）**。

### 2.2 Foreground Service + WakeLock + WifiLock

- `lib/data/foreground_service/foreground_service_manager.dart:76-77` — `allowWakeLock: true` / `allowWifiLock: true`。FGS 稼働中は PARTIAL_WAKE_LOCK と WifiLock を保持
- `lib/application/foreground_service/foreground_service_controller.dart:96-112` — 接続開始（`connectingSessionWs`）の時点で、アプリが前面か背面かに関わらず FGS を起動
- 同 `27, 149` — 放送終了後は 30 秒の猶予（読み上げキュー完了で早期終了、`notifyQueueDrained`）

**評価**: 画面 OFF でのバックグラウンド受信・読み上げを成立させるために WakeLock/WifiLock は必須。画面 ON 中は PARTIAL_WAKE_LOCK は実質無害（画面点灯自体が CPU を起こしている）なので、FGS の起動タイミングは現状維持が妥当（→ P9 で「変更しない判断」として記録）。**ただしバックグラウンド滞在中は WakeLock 下で Dart timer が確実に CPU を起こすため、④の周期タイマー削減の価値が上がる**。

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
2. お気に入りチェック（120 秒）とフォロー取得（60 秒）のタイマーが独立していて、無線の起床タイミングが揃わない

**オーナー回答の反映**: お気に入りユーザーの背面チェック（120 秒）は**現状維持とする**（背面でも必要、との回答）。P3 の対象は `_fetchAllPrograms` のみ。

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
1. ストール検出はしきい値 15 秒に対して**毎秒**チェックしている。1 時間の視聴で約 3,600 回の起床。しかも受信が途絶えない限りチェックは常に「異常なし」を空振りし続ける
2. StatusBar の 1 秒 tick は背面滞在中も動き続ける。背面ではフレームは描かれない（setState は実質無駄）が、**FGS の WakeLock 下では毎秒の isolate 起床コストが確実に発生**する。バックグラウンド読み上げは数時間に及び得る

→ 提案 P4 / P5。

### 2.6 コメント 1 件あたりの UI 再構築コスト（前面時の CPU/GPU 主要因）

コメント 1 件到着時のパスは次の通り:

1. `lib/main.dart:633-652` — `_timelineStore.add(message)` → `notifyListeners()`（1 回目）、続けて `_statisticsStore.recordComment(message)` → `notifyListeners()`（**2 回目**）
2. `lib/presentation/select/select_screen.dart:764-786` — `Listenable.merge` した `ListenableBuilder` が **CommentScreen ウィジェット全体を再構築**（timeline と statistics の通知で計 2 回）
3. `lib/presentation/screens/comment_screen.dart:3302-3316` — build のたびに `widget.messages.where(_shouldDisplayMessage).toList()` で**タイムライン全件**（上限 15,000 件 = `historyCount` + `timelineLiveCommentBufferSize` 5,000、`lib/domain/models/app_settings.dart:197, 255`）を NG フィルタし、降順時はさらに `reversed.toList()` でコピー（同 `4178-4184`）
4. `_shouldDisplayMessage`（同 `4441-4503`）は 1 件ごとに `_ngMatcher.shouldBlockDisplay(message.content, ...)` を呼び、`NgMatcher.match`（`lib/domain/matchers/ng_matcher.dart:213-231`）は**毎回**入力テキストを 8 段正規化（`lib/domain/normalizers/ng_word_text_normalizer.dart:33-44`）してから NG 語エントリを線形走査する
5. `TimelineStore._publishSnapshot`（`lib/application/timeline/timeline_store.dart:141-144`）はコメント 1 件ごとに O(N) のスナップショット再確保
6. 自動スクロールは 1 件ごとに 180ms の `animateTo`（`comment_screen.dart:5869-5873`）→ 高頻度ストリームでは実質常時アニメーション

**規模感**: タイムライン 15,000 件・NG 語 E 個・毎秒 10 コメントの放送では、
**正規化 15,000 回 × 2 rebuild × 10 = 毎秒 300,000 回の 8 段正規化 + 15,000 × E × 20 の substring 走査**が発生し得る。正規化は 1 回あたり文字列を 7〜8 回作り直すため、GC 圧も比例して増える。これが**前面視聴時の CPU 消費の最大の掛け算**である。

なお、緩和策の一部は既に存在する:
- 検索用の正規化には `_normalizedContentCache`（`comment_screen.dart:1165, 5095-5102`、上限つき・wholesale clear）がある。ただしこれは `normalizeForSearch` の結果であり、**NG 判定（`normalizeNgWordText`）とは別の正規化**のため NG 側では使えない
- `recordReceivedAt(notify: false)`（`main.dart:636-642`）で supervisor 通知の 3 重化は既に回避済み
- 読み上げ投入は build に依存しない直接リスナー（Issue #762、`comment_screen.dart:1293, 2540-2556`）になっており、**通知をコアレッシングしても読み上げ経路は壊れない**構造が既にある

→ 提案 P1 / P2 / P7。

### 2.7 VOICEVOX 音声合成（機能上必須の CPU 消費）

- ネイティブ側（`android/.../speech/`）は event-driven ワーカー（`SpeechControllerImpl.kt:400-458`）で busy-wait なし
- キュー上限 20 + 重複テキスト拒否（`InMemorySpeechQueueManager.kt`）により、**溢れたコメントは合成前に破棄**される — 合成の無駄撃ちは構造的に発生しない
- NG 語・読み上げ対象判定は Flutter 側で投入前に済ませており、不要な合成は行われない
- `docs/voicevox-performance-guide.md` の通り、合成そのものが CPU 消費の中心

**評価**: パイプライン設計は電池観点で既に健全。合成自体は機能なので改善対象外。

### 2.8 その他（軽微）

- **`audioplayers` 依存が Dart コードから未参照**: `pubspec.yaml:26` に宣言があるが、`lib/` に import が 1 件もない。読み上げの再生はネイティブ側（`AudioTrackWavPlayer` / `MediaPlayerWavPlayer` / Android TTS）で完結しており、Flutter 側の音声再生は存在しない。**オーナー確認済み: 残す意図なし → 削除する**（→ P8）
- デバッグログは `kDebugMode` ゲート済み（`lib/app_logging.dart:6`）で release では消費しない
- `UserNameResolver` はキャッシュ + 200ms debounce + 同時 3 本制限（`lib/data/user/user_name_resolver.dart`）で健全
- コメントログ自動保存は接続終了トリガーのみ（`comment_screen.dart:4246-4249`）で、コメント毎のディスク書き込みはない
- 行単位の `MediaQuery` 購読回避（textScaler の prop 渡し、`comment_screen.dart:3326-3334`）など、リビルド抑制の配慮が既に随所にある

---

## 3. 改善提案（機能を落とさない省電力化）詳細設計

優先度は「期待削減量 × 実装リスクの低さ」で付与。P1/P2 が前面視聴時、P3/P4/P5 がバックグラウンド・待機時の主対策。**各提案に実装コード例を付す。コード例は設計意図を示すリファレンスであり、実装時は周辺コードの実態（フィールド名・既存テスト）に合わせて調整すること。**

### P1. コメント到着通知のコアレッシング（優先度: 高）【窓 200ms 承認済み】

**目的**: コメント 1 件ごとに 2 回発生する CommentScreen 全体再構築を、高頻度時に最大でも一定レートまで抑える。

**設計**:
- leading + trailing throttle を共通 mixin として実装し、`TimelineStore` と `StatisticsStore` の両方に適用する
  - 直近 `notifyWindow`（200ms）以内に通知していなければ**即時通知**（閑散時のレイテンシゼロを維持）
  - 通知済みなら trailing タイマー（one-shot 1 本）を張り、窓の終端でまとめて 1 回通知
- `TimelineStore` の O(N) スナップショット公開（`_publishSnapshot`）は**通知 1 回につき 1 回**に移す。「スナップショットは notifyListeners と同時にのみ更新される」という既存の公開契約（`timeline_store.dart:39-48` の doc comment）はそのまま保たれる
- `clear()` / `setCapacity()` は従来通り**即時通知**（画面遷移・再接続の応答性を守る）
- 接続終了時の自動ログ保存が最後の 200ms 分を取りこぼさないよう、`flushPending()` を公開し、CommentScreen の終了ステータス遷移時に呼ぶ
- 読み上げ経路（`_onTimelineStoreChanged` → tail カーソル方式の `_submitNewCommentsForSpeech`、`comment_screen.dart:2558-2581`）はまとめ通知でも取りこぼさない。読み上げ開始の遅延は最大 200ms（合成時間に対して無視できる）

**コード例 1: 共通 mixin（新規ファイル `lib/application/notify/coalescing_notifier.dart`）**

```dart
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';

/// 高頻度な状態変化の [notifyListeners] を leading + trailing throttle で
/// まとめる mixin。
///
/// - 直近 [notifyWindow] 以内に通知していなければ即時通知（閑散時は
///   レイテンシゼロ）
/// - 窓内の連続変更は one-shot タイマー 1 本にまとめ、窓の終端で 1 回通知
/// - [notifyWindow] が [Duration.zero] のときは従来の同期通知と完全に等価
///   （既存テスト・既存呼び出し元の挙動を変えないための既定値）
///
/// 時刻は package:clock の [clock] 経由で取得するため、テストでは
/// fake_async の zone 内で決定的に制御できる。
mixin CoalescingNotifier on ChangeNotifier {
  /// 通知間隔の下限。[Duration.zero] でコアレッシング無効（従来挙動）。
  @protected
  Duration get notifyWindow;

  Timer? _trailingTimer;
  DateTime? _lastNotifiedAt;

  /// 通知が実際に発火する直前に 1 回だけ呼ばれるフック。
  /// スナップショット公開など「通知 1 回につき 1 回で済む O(N) 処理」を
  /// ここに移すこと。
  @protected
  void onBeforeNotify() {}

  /// 変更を通知する。窓が空いていれば即時、窓内なら trailing にまとめる。
  @protected
  void notifyCoalesced() {
    if (notifyWindow == Duration.zero) {
      flushPending();
      return;
    }
    final DateTime now = clock.now();
    final DateTime? last = _lastNotifiedAt;
    if (last == null || now.difference(last) >= notifyWindow) {
      flushPending();
      return;
    }
    // 窓内 2 件目以降: 既に trailing が予約済みなら何もしない。
    _trailingTimer ??= Timer(notifyWindow - now.difference(last), () {
      _trailingTimer = null;
      flushPending();
    });
  }

  /// 保留中の trailing を破棄して即時に 1 回通知する。
  /// clear() や接続終了処理など、最新状態の即時反映が必要な箇所から呼ぶ。
  void flushPending() {
    _trailingTimer?.cancel();
    _trailingTimer = null;
    _lastNotifiedAt = clock.now();
    onBeforeNotify();
    notifyListeners();
  }

  @override
  void dispose() {
    // dispose 後に trailing が発火して disposed notifier に触れないよう
    // ここで必ず破棄する。
    _trailingTimer?.cancel();
    _trailingTimer = null;
    super.dispose();
  }
}
```

**コード例 2: `TimelineStore` への適用（`lib/application/timeline/timeline_store.dart` の差分イメージ）**

```dart
class TimelineStore extends ChangeNotifier with CoalescingNotifier {
  TimelineStore({
    int capacity = 100,
    // 既定 Duration.zero = 従来挙動。コアレッシングは合成ルート
    // （main.dart）だけが明示的に opt-in する。
    Duration notifyWindow = Duration.zero,
  }) : _capacity = _validateCapacity(capacity),
       _notifyWindow = notifyWindow;

  final Duration _notifyWindow;

  @override
  Duration get notifyWindow => _notifyWindow;

  /// 直近の通知以降に [_messages] へ未公開の変更があるか。
  /// onBeforeNotify で 1 回だけスナップショットを再公開するためのフラグ。
  bool _dirty = false;

  @override
  void onBeforeNotify() {
    if (_dirty) {
      _publishSnapshot(); // 既存メソッドをそのまま利用
      _dirty = false;
    }
  }

  void add(AppMessage message) {
    if (_knownIds.contains(message.id)) {
      return;
    }
    _insertSorted(message);
    _knownIds.add(message.id);
    _trimOverflow();
    _dirty = true;
    notifyCoalesced(); // 従来の _publishAndNotify() を置き換え
  }

  // addAll() も同様: changed のとき _dirty = true; notifyCoalesced();

  void clear() {
    if (_messages.isEmpty) {
      return;
    }
    _messages.clear();
    _knownIds.clear();
    _dirty = true;
    flushPending(); // 画面遷移・再接続の応答性を守るため即時
  }

  void setCapacity(int value) {
    final int next = _validateCapacity(value);
    if (_capacity == next) {
      return;
    }
    final int previousLength = _messages.length;
    _capacity = next;
    _trimOverflow();
    if (_messages.length != previousLength) {
      // 実際に間引かれたときだけスナップショットを更新する
      // （既存の identity 安定性コメント参照）。
      _dirty = true;
    }
    flushPending(); // 容量変更は常に即時通知（従来仕様の維持）
  }
}
```

**コード例 3: 合成ルートの opt-in（`lib/main.dart:553` 付近）**

```dart
    _timelineStore = TimelineStore(
      capacity: widget.initialSettings.pastCommentFetchCount.displayCapacity,
      // コメント到着通知を 200ms 窓でコアレッシングする（省電力）。
      // 閑散時は leading edge で即時通知されるため体感遅延はない。
      notifyWindow: const Duration(milliseconds: 200),
    );
    _statisticsStore = StatisticsStore(
      notifyWindow: const Duration(milliseconds: 200),
    );
```

**コード例 4: `StatisticsStore` への適用（`recordComment` のみ変更、他の通知は即時のまま）**

```dart
class StatisticsStore extends ChangeNotifier with CoalescingNotifier {
  StatisticsStore({
    Duration activeWindow = const Duration(minutes: 5),
    Duration purgeInterval = const Duration(seconds: 30),
    Duration notifyWindow = Duration.zero,
    DateTime Function()? now,
  }) : ...,
       _notifyWindow = notifyWindow;

  final Duration _notifyWindow;

  @override
  Duration get notifyWindow => _notifyWindow;

  void recordComment(AppMessage message) {
    _totalCommentCount += 1;
    // ...既存のアクティビティ記録処理...
    notifyCoalesced(); // ← notifyListeners() から変更（高頻度パスのみ）
  }

  // updateViewerCount / reset / _onPurgeTick の notifyListeners は
  // 低頻度なので従来通り即時のままとする。
  // 既存の dispose() は super.dispose() を必ず呼んでいるため、mixin の
  // trailing タイマー破棄はそのまま連鎖する。
}
```

**コード例 5: 終了時の取りこぼし防止（`comment_screen.dart` `_handleConnectionChanged` 冒頭）**

```dart
  void _handleConnectionChanged() {
    final ConnectionStatus currentStatus = widget.connectionSupervisor.status;
    // 終了系ステータスでは、コアレッシング窓内に溜まっている最後の
    // コメントを即時公開してから自動保存・統計処理に進む。
    if (currentStatus == ConnectionStatus.ended ||
        currentStatus == ConnectionStatus.stopped ||
        currentStatus == ConnectionStatus.failed) {
      widget.speechConfig.timelineStore?.flushPending();
    }
    // ...以降は既存処理...
```

**テスト設計**（既存 `test/application/timeline/timeline_store_test.dart` 等に group 追加、`fake_async` 使用）:
- 窓内に 3 件 add → 通知は leading 1 回 + trailing 1 回の計 2 回、スナップショットは通知時点の内容
- 窓経過後の単発 add → 即時通知（レイテンシゼロ）
- `clear` / `setCapacity` → trailing 予約があっても即時通知 1 回に集約
- dispose 後に trailing が発火しない
- `notifyWindow: Duration.zero` で従来テストが無修正で通ること

**期待効果**: 毎秒 10 コメント時に再構築 20 回/秒 → 最大 5 回/秒（-75%）。`_publishSnapshot` の O(N) 再確保、`where().toList()`、auto-scroll `animateTo` の起動回数も同率で減る。

### P2. NG 表示判定のメモ化（優先度: 高）

**目的**: 再構築のたびにタイムライン全件へ 8 段正規化 + 線形走査を再実行している掛け算を消す。

**設計**（rev.2 で単純化）:
- 当初案の「`NgMatcher` に正規化済み入力 API を追加」は**採用しない**。検索用キャッシュ（`normalizeForSearch`）と NG 用正規化（`normalizeNgWordText`）は別関数であり共用できないため
- 代わりに **CommentScreen 側で「NG 語判定の結果 bool」を message.id キーでメモ化**する。`NgMatcher` は一切変更しない
- キャッシュ対象は `_ngMatcher.shouldBlockDisplay(...)` の呼び出し**だけ**。型トグル（gift/nicoad/operator 等）や `ngUserIds` の Set lookup は O(1) なのでキャッシュしない（トグル変更時の無効化を考えなくて済む）
- **無効化は 2 点に集約**: ① `_rebuildNgMatcher()` 内（NG 語リスト変更の全経路 — `comment_screen.dart:1226, 1406, 1416, 1429, 1432, 5155` — はすべてここを通る）、② `didUpdateWidget` で `ngDisplayPreferences` が変わったとき（prefs は matcher に焼き込まれず判定時引数のため、matcher 再構築を通らない）
- サイズ上限 + wholesale clear は既存 `_normalizedContentCache`（`comment_screen.dart:5095-5102`）と同じ方式

**コード例（`comment_screen.dart` の差分イメージ）**

```dart
  /// NG 語判定（8 段正規化 + エントリ線形走査）の結果メモ。
  /// key は message.id（content は id に対して不変）。
  /// フィルタ条件が変わったら [_invalidateNgVerdictCache] で全クリアする。
  final Map<String, bool> _ngVerdictCache = <String, bool>{};

  /// タイムライン上限 15,000 + 余裕。溢れたら wholesale clear
  /// （_normalizedContentCache と同じ方針: 真の LRU より単純で、
  /// 全再計算になっても非キャッシュ時と同コストで済む）。
  static const int _kNgVerdictCacheCeiling = 20000;

  void _invalidateNgVerdictCache() {
    _ngVerdictCache.clear();
  }

  /// message.content が表示軸 NG 語に該当するか（メモ化つき）。
  bool _isBlockedByNgWord(AppMessage message) {
    final bool? cached = _ngVerdictCache[message.id];
    if (cached != null) {
      return cached;
    }
    final bool blocked = _ngMatcher.shouldBlockDisplay(
      message.content,
      widget.contentFilter.ngDisplayPreferences,
    );
    if (_ngVerdictCache.length >= _kNgVerdictCacheCeiling) {
      _ngVerdictCache.clear();
    }
    _ngVerdictCache[message.id] = blocked;
    return blocked;
  }
```

`_shouldDisplayMessage`（`comment_screen.dart:4495-4500`）の該当部分を差し替え:

```dart
    // 変更前:
    // if (_ngMatcher.shouldBlockDisplay(
    //   message.content,
    //   widget.contentFilter.ngDisplayPreferences,
    // )) {
    //   return false;
    // }

    // 変更後:
    if (_isBlockedByNgWord(message)) {
      return false;
    }
```

無効化ポイント①（`_rebuildNgMatcher`、`comment_screen.dart:5176`）:

```dart
  void _rebuildNgMatcher() {
    // ...既存の matcher 再構築処理...
    _ngMatcher = NgMatcher(
      presetCategories: categories,
      userNgWords: widget.contentFilter.ngWords,
      normalizer: normalizeNgWordText,
    );
    // matcher が変わったら過去の判定結果はすべて無効。
    _invalidateNgVerdictCache();
  }
```

無効化ポイント②（`didUpdateWidget` 内に追加）:

```dart
    // ngDisplayPreferences は matcher に焼き込まれず判定時の引数なので、
    // matcher 再構築（＝無効化ポイント①）を通らない。ここで明示的に
    // キャッシュを落とす。
    if (oldWidget.contentFilter.ngDisplayPreferences !=
        widget.contentFilter.ngDisplayPreferences) {
      _invalidateNgVerdictCache();
    }
```

dispose での解放（既存の `_normalizedContentCache.clear()` の隣、`comment_screen.dart:1658` 付近）:

```dart
    _normalizedContentCache.clear();
    _ngVerdictCache.clear();
```

**テスト設計**（既存 `comment_screen_test.dart` の NG フィルタ group に追加）:
- NG 語追加 → 既に表示中のコメントが即座に隠れる（無効化①の回帰）
- 表示サブカテゴリトグル変更 → 即時反映（無効化②の回帰）
- 同一メッセージリストで 2 回 build しても表示結果が同一（メモ化の正しさ）
- `ngDisplayPreferences` の等値比較が成立していること（値が同一のインスタンス再生成で無駄クリアされるのは許容だが、変更が検知されないのは不可 — `NgDisplayPreferences` に `==`/`hashCode` が無ければ実装時に追加する）

**期待効果**: 定常時の NG 判定は「新着分のみ」になり、再構築 1 回あたりのフィルタコストが O(全件 × 正規化) → O(全件 × Map lookup) に低下。P1 と乗算で効く。

### P3. フォロー中番組ポーリングのライフサイクル制御（優先度: 高）【お気に入り側は現状維持】

**目的**: 見えていない画面のための定期的な無線起床をやめる。

**設計**:
- 対象は `_fetchAllPrograms`（60 秒）**のみ**。お気に入りチェックはオーナー回答により背面 120 秒継続を維持する
- お気に入り側と同じゲート方式に揃える: 一覧が見えていない間（背面 or CommentScreen 表示中）はタイマーを張らず、見える状態に戻る既存導線（前面復帰 / CommentScreen から pop）で即時 fetch + 再開する。**pop 復帰時の即時 fetch は既に存在する**（`select_screen.dart:653`）ため、追加するのは「resumed 時の再開」と「ゲート」だけ

**コード例（`select_screen.dart` の差分イメージ）**

```dart
  /// フォロー一覧が実際に見えているときだけ次回の取得を予約する。
  /// 見えていない間はタイマーを張らない — 復帰導線（didChangeAppLifecycleState
  /// の resumed 分岐、CommentScreen pop 後の _fetchAllPrograms 呼び出し）が
  /// サイクルを再開する。
  void _scheduleFollowRefresh() {
    _followRefreshTimer?.cancel();
    if (!_isInForeground || _isCommentScreenActive) {
      return;
    }
    _followRefreshTimer = Timer(
      _followRefreshInterval,
      () => unawaited(_fetchAllPrograms()),
    );
  }
```

`_fetchAllPrograms` 末尾（`select_screen.dart:1778-1783`）の置き換え:

```dart
    // 変更前:
    // _followRefreshTimer?.cancel();
    // _followRefreshTimer = Timer(
    //   _followRefreshInterval,
    //   () => unawaited(_fetchAllPrograms()),
    // );

    // 変更後:
    _scheduleFollowRefresh();
```

`didChangeAppLifecycleState`（`select_screen.dart:421-444`）への追記:

```dart
    if (!wasForeground && _isInForeground) {
      if (_isCommentScreenActive) {
        _scheduleFavoriteRefresh();
      } else {
        _refreshFavoritesNowAndReschedule();
        // 前面復帰: 停止していたフォロー取得サイクルを即時 fetch から再開。
        unawaited(_fetchAllPrograms());
      }
    } else if (wasForeground && !_isInForeground) {
      _scheduleFavoriteRefresh();
      // 背面移行: armed 済みのフォロー取得タイマーを即座に止める
      // （_scheduleFollowRefresh のゲートは「次回予約」にしか効かないため）。
      _followRefreshTimer?.cancel();
      _followRefreshTimer = null;
    }
```

CommentScreen 遷移時（`select_screen.dart:639` 付近）への追記:

```dart
    _isCommentScreenActive = true;
    _scheduleFavoriteRefresh();
    // 視聴中はフォロー一覧が見えないため取得を止める。
    // pop 復帰時は既存の finally 後の _fetchAllPrograms()（同 653 行）が
    // 即時 fetch + サイクル再開を担う。
    _followRefreshTimer?.cancel();
    _followRefreshTimer = null;
```

**テスト設計**（select_screen の既存テストファイルに group 追加、`fake_async`）:
- 背面移行後、60 秒経過してもフォロー取得のネットワーク呼び出しが発生しない
- 前面復帰で即時 fetch が 1 回発生し、その後 60 秒周期が再開する
- CommentScreen push 中は取得が止まり、pop 後に即時 fetch（既存挙動）+ 周期再開

**期待効果**: 背面滞在・視聴中の 60 秒毎の無線起床がゼロになる（お気に入りの 120 秒は仕様として残る）。

### P4. NDGR ストール検出の one-shot 化（優先度: 中）

**目的**: 受信が続いている限り空振りし続ける毎秒タイマーをやめる。

**設計**:
- periodic 1 秒タイマー（`ndgr_client.dart:459`）を one-shot 方式に変更
- **コメント毎の cancel/re-arm churn を避ける**: `markReceived` 時はタイマーが未 arm のときだけ threshold 分の one-shot を張る（現行の「timer == null のときだけ start」ガード（同 `476-481`）と同じ発想）。発火時に実際の経過時間を見て、しきい値未達なら**残り時間**で再 arm する
- `NdgrStallDetector`（純粋ロジック）は変更しない。stalled 通知後は markReceived が来るまで再 arm しない（現行の `_stallNotified` フラグと同じ抑止が、タイマー自体の停止として表現される）
- 検出遅延は「最終受信から threshold + ごく僅かな再 arm 誤差」となり、現行（threshold + 最大 1 秒のポーリング誤差）と実質同等かむしろ正確になる

**コード例（`ndgr_client.dart` の差分イメージ）**

```dart
  // 変更前の _startStallTimer / _stopStallTimer / _markReceivedAndEnsureTimer
  // を以下に置き換える。_stallCheckInterval フィールドは再 arm の下限
  // （負値ガード）として残す。

  /// [delay] 後に 1 回だけストール判定を行う one-shot を張る。
  void _armStallTimer(Duration delay) {
    _stallTimer?.cancel();
    _stallTimer = Timer(delay, _onStallTimerFired);
  }

  void _onStallTimerFired() {
    _stallTimer = null;
    if (_isStopped || !_isRunning) {
      return;
    }
    final Duration? elapsed = _stallDetector.elapsedSinceLastReceived();
    if (elapsed == null) {
      // 受信前に発火することは通常ないが、防御的に threshold で再 arm。
      _armStallTimer(_stallDetector.threshold);
      return;
    }
    if (_stallDetector.shouldNotifyStall()) {
      _eventsController.add(NdgrClientEvent.stalled(elapsed));
      // 通知済み: 次の markReceived まで再 arm しない
      // （periodic 時代の _stallNotified による空振り抑止と等価）。
      return;
    }
    // しきい値未達（発火までの間に受信があった）: 残り時間で再 arm。
    final Duration remaining = _stallDetector.threshold - elapsed;
    _armStallTimer(
      remaining > Duration.zero ? remaining : _stallCheckInterval,
    );
  }

  void _stopStallTimer() {
    _stallTimer?.cancel();
    _stallTimer = null;
  }

  void _markReceivedAndEnsureTimer(DateTime timestamp) {
    _stallDetector.markReceived(timestamp);
    // 受信のたびに cancel/re-arm しない: 既に armed なら発火時に
    // 残り時間で再 arm される。未 arm（初回 or stalled 通知後）のとき
    // だけ threshold 分を張る。
    _stallTimer ??= Timer(_stallDetector.threshold, _onStallTimerFired);
  }
```

`NdgrStallDetector` に threshold の公開が必要（既に `final Duration threshold;` として public — 変更不要）。

**テスト設計**（既存 `ndgr_client` テストの stall group に追加、`fake_async`）:
- 受信が threshold/2 間隔で続く間、タイマー発火回数が「threshold あたり 1 回」以下
- 受信停止から threshold 経過で stalled が**ちょうど 1 回**発火
- stalled 後の受信再開 → タイマー再 arm → 再度停止で 2 回目の stalled
- `stop()` / `dispose()` でタイマーが残らない

**期待効果**: 起床回数がストリーミング 1 時間あたり約 3,600 回 → 受信が続く限り約 240 回（15 秒毎）以下。FGS + WakeLock 下のバックグラウンド受信で実削減。

### P5. UI 秒針タイマーのライフサイクル一時停止（優先度: 中）

**目的**: 背面滞在中（フレームが描かれない間）の毎秒起床を止める。

**設計**:
- `_StatusBarState`（`comment_screen.dart:6100-6157`）と `_RemainingTimeIndicatorState`（`broadcast_control_panel.dart:428-446`）に `WidgetsBindingObserver` を追加
- `paused` / `hidden` / `detached` でタイマーを cancel、`resumed` で再開（`inactive` は通知シェード等の一時的な状態なので止めない）
- 表示値は wall clock から毎回導出している（`formatElapsed(widget.beginAt)`、`lib/domain/utils/elapsed_formatter.dart:19-29`）ため、**停止→再開でズレは発生しない**。tick は再描画トリガーに過ぎない

**コード例（`_StatusBarState` の差分イメージ。`_RemainingTimeIndicatorState` も同一パターン）**

```dart
class _StatusBarState extends State<_StatusBar> with WidgetsBindingObserver {
  bool _collapsed = false;
  Timer? _autoCollapseTimer;
  Timer? _elapsedTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // ...既存の autoCollapse / elapsed timer 初期化...
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_shouldTickElapsed && _elapsedTimer == null) {
          // 経過時間は wall clock から導出されるため、setState 1 回で
          // 正しい値に追いつく（停止していた間のズレは発生しない）。
          setState(() {});
          _startElapsedTimer();
        }
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // 背面ではフレームが描かれず tick は無駄な isolate 起床にしか
        // ならない（FGS の WakeLock 下では毎秒確実に CPU を起こす）。
        _elapsedTimer?.cancel();
        _elapsedTimer = null;
      case AppLifecycleState.inactive:
        break; // 通知シェード等の一時状態では止めない
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoCollapseTimer?.cancel();
    _elapsedTimer?.cancel();
    super.dispose();
  }

  // 既存の didUpdateWidget / _startElapsedTimer は変更なし。
}
```

**テスト設計**（既存 `comment_screen_test.dart` の StatusBar group に追加）:
- `tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused)` 後に pump しても経過表示が更新されない
- `resumed` 復帰後、次の pump で正しい経過時間に追いつき、以後 1 秒 tick が再開する

**期待効果**: バックグラウンド読み上げ数時間のセッションで毎秒 1〜2 回の isolate 起床が消える。実装コスト小・回帰リスク低。

### P6. 画面常時点灯のオプション化【オーナー判断: 見送り（バックログ）】

オーナー回答: 「追加する方針はない。設定としてあってもいいかもね」→ **今回のスコープからは外し、バックログとして設計だけ残す**。将来実装する場合の要点:

- `AppSettings.keepScreenOnWhileConnected`（bool、デフォルト true = 現行挙動）を追加し、`initState` の `WakelockPlus.enable()`（`comment_screen.dart:1210`）と `_syncWakelockForStatus`（同 `5256`）の enable 側を設定値でゲートする:

```dart
  void _syncWakelockForStatus(ConnectionStatus status) {
    // 設定 OFF 時は wakelock を一切取得しない。接続・読み上げは
    // 既存の FGS 経路がそのまま維持する（画面 OFF 時と同じ動作原理）。
    if (!widget.keepScreenOnWhileConnected) {
      _stopWakelockReleaseTimer();
      unawaited(WakelockPlus.disable());
      return;
    }
    // ...既存の switch...
  }
```

- **CLAUDE.md の設定項目ルールに従い Export/Import 対応が必須**: `toJson`/`fromJson` にキー追加、欠損時は true フォールバック（古い Export ファイルの Import で挙動不変）

### P7. 降順表示の reversed コピー除去（優先度: 低）

**目的**: 再構築ごとの O(N) リストコピー（最大 15,000 要素、`comment_screen.dart:4178-4184`）を削る。

**設計**: build 内のリスト表示経路ではコピーを作らず、`itemBuilder` のインデックス写像で降順を実現する。`ListView.reverse: true` はスクロール anchoring と `_isNearTop/_isNearBottom` 判定に波及するため**採用しない**。`_applySortOrder` 自体はログ保存経路（`comment_screen.dart:5543`、単発実行）で使われ続けるので残す。

**コード例（build 内、`comment_screen.dart:3314` と `3629` 付近の差分イメージ）**

```dart
          // 変更前:
          // final List<AppMessage> sortedMessages = _applySortOrder(
          //   searchedMessages,
          // );

          // 変更後: リストのコピーはせず、表示時にインデックスを写像する。
          final List<AppMessage> displayMessages = searchedMessages;
          final bool descending = _sortOrder == CommentSortOrder.descending;
```

```dart
                          child: ListView.builder(
                            key: const Key('comment-list'),
                            controller: _scrollController,
                            itemCount: displayMessages.length,
                            itemBuilder: (BuildContext context, int index) {
                              // 降順時は末尾から数える（reversed コピーの代替）。
                              final AppMessage message = displayMessages[
                                  descending
                                      ? displayMessages.length - 1 - index
                                      : index];
                              // commentIndex（ゼブラ縞用の視覚上の行位置）は
                              // 従来通り index のまま — reversed リスト時代と
                              // 同じ見た目になる。
                              // ...既存の _CommentRow 生成...
```

**注意**: `sortedMessages` を参照している他の箇所（空状態判定・スクロール処理等）を `displayMessages` + 写像に追随させること。挙動（表示順・縞・自動スクロール）はゴールデンで変わらないことをテストで確認する。

### P8. 未使用依存 `audioplayers` の削除（優先度: 低）【オーナー確認済み: 削除する】

読み上げの再生は Android ネイティブ側（`AudioTrackWavPlayer` / `MediaPlayerWavPlayer` / Android TTS）で完結しており、`audioplayers` は Dart コードから参照ゼロ。削除により起動時のプラグイン初期化と APK サイズ・依存面積が減る。

**実施手順**:

```bash
# 1. 参照が本当にゼロであることを確認（lib/ test/ integrations/ tool/）
grep -rn "audioplayers" lib/ test/ integrations/ tool/ android/app/src

# 2. pubspec.yaml から audioplayers: 6.8.1 の行（と直上のコメント）を削除

# 3. 依存解決し直し、lock の差分が audioplayers 系の削除だけであることを
#    レビューする（CLAUDE.md の依存ピン留め・lock コミットルール準拠）
flutter pub get
git diff pubspec.lock

# 4. ビルドとテストが通ることを確認
flutter analyze && flutter test
```

**注意**: `pubspec.yaml:25` のコメント「音声再生（VOICEVOX合成音声の再生）」は過去の設計の名残であり、現行の再生経路と一致していない。削除時にコメントごと除去する。

### P9. 【変更しない判断】FGS の起動タイミング

FGS は前面での接続開始時点から起動し WakeLock/WifiLock を保持するが、これは**意図的に現状維持とする**:
- 画面 ON 中は PARTIAL_WAKE_LOCK の追加消費は実質ゼロ（画面が CPU を起こしている）
- 「背面移行時に初めて FGS を起動する」方式は Android 12+ の background FGS start 制限とのレースを抱え、**接続維持という中核機能の信頼性を落とすリスク**が省電力の利得に見合わない

---

## 4. 期待効果まとめ

| 提案 | 効くシナリオ | 削減対象 | 概算 | 状態 |
|---|---|---|---|---|
| P1 通知コアレッシング | 前面・高頻度放送 | 再構築回数 | 再構築 -50〜75%（10 コメ/秒時） | **実施**（窓 200ms 承認済み） |
| P2 NG 判定メモ化 | 前面・高頻度 × 大タイムライン | 再構築 1 回あたりの CPU | フィルタコストを O(N×正規化) → O(N×lookup) に | **実施** |
| P3 フォロー取得の制御 | 背面滞在・視聴中 | 無線起床 | 背面の 60 秒毎起床をゼロ化 | **実施**（お気に入り側は現状維持） |
| P4 ストール検出 one-shot | 受信中全般（特に背面） | CPU 起床 | 3,600 回/h → ≦240 回/h | **実施** |
| P5 秒針タイマー停止 | 背面読み上げ | CPU 起床 | 毎秒 1〜2 回 → 0 | **実施** |
| P6 常時点灯オプション | 読み上げ主体ユーザー | 画面 | オプトインで最大 | **見送り（バックログ）** |
| P7 reversed 除去 | 前面・降順表示 | アロケーション/GC | 小 | 実施（仕上げ） |
| P8 依存削除 | 起動時 | 初期化・サイズ | 微小 | **実施**（承認済み） |

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
- **回帰確認**: コメント表示遅延（P1 の窓 200ms が体感に出ないこと）、ストール検出遅延（P4 で threshold + α を超えないこと）、復帰時の一覧鮮度（P3 で復帰即時 fetch が走ること）

---

## 6. Issue 分解案

依存順に並べる。1 Issue = 1 PR を想定。**共通の実装ルール**: コード変更後は CLAUDE.md の必須チェック（`flutter analyze` / `flutter format .` / `flutter test`）を全パスさせること。テストは新規ファイルを作らず既存の `<target>_test.dart` に group を追加すること（AGENTS.md のテストファイル肥大化ルール参照）。

### Issue 1: TimelineStore / StatisticsStore の通知コアレッシング（P1）
- **goal**: `CoalescingNotifier` mixin 新設（`lib/application/notify/coalescing_notifier.dart`）+ 両ストアへの適用 + main.dart で 200ms opt-in + `flushPending()` の終了時フック
- **scope**: `timeline_store.dart`, `statistics_store.dart`, `main.dart`（コンストラクタ引数）, `comment_screen.dart`（`_handleConnectionChanged` 冒頭の flush 1 箇所）
- **non-scope**: CommentScreen の build ロジック変更、NG 判定キャッシュ
- **AC**: 窓内の連続 add が leading + trailing の 2 通知に集約される / 窓経過後の単発 add は即時通知 / `clear`・`setCapacity` は即時通知 / dispose 後に trailing が発火しない / `notifyWindow: Duration.zero` で既存テストが無修正で通る / 終了ステータス遷移時に flush され自動保存が窓内コメントを取りこぼさない
- **test**: `timeline_store_test.dart` / `statistics_store_test.dart` に `fake_async` ベースの group を追加

### Issue 2: NG 表示判定のメモ化（P2）
- **goal**: `_ngVerdictCache` 導入（`NgMatcher` は変更しない）
- **依存**: Issue 1 と独立（並行可）
- **non-scope**: `NgMatcher` / 正規化関数の変更（Kotlin 側との一致契約に触れない）、検索キャッシュとの統合
- **AC**: NG 語・表示設定変更で既存コメントの表示可否が即時再評価される / 判定結果が変更前後で完全一致（既存テスト全パス）/ キャッシュ上限到達時に wholesale clear / `NgDisplayPreferences` の変更検知が機能する（必要なら `==`/`hashCode` 追加）
- **test**: 既存 `comment_screen_test.dart` の NG フィルタ group に追加

### Issue 3: フォロー中番組ポーリングのライフサイクル制御（P3）
- **goal**: `_scheduleFollowRefresh` ゲート導入 + 背面/視聴中のタイマー即時停止 + resumed 時の即時 fetch 再開
- **non-scope**: お気に入りユーザーチェックの周期・背面挙動（現状維持がオーナー決定）
- **AC**: 背面移行後にフォロー取得のネットワーク呼び出しが発生しない（fake timer で検証）/ 前面復帰で即時 fetch + 60 秒周期再開 / CommentScreen 表示中は取得停止、pop 後に即時 fetch（既存挙動の維持）
- **test**: select_screen の既存テストファイルに group 追加

### Issue 4: NDGR ストール検出の one-shot 化（P4）
- **goal**: periodic 1s → one-shot 残時間再 arm 方式（`NdgrStallDetector` は不変）
- **AC**: 受信継続中はタイマー発火が threshold 間隔以下 / 受信停止から threshold 経過で stalled がちょうど 1 回発火 / stalled → 受信再開 → 再停止で 2 回目が発火 / `stop`/`dispose` でタイマーが残らない
- **test**: 既存 `ndgr_client` テストの stall group に追加（`fake_async`）

### Issue 5: 秒針タイマーのライフサイクル停止（P5）
- **goal**: `_StatusBar` / `_RemainingTimeIndicator` の背面 pause / 前面 resume
- **AC**: paused/hidden 遷移でタイマー停止 / resumed で表示が正しい経過時間に即時復帰（ズレなし）/ inactive では止まらない
- **test**: 既存 `comment_screen_test.dart` / broadcast_control_panel のテストに group 追加

### Issue 6: 仕上げ（P7 + P8）
- **goal**: 降順表示のインデックス写像化 + `audioplayers` 依存削除
- **AC（P7）**: 表示順・ゼブラ縞・自動スクロール挙動が既存テストで不変 / build 内での `reversed.toList()` が消えている
- **AC（P8）**: `grep -rn audioplayers` が pubspec 以外でヒットしない状態を確認した上で削除 / `pubspec.lock` の差分が audioplayers 系の削除のみ / `flutter analyze` / `flutter test` 全パス

### （バックログ）Issue 7: 画面常時点灯のオプション化（P6）
- オーナーが将来必要と判断した場合に着手。設計は本書 P6 節を参照。Export/Import 後方互換（欠損時 true フォールバック）が must fix 条件

---

## 7. オーナー確認事項と回答（rev.2 で確定）

| # | 質問 | 回答 | 設計への反映 |
|---|---|---|---|
| 1 | コアレッシング窓 200ms は許容か | **許容** | P1 の窓を 200ms で確定 |
| 2 | お気に入り放送チェックを背面中も続けるか | **必要（継続する）**。※現在の間隔は前面 15 秒 / 背面・視聴中 120 秒（60 秒はフォロー中番組一覧の取得の方） | P3 の対象からお気に入り側を除外。「放送開始通知」機能は現状予定なし |
| 3 | ストール検出の one-shot 化に伴う検出タイミング | （実質同等のため判断不要と整理） | P4 の設計ノートに明記: 検出は「最終受信から threshold + 再 arm 誤差」で現行と同等以上の精度 |
| 4 | P6（常時点灯オプション）を追加するか | **方針なし（あってもいいかも、程度）** | バックログ化。設計のみ残す |
| 5 | `audioplayers` を残す意図はあるか | **なし**。読み上げでは使っていない（再生はネイティブ側で完結） | P8 を「実施」に確定 |

---

## 8. まとめ

- 支配的な消費（画面点灯・ストリーミング・音声合成）は機能そのものであり、パイプライン設計（キュー上限・重複排除・event-driven ワーカー・接続再利用・バックオフ）は既に電池観点で健全
- 削減余地は「同じ仕事のやり直し」と「見えていない間の稼働」に集中している:
  1. **コメント 1 件 → 2 回の全画面再構築 → タイムライン全件の NG 再判定**という掛け算(P1 + P2)
  2. **背面でも止まらないポーリングと秒針タイマー**(P3 + P4 + P5)
- いずれもユーザー可視の挙動を変えずに実装可能。オーナー回答を反映し、P1〜P5・P7・P8 を実施、P6 をバックログとした
