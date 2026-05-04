import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/models/app_message.dart';

class StatisticsStore extends ChangeNotifier {
  StatisticsStore({
    Duration activeWindow = const Duration(minutes: 5),
    Duration purgeInterval = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : _activeWindow = activeWindow,
       _purgeInterval = purgeInterval,
       _now = now ?? DateTime.now;

  final Duration _activeWindow;
  final Duration _purgeInterval;
  final DateTime Function() _now;

  Timer? _purgeTimer;
  bool _disposed = false;

  int _totalCommentCount = 0;
  int? _viewerCount;
  final Map<String, DateTime> _latestActivityByUser = <String, DateTime>{};

  int get totalCommentCount => _totalCommentCount;
  int? get viewerCount => _viewerCount;

  int get activeUserCount {
    _purgeExpired();
    return _latestActivityByUser.length;
  }

  void recordComment(AppMessage message) {
    _totalCommentCount += 1;

    final String? userId = message.userId;
    if (userId != null && userId.isNotEmpty) {
      final DateTime timestamp = message.timestamp;
      final DateTime? latestTimestamp = _latestActivityByUser[userId];
      if (latestTimestamp == null || timestamp.isAfter(latestTimestamp)) {
        _latestActivityByUser[userId] = timestamp;
      }
      _ensurePurgeTimer();
    }

    notifyListeners();
  }

  void updateViewerCount(int? count) {
    if (_viewerCount == count) {
      return;
    }
    _viewerCount = count;
    notifyListeners();
  }

  void reset() {
    _totalCommentCount = 0;
    _viewerCount = null;
    _latestActivityByUser.clear();
    _cancelPurgeTimer();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelPurgeTimer();
    super.dispose();
  }

  void _ensurePurgeTimer() {
    if (_disposed || _purgeTimer != null) {
      return;
    }
    _purgeTimer = Timer.periodic(_purgeInterval, (_) => _onPurgeTick());
  }

  void _cancelPurgeTimer() {
    _purgeTimer?.cancel();
    _purgeTimer = null;
  }

  void _onPurgeTick() {
    if (_disposed) {
      _cancelPurgeTimer();
      return;
    }

    final int countBefore = _latestActivityByUser.length;
    _purgeExpired();
    final int countAfter = _latestActivityByUser.length;

    if (countAfter == 0) {
      _cancelPurgeTimer();
    }

    if (countBefore != countAfter) {
      notifyListeners();
    }
  }

  void _purgeExpired() {
    final DateTime cutoff = _now().subtract(_activeWindow);
    _latestActivityByUser.removeWhere(
      (_, timestamp) => timestamp.isBefore(cutoff),
    );
  }
}
