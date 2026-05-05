import 'dart:async';

import '../../app_logging.dart';
import '../../data/broadcast/broadcast_control_repository.dart';
import '../../domain/models/app_message.dart';

/// Issue #876: a clock abstraction so the controller can be tested with
/// `fake_async` without bringing in a third-party clock package. The
/// production default reads the real system wall clock.
typedef AutoExtendClock = DateTime Function();

/// Issue #876: source of truth for the controller's tunable thresholds.
/// Kept as a separate immutable object so future Issue (per-user
/// configuration) can swap values without rewriting the controller.
class AutoExtendBroadcastConfig {
  const AutoExtendBroadcastConfig({
    this.thresholdBeforeEnd = const Duration(minutes: 5),
    this.extendMinutes = 30,
    this.maxRetries = 3,
    this.retryBackoff = const Duration(seconds: 30),
  });

  /// 「残り {threshold} を切ったら自動延長」の閾値。Issue #876 では
  /// 5 分固定。
  final Duration thresholdBeforeEnd;

  /// 自動延長 API に渡す `minutes`。Issue #876 では 30 分固定。
  final int extendMinutes;

  /// 失敗時のリトライ最大回数（最初の試行 1 + リトライ N-1 回）。
  final int maxRetries;

  /// リトライ間隔。
  final Duration retryBackoff;
}

/// Issue #876: timer-driven auto-extension orchestrator.
///
/// 責務:
/// - Switch ON 時に「endAt - 閾値」のタイミングで `extendBroadcast` を呼ぶ
///   ことを Timer で予約する。
/// - 失敗時にリトライ（最大 [AutoExtendBroadcastConfig.maxRetries] 回、
///   間隔 [AutoExtendBroadcastConfig.retryBackoff]）。
/// - 成功時に新 `endAt` で再スケジュール、`onEndTimeUpdated` で上位に
///   通知し、コメ欄に成功メッセージを emit。
/// - 失敗時に Switch を OFF にせず（次のタイマー発火が来ないので連続
///   失敗ループは起きない）、コメ欄に失敗メッセージを emit。
/// - Switch OFF / 配信終了 / アプリ background 移行で Timer をキャンセル。
/// - アプリ復帰で再評価。
///
/// 状態の所有:
/// - 「Switch ON/OFF」「endAt」「programId」「userSession」は呼び出し
///   元（screen state）が所有し、変化のたびに [update] で渡す。
/// - 「Timer」「リトライ進行中フラグ」は本コントローラー内部の状態。
class AutoExtendBroadcastController {
  AutoExtendBroadcastController({
    required this.repository,
    required this.emitMessage,
    required this.onEndTimeUpdated,
    required this.successMessageBuilder,
    required this.failureMessage,
    AutoExtendBroadcastConfig config = const AutoExtendBroadcastConfig(),
    AutoExtendClock? clock,
  }) : _config = config,
       _clock = clock ?? DateTime.now;

  final BroadcastControlRepository repository;

  /// コメ欄にシステムメッセージを emit するためのコールバック。null
  /// (= host が TimelineStore を持たない構成) の場合は drop される
  /// 設計を想定し、呼出元で null-safe に渡すこと。
  final void Function(AppMessage message) emitMessage;

  /// 自動延長 API 成功で得られた新 `endAt` を上位に通知するコール
  /// バック。上位が `FollowProgram.endAt` を更新し、その値が
  /// [update] 経由で controller に戻ってくるまでが 1 サイクル。
  final void Function(DateTime newEndAt) onEndTimeUpdated;

  /// 成功時にコメ欄へ流すシステムメッセージの文字列ビルダー。引数は
  /// 実際に伸びた分数（[AutoExtendBroadcastConfig.extendMinutes]）。
  /// 文字列の所有・i18n 責務は host (presentation 層) に残し、本
  /// application 層は文字列リテラルを持たない設計。
  final String Function(int minutes) successMessageBuilder;

