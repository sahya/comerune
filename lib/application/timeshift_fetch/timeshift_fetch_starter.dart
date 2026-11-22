import 'dart:developer';

import '../../app_logging.dart';
import '../../data/connection/timeshift_view_uri_resolver.dart';
import 'timeshift_fetch_controller.dart';

/// Looks up the view URI of an ended program for [lv].
typedef TimeshiftViewUriLookup =
    Future<TimeshiftViewUriResult> Function(String lv);

/// Decides when to start the timeshift (ended program) comment fetch.
///
/// Sits between connection events and [TimeshiftFetchController]:
///
/// - When the program info had no view URI (Issue #654), looks it up and
///   reports a failure through [onUnavailable] (the caller shows it at most
///   once per program).
/// - Runs at most one lookup per program switch, and drops a lookup result
///   when the user has switched to another program meanwhile (even when
///   they switched back to the same program).
/// - Resets the fetch state when the program changes, so a fetch for one
///   program never continues into another one.
/// - Skips the fetch when the current connection was streaming live: the
///   user watched the broadcast live and it just ended (Issue #1017), so
///   there is nothing to fetch and no dialog to show.
class TimeshiftFetchStarter {
  TimeshiftFetchStarter({
    required bool enabled,
    required String Function() currentLv,
    required bool Function() hasStreamedLive,
    required TimeshiftFetchStatus Function() status,
    required Future<void> Function(Uri viewApiUri) fetchInitial,
    required Future<void> Function() cancelAndReset,
    required TimeshiftViewUriLookup lookUpViewUri,
    required void Function() onUnsupported,
    required void Function(TimeshiftViewUriFailure? failure) onUnavailable,
  }) : _enabled = enabled,
       _currentLv = currentLv,
       _hasStreamedLive = hasStreamedLive,
       _status = status,
       _fetchInitial = fetchInitial,
       _cancelAndReset = cancelAndReset,
       _lookUpViewUri = lookUpViewUri,
       _onUnsupported = onUnsupported,
       _onUnavailable = onUnavailable;

  final bool _enabled;
  final String Function() _currentLv;
  final bool Function() _hasStreamedLive;
  final TimeshiftFetchStatus Function() _status;
  final Future<void> Function(Uri viewApiUri) _fetchInitial;
  final Future<void> Function() _cancelAndReset;
  final TimeshiftViewUriLookup _lookUpViewUri;
  final void Function() _onUnsupported;
  final void Function(TimeshiftViewUriFailure? failure) _onUnavailable;

  String? _programLv;
  String? _resolvingLv;
  String? _fetchingLv;
  Future<void>? _pendingReset;
  // Advanced on every program switch and on dispose; a lookup started in
  // an older generation is discarded when it finishes.
  int _generation = 0;
  bool _disposed = false;

  /// Stops acting on lookups and fetches that are still running.
  void dispose() {
    _disposed = true;
    _generation += 1;
  }

  /// Whether messages from the timeshift fetch belong to the program that
  /// is open now. Messages that arrive after a program switch are dropped.
  bool get acceptsMessages =>
      _fetchingLv != null && _fetchingLv == _currentLv();

  /// Call when a connection is prepared for [lv]. Resets the fetch state
  /// when [lv] differs from the previous program; a reconnect to the same
  /// program keeps what was already fetched.
  Future<void> onProgramChanged(String lv) async {
    if (_programLv == lv) {
      return;
    }
    _programLv = lv;
    _generation += 1;
    _resolvingLv = null;
    _fetchingLv = null;
    final Future<void> reset = _resetLogged();
    _pendingReset = reset;
    try {
      await reset;
    } finally {
      if (identical(_pendingReset, reset)) {
        _pendingReset = null;
      }
    }
  }

  /// Resets the fetch state; a failure is logged and never rethrown.
  Future<void> _resetLogged() async {
    try {
      await _cancelAndReset();
    } on Object catch (error, stackTrace) {
      log(
        'Timeshift fetch reset failed: ${error.runtimeType}',
        name: 'TimeshiftFetchStarter',
        stackTrace: stackTrace,
      );
    }
  }

  /// Call when the open program turned out to be an ended program.
  /// [viewApiUri] is the view URI from the program info, or `null` when it
  /// had none (Issue #654).
  Future<void> onTimeshiftDetected(Uri? viewApiUri) async {
    if (_disposed || _hasStreamedLive()) {
      return;
    }
    if (!_enabled) {
      _onUnsupported();
      return;
    }
    // Let a reset for a program switch finish first, so the previous
    // program's status does not make this one look already fetched.
    final Future<void>? pendingReset = _pendingReset;
    if (pendingReset != null) {
      // onProgramChanged logs a failed reset and never rethrows.
      await pendingReset;
    }
    final String lv = _currentLv();
    if (_disposed || lv.isEmpty || _status() != TimeshiftFetchStatus.idle) {
      return;
    }
    final int generation = _generation;

    Uri? uri = viewApiUri;
    if (uri == null) {
      if (_resolvingLv == lv) {
        return;
      }
      _resolvingLv = lv;
      TimeshiftViewUriResult? result;
      try {
        result = await _lookUpViewUri(lv);
      } on Object catch (error, stackTrace) {
        log(
          'Timeshift view URI lookup threw',
          name: 'TimeshiftFetchStarter',
          error: error.runtimeType,
          stackTrace: stackTrace,
        );
      } finally {
        if (generation == _generation && _resolvingLv == lv) {
          _resolvingLv = null;
        }
      }
      if (generation != _generation ||
          _currentLv() != lv ||
          _hasStreamedLive()) {
        return;
      }
      uri = result?.viewUri;
      if (uri == null) {
        // Only the failure kind is logged, never URLs or cookies. Shown in
        // debug builds' logcat so the failure can be checked on a device.
        appDebugLog(
          '[TimeshiftFetchStarter] Timeshift view URI unavailable: '
          '${result?.failure?.name}',
        );
        _onUnavailable(result?.failure);
        return;
      }
      if (_status() != TimeshiftFetchStatus.idle) {
        return;
      }
    }

    _fetchingLv = lv;
    try {
      await _fetchInitial(uri);
    } on Object catch (error, stackTrace) {
      // Only the type: HTTP errors can carry signed URLs.
      log(
        'Timeshift initial fetch failed: ${error.runtimeType}',
        name: 'TimeshiftFetchStarter',
        stackTrace: stackTrace,
      );
    }
  }
}
