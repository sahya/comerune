import 'dart:collection';
import 'dart:developer';

import '../models/app_message.dart';

const int kDefaultSpeechQueueLimit = 20;
const Duration kDefaultSpeechMaxDelay = Duration(seconds: 10);
const Duration kFloodSuppressionWindow = Duration(seconds: 1);

class SpeechQueueItem {
  const SpeechQueueItem({
    required this.messageId,
    required this.messageTimestamp,
    required this.userId,
    required this.text,
  });

  final String messageId;
  final DateTime messageTimestamp;
  final String? userId;
  final String text;
}

class SpeechQueueController {
  SpeechQueueController({
    int queueLimit = kDefaultSpeechQueueLimit,
    Duration maxDelay = kDefaultSpeechMaxDelay,
    bool autoReadEnabled = true,
    List<String> ngWordPatterns = const <String>[],
    DateTime Function()? nowProvider,
  })  : _queueLimit = queueLimit,
        _maxDelay = maxDelay,
        _autoReadEnabled = autoReadEnabled,
        _nowProvider = nowProvider ?? DateTime.now {
    if (queueLimit < 1) {
      throw ArgumentError.value(queueLimit, 'queueLimit', 'must be at least 1');
    }
    if (maxDelay < Duration.zero) {
      throw ArgumentError.value(maxDelay, 'maxDelay', 'must not be negative');
    }

    setNgWordPatterns(ngWordPatterns);
  }

  final Queue<SpeechQueueItem> _queue = Queue<SpeechQueueItem>();
  final Map<String, DateTime> _lastAcceptedAtByUserId = <String, DateTime>{};
  final DateTime Function() _nowProvider;
  // Optional review note:
  // Keep URL detection simple for v1.2; trailing punctuation may be consumed.
  // If readability impact is observed, narrow this pattern in a follow-up.
  final RegExp _urlPattern = RegExp(r'https?:\/\/\S+');

  int _queueLimit;
  Duration _maxDelay;
  bool _autoReadEnabled;
  List<RegExp> _compiledNgWordPatterns = <RegExp>[];

  int get queueLimit => _queueLimit;
  Duration get maxDelay => _maxDelay;
  bool get autoReadEnabled => _autoReadEnabled;
  int get length => _queue.length;
  bool get isEmpty => _queue.isEmpty;

  List<SpeechQueueItem> get items => List<SpeechQueueItem>.unmodifiable(_queue);

  void setAutoReadEnabled(bool enabled) {
    _autoReadEnabled = enabled;
  }

  void setQueueLimit(int limit) {
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'must be at least 1');
    }
    _queueLimit = limit;
    _enforceQueueLimit();
  }

  void setMaxDelay(Duration delay) {
    if (delay < Duration.zero) {
      throw ArgumentError.value(delay, 'delay', 'must not be negative');
    }
    _maxDelay = delay;
    _discardExpired(_nowProvider());
  }

  void setNgWordPatterns(List<String> patterns) {
    final List<RegExp> compiled = <RegExp>[];
    for (final String pattern in patterns) {
      try {
        compiled.add(RegExp(pattern));
      } on FormatException catch (error) {
        log(
          'Ignoring invalid NG word pattern: $pattern ($error)',
          name: 'SpeechQueueController',
        );
      }
    }
    _compiledNgWordPatterns = compiled;
  }

  bool enqueue(AppMessage message) {
    final DateTime nowAt = _nowProvider();
    _discardExpired(nowAt);
    _pruneOldFloodHistory(nowAt);

    if (!_autoReadEnabled) {
      return false;
    }
    if (_isLegacyUnsupportedFormat(message)) {
      return false;
    }
    if (_isFloodMessage(message)) {
      return false;
    }

    if (_matchesNgWord(message.content)) {
      return false;
    }
    final String normalizedText = _replaceUrls(message.content);
    if (_isExpired(message.timestamp, nowAt)) {
      return false;
    }

    _queue.add(
      SpeechQueueItem(
        messageId: message.id,
        messageTimestamp: message.timestamp,
        userId: message.userId,
        text: normalizedText,
      ),
    );
    _rememberAcceptedMessage(message);
    _enforceQueueLimit();
    return true;
  }

  SpeechQueueItem? dequeue() {
    _discardExpired(_nowProvider());
    if (_queue.isEmpty) {
      return null;
    }
    return _queue.removeFirst();
  }

  void clear() {
    _queue.clear();
    _lastAcceptedAtByUserId.clear();
  }

  bool _isLegacyUnsupportedFormat(AppMessage message) {
    // Optional review note:
    // v1.2 uses shared fallback text as the compatibility signal.
    // If a dedicated marker (e.g. raw.kind) becomes stable, switch to it.
    return message.content == kLegacyUnsupportedFormatMessage;
  }

  bool _isFloodMessage(AppMessage message) {
    final String? userId = message.userId;
    if (userId == null || userId.isEmpty) {
      return false;
    }

    final DateTime? lastAcceptedAt = _lastAcceptedAtByUserId[userId];
    if (lastAcceptedAt == null) {
      return false;
    }

    final Duration interval = message.timestamp.difference(lastAcceptedAt);
    return !interval.isNegative && interval <= kFloodSuppressionWindow;
  }

  void _rememberAcceptedMessage(AppMessage message) {
    final String? userId = message.userId;
    if (userId == null || userId.isEmpty) {
      return;
    }
    _lastAcceptedAtByUserId[userId] = message.timestamp;
  }

  void _pruneOldFloodHistory(DateTime now) {
    _lastAcceptedAtByUserId.removeWhere((String _, DateTime acceptedAt) {
      final Duration age = now.difference(acceptedAt);
      return !age.isNegative && age > kFloodSuppressionWindow;
    });
  }

  String _replaceUrls(String content) {
    return content.replaceAll(_urlPattern, 'URL');
  }

  bool _matchesNgWord(String content) {
    for (final RegExp pattern in _compiledNgWordPatterns) {
      if (pattern.hasMatch(content)) {
        return true;
      }
    }
    return false;
  }

  void _discardExpired(DateTime now) {
    final Queue<SpeechQueueItem> retained = Queue<SpeechQueueItem>();
    while (_queue.isNotEmpty) {
      final SpeechQueueItem item = _queue.removeFirst();
      if (_isExpired(item.messageTimestamp, now)) {
        continue;
      }
      retained.add(item);
    }
    while (retained.isNotEmpty) {
      _queue.add(retained.removeFirst());
    }
  }

  void _enforceQueueLimit() {
    while (_queue.length > _queueLimit) {
      _queue.removeFirst();
    }
  }

  bool _isExpired(DateTime timestamp, DateTime now) {
    final Duration delay = now.difference(timestamp);
    return !delay.isNegative && delay > _maxDelay;
  }
}