  /// 失敗時にコメ欄へ流すシステムメッセージ。i18n 済の表示文字列を
  /// host から渡す（理由は [successMessageBuilder] と同じ）。
  final String failureMessage;

  static const String _logName = 'AutoExtendBroadcastController';

  final AutoExtendBroadcastConfig _config;
  final AutoExtendClock _clock;

  Timer? _timer;
  bool _disposed = false;
  bool _paused = false;

  /// Last applied state, kept so the controller can re-evaluate after a
  /// pause / resume cycle without forcing the host to re-call [update]
  /// with redundant data.
  bool _enabled = false;
  String _programId = '';
  String _userSession = '';
  DateTime? _endAt;

  /// True while a fire (initial call + ongoing retries) is in flight.
  /// Prevents a second Timer from stacking if [update] is called while
  /// the API is mid-call (e.g. a parent rebuild sets the same enabled
  /// + endAt again).
  bool _firing = false;

  /// Test-only accessor for white-box assertions. Returns whether the
  /// controller currently has a scheduled Timer waiting to fire.
  bool get hasScheduledTimerForTesting => _timer != null;

  /// Test-only accessor for white-box assertions on the in-flight
  /// retry state.
  bool get isFiringForTesting => _firing;

  /// Apply the latest desired state. Called by the screen state on:
  /// - Switch toggle
  /// - widget rebuild with a different `endAt` (e.g. after manual extend
  ///   propagated `BroadcastControlResult.endTime` upstream)
  /// - programId / userSession change
  ///
  /// The implementation diff-checks against the last applied state so
  /// redundant calls are no-ops. The Timer is cancelled and re-scheduled
  /// only when something material changes.
  void update({
    required bool enabled,
    required String programId,
    required String userSession,
    required DateTime? endAt,
  }) {
    if (_disposed) {
      return;
    }
    final bool changed =
        _enabled != enabled ||
        _programId != programId ||
        _userSession != userSession ||
        _endAt != endAt;
    _enabled = enabled;
    _programId = programId;
    _userSession = userSession;
    _endAt = endAt;
    if (!changed) {
      return;
    }
    _reschedule();
  }

  /// Cancels the Timer without forgetting the desired state. Call from
  /// `AppLifecycleState.paused` so the app does not silently fire while
  /// in the background.
  void pause() {
    if (_disposed || _paused) {
      return;
    }
    _paused = true;
    _cancelTimer();
  }

  /// Restores Timer scheduling using the last applied state. Call from
  /// `AppLifecycleState.resumed`.
  void resume() {
    if (_disposed || !_paused) {
      return;
    }
    _paused = false;
    _reschedule();
  }

