import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/connection/ndgr_timeshift_client.dart';
import '../../domain/models/app_message.dart';

enum TimeshiftFetchStatus { idle, fetching, paused, completed, error }

/// Classified error captured by [TimeshiftFetchController].
///
/// `retryable` is consumed by the UI (`TimeshiftFetchPanel`) to gate the
/// retry button: when `false`, the cause is not expected to recover from a
/// simple same-URL retry (e.g. HTTP 401/403 permission errors, which on
/// niconico typically indicate the timeshift is premium-only).
///
/// Issue #639 cause 5.
@immutable
class TimeshiftFetchError {
  const TimeshiftFetchError({required this.retryable, required this.cause});

  /// Whether the fetch should be offered for retry in the UI.
  ///
  /// - `true`: transient network/server failures (connection dropped,
  ///   5xx, socket errors).
  /// - `false`: permanent-looking failures that same-URL retry cannot
  ///   resolve (4xx auth errors, malformed URL, protocol decode errors).
  final bool retryable;

  /// The underlying exception captured from the fetch pipeline.
  final Object cause;

  /// Classifies an arbitrary exception into a [TimeshiftFetchError].
  ///
  /// Mapping rules (conservative — anything unknown is `retryable=true`
  /// to preserve the legacy UX):
  ///
  /// - `HttpException` with a 4xx status (other than 408/429) → not
  ///   retryable. 401/403 typically mean the broadcast is premium-only,
  ///   404 means the timeshift has been removed.
  /// - `HttpException` 408/429/5xx, `SocketException`, `TimeoutException`
  ///   → retryable (transient).
  /// - Anything else → retryable (fall back to legacy behaviour).
  factory TimeshiftFetchError.classify(Object error) {
    if (error is HttpException) {
      final int? status = _extractHttpStatus(error.message);
      if (status != null) {
        // 408 Request Timeout and 429 Too Many Requests are transient.
        if (status == 408 || status == 429) {
          return TimeshiftFetchError(retryable: true, cause: error);
        }
        if (status >= 400 && status < 500) {
          return TimeshiftFetchError(retryable: false, cause: error);
        }
      }
      // 5xx or unknown status → treat as transient.
      return TimeshiftFetchError(retryable: true, cause: error);
    }
    if (error is SocketException || error is TimeoutException) {
      return TimeshiftFetchError(retryable: true, cause: error);
    }
    return TimeshiftFetchError(retryable: true, cause: error);
  }

  /// Extracts an HTTP status code from an `HttpException` message string
  /// of the shape `"NDGR timeshift <phase> request failed with status <N>"`
  /// (as emitted by `NdgrTimeshiftClient._fetch` at
  /// `lib/domain/connection/ndgr_timeshift_client.dart`).
  ///
  /// Lock-step coupling: this parser depends on the exact message format
  /// emitted by `NdgrTimeshiftClient`. If that format changes, the
  /// classification silently falls back to "retryable=true" and
  /// non-retryable 4xx responses would be offered for retry in the UI.
  /// The `_ndgrTimeshiftClientMessageFormatIsStable` test in
  /// `test/application/timeshift_fetch/timeshift_fetch_controller_test.dart`
  /// guards the invariant — keep it in sync if the producer side changes.
  ///
  /// Returns `null` when the pattern does not match.
  static int? _extractHttpStatus(String message) {
    // Anchor to end of string so a stray 3-digit number elsewhere in the
    // message does not shadow the actual status code.
    final RegExpMatch? match = RegExp(
      r'status (\d{3})\s*$',
    ).firstMatch(message);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1) ?? '');
  }
}

class TimeshiftFetchController extends ChangeNotifier {
  TimeshiftFetchController({
    required NdgrTimeshiftClient client,
    required void Function(List<AppMessage> messages) onMessages,
    int fetchAllBatchSize = 500,
    Duration fetchAllBatchDelay = const Duration(milliseconds: 100),
  }) : _client = client,
       _onMessages = onMessages,
       _fetchAllBatchSize = fetchAllBatchSize,
       _fetchAllBatchDelay = fetchAllBatchDelay {
    _subscription = _client.events.listen(_handleTimeshiftEvent);
  }

  final NdgrTimeshiftClient _client;
  final void Function(List<AppMessage> messages) _onMessages;
  final int _fetchAllBatchSize;
  final Duration _fetchAllBatchDelay;

