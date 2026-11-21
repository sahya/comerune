import 'dart:developer';

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
///   reports a failure once through [onUnavailable].
/// - Runs at most one lookup per program, and drops a lookup result when
///   the user has switched to another program meanwhile.
/// - Resets the fetch state when the program changes, so a fetch for one
///   program never continues into another one.
/// - Skips the fetch when live comments were already received for the
///   program: the user watched it live and the broadcast just ended
///   (Issue #1017), so there is nothing to fetch and no dialog to show.
class TimeshiftFetchStarter {
  TimeshiftFetchStarter({
    required bool enabled,
    required String Function() currentLv,
    required TimeshiftFetchStatus Function() status,
    required Future<void> Function(Uri viewApiUri) fetchInitial,
    required Future<void> Function() cancelAndReset,
    required TimeshiftViewUriLookup lookUpViewUri,
    required void Function() onUnsupported,
    required void Function(TimeshiftViewUriFailure? failure) onUnavailable,
  }) : _enabled = enabled,
       _currentLv = currentLv,
       _status = status,
       _fetchInitial = fetchInitial,
       _cancelAndReset = cancelAndReset,
       _lookUpViewUri = lookUpViewUri,
       _onUnsupported = onUnsupported,
       _onUnavailable = onUnavailable;

  final bool _enabled;
  final String Function() _currentLv;
  final TimeshiftFetchStatus Function() _status;
  final Future<void> Function(Uri viewApiUri) _fetchInitial;
  final Future<void> Function() _cancelAndReset;
  final TimeshiftViewUriLookup _lookUpViewUri;
  final void Function() _onUnsupported;
  final void Function(TimeshiftViewUriFailure? failure) _onUnavailable;

  String? _programLv;
  String? _liveCommentsLv;
  String? _resolvingLv;
  String? _fetchingLv;

  /// Whether messages from the timeshift fetch belong to the program that
  /// is open now. Messages that arrive after a program switch are dropped.
  bool get acceptsMessages =>
      _fetchingLv != null && _fetchingLv == _currentLv();

  /// Records that live comments arrived for the open program.
  void markLiveCommentsReceived() {
    final String lv = _currentLv();
    if (lv.isNotEmpty) {
      _liveCommentsLv = lv;
    }
  }

  /// Call when a connection is prepared for [lv]. Resets the fetch state
  /// when [lv] differs from the previous program; a reconnect to the same
  /// program keeps what was already fetched.
  Future<void> onProgramChanged(String lv) async {
    if (_programLv == lv) {
      return;
    }
    _programLv = lv;
    _liveCommentsLv = null;
    _resolvingLv = null;
    _fetchingLv = null;
    await _cancelAndReset();
  }

  /// Call when the open program turned out to be an ended program.
  /// [viewApiUri] is the view URI from the program info, or `null` when it
  /// had none (Issue #654).
  Future<void> onTimeshiftDetected(Uri? viewApiUri) async {
    if (!_enabled) {
      _onUnsupported();
      return;
    }
    final String lv = _currentLv();
    if (lv.isEmpty ||
        _liveCommentsLv == lv ||
        _status() != TimeshiftFetchStatus.idle) {
      return;
    }

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
        if (_resolvingLv == lv) {
          _resolvingLv = null;
        }
      }
      if (_currentLv() != lv || _liveCommentsLv == lv) {
        return;
      }
      uri = result?.viewUri;
      if (uri == null) {
        // Only the failure kind is logged, never URLs or cookies.
        log(
          'Timeshift view URI unavailable: ${result?.failure?.name}',
          name: 'TimeshiftFetchStarter',
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
      log(
        'Timeshift initial fetch failed',
        name: 'TimeshiftFetchStarter',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