  /// Releases the Timer. Safe to call multiple times.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _cancelTimer();
  }

  // ---- Internal ----

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Computes the next Timer delay and arms it. Idempotent — safe to call
  /// after [update] / [pause] / [resume] state shifts.
  void _reschedule() {
    _cancelTimer();
    if (_disposed || _paused || _firing) {
      // While firing the in-progress retry chain owns scheduling. We
      // re-schedule once it settles (success path → new endAt arrives via
      // [update]; failure path → controller idles until the host changes
      // state).
      return;
    }
    if (!_enabled) {
      return;
    }
    final DateTime? endAt = _endAt;
    if (endAt == null) {
      return;
    }
    if (_programId.isEmpty || _userSession.isEmpty) {
      return;
    }
    final DateTime fireAt = endAt.subtract(_config.thresholdBeforeEnd);
    final Duration delay = fireAt.difference(_clock());
    if (delay.isNegative || delay == Duration.zero) {
      // Already past the threshold — fire immediately. Use a zero-delay
      // Timer rather than a synchronous call so the host's setState
      // pipeline can settle before the API call goes out (avoids
      // re-entering setState during build).
      _timer = Timer(Duration.zero, _fire);
      return;
    }
    _timer = Timer(delay, _fire);
  }

  Future<void> _fire() async {
    if (_disposed || _paused || !_enabled) {
      return;
    }
    _firing = true;
    try {
      await _attemptWithRetries();
    } finally {
      _firing = false;
      // Successful attempts re-schedule via the `onEndTimeUpdated`
      // round-trip (host updates endAt, controller receives new endAt
      // through [update]). Failed attempts leave the controller idle —
      // the next firing only comes back if the host extends the
      // broadcast manually or toggles the Switch off/on.
    }
  }

  Future<void> _attemptWithRetries() async {
    for (int attempt = 1; attempt <= _config.maxRetries; attempt++) {
      if (_disposed || _paused || !_enabled) {
        return;
      }
      final BroadcastControlResult result;
      try {
        result = await repository.extendBroadcast(
          programId: _programId,
          userSession: _userSession,
          minutes: _config.extendMinutes,
        );
      } on Object catch (e, st) {
        // The repository normally maps Exception subtypes into a
        // BroadcastControlResult, but defensive: anything that escapes
        // (Error subclasses, programming mistakes) is treated as a
        // failed attempt so the retry chain keeps going. Log via the
        // project debug channel so field issues are reproducible.
        appDebugLogLazy(
          () =>
              '[$_logName] extendBroadcast threw on attempt $attempt: $e\n$st',
        );
        await _waitForRetryOrAbort(attempt);
        continue;
      }

      if (result.success) {
        _onSuccess(result);
        return;
      }

      // 既存上限到達は再試行しても成功しないが、本実装はエラーコード
      // 別の早期 abort をしない（仕様上は単純なリトライ N 回で OK）。
      // PR2 の AC「失敗時に最大 3 回までリトライされる」を素直に満たす。
      await _waitForRetryOrAbort(attempt);
    }
    _onAllRetriesFailed();
  }

  /// Sleeps the retry backoff between attempts. Returns early if the
  /// controller becomes disabled / paused / disposed during the wait so
  /// the host's state takes precedence over the in-flight retry chain.
  Future<void> _waitForRetryOrAbort(int attempt) async {
    if (attempt >= _config.maxRetries) {
      return;
    }
    await Future<void>.delayed(_config.retryBackoff);
  }

  void _onSuccess(BroadcastControlResult result) {
    final int? endTimeSec = result.endTime;
    if (endTimeSec != null) {
      // Server returned the authoritative new end time — propagate it
      // upstream so FollowProgram.endAt updates and the next [update]
      // call carries the new value back into the controller.
      final DateTime newEndAt = DateTime.fromMillisecondsSinceEpoch(
        endTimeSec * 1000,
      );
      onEndTimeUpdated(newEndAt);
    }
    _emit(_buildSuccessMessage());
  }

  void _onAllRetriesFailed() {
    appDebugLogLazy(
      () =>
          '[$_logName] all ${_config.maxRetries} retries failed; '
          'leaving the Switch ON so the broadcaster decides whether to '
          'manually extend or toggle off.',
    );
    _emit(_buildFailureMessage());
  }

  void _emit(AppMessage message) {
    if (_disposed) return;
    emitMessage(message);
  }

  AppMessage _buildSuccessMessage() {
    final DateTime now = _clock();
    return AppMessage(
      id: buildAutoExtendSuccessNotificationId(
        epochMilliseconds: now.millisecondsSinceEpoch,
        sequence: _nextSequence(),
      ),
      timestamp: now,
      content: successMessageBuilder(_config.extendMinutes),
      type: AppMessageType.notification,
    );
  }

  AppMessage _buildFailureMessage() {
    final DateTime now = _clock();
    return AppMessage(
      id: buildAutoExtendFailureNotificationId(
        epochMilliseconds: now.millisecondsSinceEpoch,
        sequence: _nextSequence(),
      ),
      timestamp: now,
      content: failureMessage,
      type: AppMessageType.notification,
    );
  }

  int _sequence = 0;
  int _nextSequence() => _sequence++;
}