  StreamSubscription<NdgrTimeshiftEvent>? _subscription;
  bool _isFetchingAll = false;
  bool _cancelRequested = false;
  TimeshiftFetchError? _lastError;

  TimeshiftFetchStatus _status = TimeshiftFetchStatus.idle;

  TimeshiftFetchStatus get status => _status;
  bool get hasMore => _client.hasMore;
  int get totalFetched => _client.totalFetched;
  bool get isFetchingAll => _isFetchingAll;

  /// The last fetch failure, or `null` when the controller is not in the
  /// error state. Callers should use [TimeshiftFetchError.retryable] to
  /// decide whether to offer a retry action.
  TimeshiftFetchError? get lastError => _lastError;

  Future<void> fetchInitial(Uri viewApiUri) async {
    if (_status == TimeshiftFetchStatus.fetching) {
      return;
    }
    _setStatus(TimeshiftFetchStatus.fetching);
    _lastError = null;

    try {
      await _client.fetchPastComments(viewApiUri);
      _setStatus(
        _client.hasMore
            ? TimeshiftFetchStatus.paused
            : TimeshiftFetchStatus.completed,
      );
    } on Object catch (error) {
      _lastError = TimeshiftFetchError.classify(error);
      _setStatus(TimeshiftFetchStatus.error);
    }
  }

  Future<void> fetchMore(int count) async {
    if (_status == TimeshiftFetchStatus.fetching) {
      return;
    }
    if (!_client.hasMore) {
      _setStatus(TimeshiftFetchStatus.completed);
      return;
    }
    _setStatus(TimeshiftFetchStatus.fetching);
    _lastError = null;

    try {
      await _client.fetchMore(count: count);
      _setStatus(
        _client.hasMore
            ? TimeshiftFetchStatus.paused
            : TimeshiftFetchStatus.completed,
      );
    } on Object catch (error) {
      _lastError = TimeshiftFetchError.classify(error);
      _setStatus(TimeshiftFetchStatus.error);
    }
  }

  Future<void> fetchAll() async {
    if (_status == TimeshiftFetchStatus.fetching || _isFetchingAll) {
      return;
    }
    if (!_client.hasMore) {
      _setStatus(TimeshiftFetchStatus.completed);
      return;
    }

    _isFetchingAll = true;
    _cancelRequested = false;
    _lastError = null;
    _setStatus(TimeshiftFetchStatus.fetching);

    try {
      while (_client.hasMore && !_cancelRequested) {
        await _client.fetchMore(count: _fetchAllBatchSize);
        if (_client.hasMore && !_cancelRequested) {
          await Future<void>.delayed(_fetchAllBatchDelay);
        }
      }
      _setStatus(
        _client.hasMore
            ? TimeshiftFetchStatus.paused
            : TimeshiftFetchStatus.completed,
      );
    } on Object catch (error) {
      _lastError = TimeshiftFetchError.classify(error);
      _setStatus(TimeshiftFetchStatus.error);
    } finally {
      _isFetchingAll = false;
      _cancelRequested = false;
    }
  }

  Future<void> cancel() async {
    _cancelRequested = true;
    try {
      await _client.stop();
    } on Object catch (error, stackTrace) {
      log(
        'Timeshift cancel failed',
        name: 'TimeshiftFetchController',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (_status == TimeshiftFetchStatus.fetching) {
      _setStatus(
        _client.hasMore
            ? TimeshiftFetchStatus.paused
            : TimeshiftFetchStatus.completed,
      );
    }
    _isFetchingAll = false;
  }

  void reset() {
    _client.resetSession();
    _isFetchingAll = false;
    _cancelRequested = false;
    _lastError = null;
    _setStatus(TimeshiftFetchStatus.idle);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }

  void _handleTimeshiftEvent(NdgrTimeshiftEvent event) {
    switch (event.type) {
      case NdgrTimeshiftEventType.progress:
        if (event.messages != null && event.messages!.isNotEmpty) {
          _onMessages(event.messages!);
        }
        notifyListeners();
        break;
      case NdgrTimeshiftEventType.started:
      case NdgrTimeshiftEventType.completed:
        break;
      case NdgrTimeshiftEventType.error:
        log(
          'Timeshift event error: ${event.error}',
          name: 'TimeshiftFetchController',
        );
        break;
    }
  }

  void _setStatus(TimeshiftFetchStatus next) {
    if (_status == next) {
      return;
    }
    _status = next;
    notifyListeners();
  }
}
