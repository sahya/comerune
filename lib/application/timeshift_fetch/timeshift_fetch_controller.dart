import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';

import '../../domain/connection/ndgr_timeshift_client.dart';
import '../../domain/models/app_message.dart';

enum TimeshiftFetchStatus { idle, fetching, paused, completed, error }

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
  Object? _lastError;

  TimeshiftFetchStatus _status = TimeshiftFetchStatus.idle;

  TimeshiftFetchStatus get status => _status;
  bool get hasMore => _client.hasMore;
  int get totalFetched => _client.totalFetched;
  bool get isFetchingAll => _isFetchingAll;
  Object? get lastError => _lastError;

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
      _lastError = error;
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
      _lastError = error;
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
      _lastError = error;
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
