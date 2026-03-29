import 'package:flutter/foundation.dart';

import '../../domain/models/app_message.dart';

class StatisticsStore extends ChangeNotifier {
  StatisticsStore({
    Duration activeWindow = const Duration(minutes: 5),
    DateTime Function()? now,
  })  : _activeWindow = activeWindow,
        _now = now ?? DateTime.now;

  final Duration _activeWindow;
  final DateTime Function() _now;

  int _totalCommentCount = 0;
  int? _viewerCount;
  final List<_TimestampedUserId> _recentUserEvents = <_TimestampedUserId>[];

  int get totalCommentCount => _totalCommentCount;
  int? get viewerCount => _viewerCount;

  int get activeUserCount {
    _pruneExpired();
    final Set<String> uniqueIds = <String>{};
    for (final _TimestampedUserId entry in _recentUserEvents) {
      uniqueIds.add(entry.userId);
    }
    return uniqueIds.length;
  }

  void recordComment(AppMessage message) {
    _totalCommentCount += 1;

    final String? userId = message.userId;
    if (userId != null && userId.isNotEmpty) {
      _recentUserEvents.add(
        _TimestampedUserId(userId: userId, timestamp: _now()),
      );
      // Prune periodically to avoid unbounded growth during long streams.
      if (_totalCommentCount % 100 == 0) {
        _pruneExpired();
      }
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
    _recentUserEvents.clear();
    notifyListeners();
  }

  void _pruneExpired() {
    final DateTime cutoff = _now().subtract(_activeWindow);
    _recentUserEvents.removeWhere(
      (_TimestampedUserId entry) => entry.timestamp.isBefore(cutoff),
    );
  }
}

class _TimestampedUserId {
  const _TimestampedUserId({
    required this.userId,
    required this.timestamp,
  });

  final String userId;
  final DateTime timestamp;
}
