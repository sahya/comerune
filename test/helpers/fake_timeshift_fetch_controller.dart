import 'package:comerune/application/timeshift_fetch/timeshift_fetch_controller.dart';
import 'package:flutter/foundation.dart';

/// Test double for [TimeshiftFetchController] whose state is set directly.
///
/// The fetch methods do nothing; drive the state with [setStatus] instead.
class FakeTimeshiftFetchController extends ChangeNotifier
    implements TimeshiftFetchController {
  FakeTimeshiftFetchController({
    TimeshiftFetchStatus status = TimeshiftFetchStatus.idle,
    bool hasMore = false,
    int totalFetched = 0,
    bool isFetchingAll = false,
    TimeshiftFetchError? lastError,
  }) : _status = status,
       _hasMore = hasMore,
       _totalFetched = totalFetched,
       _isFetchingAll = isFetchingAll,
       _lastError = lastError;

  TimeshiftFetchStatus _status;
  final bool _hasMore;
  final int _totalFetched;
  final bool _isFetchingAll;
  final TimeshiftFetchError? _lastError;

  /// Changes [status] and notifies listeners, like the real controller.
  void setStatus(TimeshiftFetchStatus next) {
    _status = next;
    notifyListeners();
  }

  @override
  TimeshiftFetchStatus get status => _status;

  @override
  bool get hasMore => _hasMore;

  @override
  int get totalFetched => _totalFetched;

  @override
  bool get isFetchingAll => _isFetchingAll;

  @override
  TimeshiftFetchError? get lastError => _lastError;

  @override
  Future<void> fetchInitial(Uri viewApiUri) async {}

  @override
  Future<void> fetchMore(int count) async {}

  @override
  Future<void> fetchAll() async {}

  @override
  Future<void> cancel() async {}

  @override
  void reset() => setStatus(TimeshiftFetchStatus.idle);

  @override
  Future<void> cancelAndReset() async => reset();
}
