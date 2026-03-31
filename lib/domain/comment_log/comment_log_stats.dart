import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../models/app_message.dart';

/// A detected peak period with representative comments.
@immutable
class HighlightPeak {
  const HighlightPeak({
    required this.minuteOffset,
    required this.label,
    required this.commentCount,
    required this.representativeComments,
  });

  /// Minute offset from broadcast start.
  final int minuteOffset;

  /// Human-readable label (e.g. "開始25分").
  final String label;

  /// Number of comments in this peak minute.
  final int commentCount;

  /// Up to 3 representative comments from this peak minute.
  final List<AppMessage> representativeComments;
}

/// Statistics summary computed from a list of [AppMessage].
///
/// All fields are derived from the provided messages at construction time.
/// The calculator is a pure function with no side effects.
class CommentLogStats {
  CommentLogStats({
    required this.totalComments,
    required this.uniqueUserCount,
    required this.duration,
    required this.peakMinuteLabel,
    required this.peakMinuteCount,
    required this.commentsPerMinute,
  });

  /// Calculates statistics from the given [messages].
  ///
  /// Only [AppMessageType.chat], [AppMessageType.operator], and
  /// [AppMessageType.notification] messages are counted (consistent with the
  /// display filter in CommentScreen). Gift and nicoad types are excluded.
  ///
  /// [ngUserIds] excludes messages from blocked users, matching the display
  /// filter.
  factory CommentLogStats.fromMessages(
    List<AppMessage> messages, {
    Set<String> ngUserIds = const <String>{},
  }) {
    final List<AppMessage> filtered = _filterDisplayable(
      messages,
      ngUserIds: ngUserIds,
    );

    if (filtered.isEmpty) {
      return CommentLogStats(
        totalComments: 0,
        uniqueUserCount: 0,
        duration: Duration.zero,
        peakMinuteLabel: null,
        peakMinuteCount: 0,
        commentsPerMinute: <int, int>{},
      );
    }

    // Unique users
    final Set<String> users = <String>{};
    for (final AppMessage m in filtered) {
      if (m.userId != null && m.userId!.isNotEmpty) {
        users.add(m.userId!);
      }
    }

    // Duration: first message to last message
    final DateTime first = filtered.first.timestamp;
    final DateTime last = filtered.last.timestamp;
    final Duration duration =
        last.isAfter(first) ? last.difference(first) : Duration.zero;

    // Comments per minute (minute offset from first message)
    final Map<int, int> commentsPerMinute = <int, int>{};
    for (final AppMessage m in filtered) {
      final int minuteOffset = m.timestamp.difference(first).inMinutes;
      commentsPerMinute[minuteOffset] =
          (commentsPerMinute[minuteOffset] ?? 0) + 1;
    }

    // Peak minute
    int peakMinute = 0;
    int peakCount = 0;
    for (final MapEntry<int, int> entry in commentsPerMinute.entries) {
      if (entry.value > peakCount) {
        peakMinute = entry.key;
        peakCount = entry.value;
      }
    }

    return CommentLogStats(
      totalComments: filtered.length,
      uniqueUserCount: users.length,
      duration: duration,
      peakMinuteLabel: _formatPeakLabel(peakMinute),
      peakMinuteCount: peakCount,
      commentsPerMinute: commentsPerMinute,
    );
  }

  /// Total number of displayable comments.
  final int totalComments;

  /// Number of distinct user IDs.
  final int uniqueUserCount;

  /// Duration between first and last message.
  final Duration duration;

  /// Human-readable label for the peak minute (e.g. "25分").
  final String? peakMinuteLabel;

  /// Number of comments in the peak minute.
  final int peakMinuteCount;

  /// Comments per minute offset from the first message.
  ///
  /// Exposed so that issue #120 (frequency graph) can reuse the same data
  /// without re-calculating.
  final Map<int, int> commentsPerMinute;

  /// Formats the stats as a shareable plain-text summary.
  String toShareText({String? programTitle, String? lv}) {
    final StringBuffer buffer = StringBuffer();

    if (programTitle != null && programTitle.isNotEmpty) {
      buffer.writeln(programTitle);
    }
    if (lv != null && lv.isNotEmpty) {
      buffer.writeln(lv);
    }
    if (buffer.isNotEmpty) {
      buffer.writeln();
    }

    buffer.writeln('コメント統計サマリ');
    buffer.writeln('総コメント数: $totalComments');
    buffer.writeln('ユニークユーザー数: $uniqueUserCount');
    buffer.writeln('配信時間: ${formatDuration(duration)}');
    if (peakMinuteLabel != null && peakMinuteCount > 0) {
      buffer.writeln('ピーク時間帯: $peakMinuteLabel ($peakMinuteCountコメント)');
    }

    return buffer.toString().trimRight();
  }

  /// Formats a [Duration] as "X時間Y分" or "Y分".
  static String formatDuration(Duration duration) {
    final int totalMinutes = duration.inMinutes;
    if (totalMinutes < 1) {
      return '1分未満';
    }
    final int hours = totalMinutes ~/ 60;
    final int minutes = totalMinutes % 60;
    if (hours == 0) {
      return '$minutes分';
    }
    if (minutes == 0) {
      return '$hours時間';
    }
    return '$hours時間$minutes分';
  }

  /// Detects the top peak minutes from [messages] using [commentsPerMinute].
  ///
  /// A peak is a minute whose comment count exceeds the mean + 1 standard
  /// deviation. Returns up to [maxPeaks] peaks sorted by comment count
  /// descending. Each peak includes up to 3 representative comments.
  static List<HighlightPeak> detectPeaks(
    List<AppMessage> messages, {
    required Map<int, int> commentsPerMinute,
    Set<String> ngUserIds = const <String>{},
    int maxPeaks = 3,
  }) {
    if (commentsPerMinute.isEmpty) {
      return const <HighlightPeak>[];
    }

    final List<int> counts = commentsPerMinute.values.toList();
    final double mean =
        counts.fold<int>(0, (int a, int b) => a + b) / counts.length;
    double variance = 0;
    for (final int c in counts) {
      variance += (c - mean) * (c - mean);
    }
    variance /= counts.length;
    final double stddev = variance > 0 ? math.sqrt(variance) : 0;
    final double threshold = mean + stddev;

    // Minimum threshold: at least 2 comments/minute to be a peak.
    final double effectiveThreshold = threshold < 2 ? 2 : threshold;

    final List<MapEntry<int, int>> candidates = commentsPerMinute.entries
        .where((MapEntry<int, int> e) => e.value >= effectiveThreshold)
        .toList()
      ..sort((MapEntry<int, int> a, MapEntry<int, int> b) =>
          b.value.compareTo(a.value));

    if (candidates.isEmpty) {
      return const <HighlightPeak>[];
    }

    // Filter messages once.
    final List<AppMessage> filtered = _filterDisplayable(
      messages,
      ngUserIds: ngUserIds,
    );

    if (filtered.isEmpty) {
      return const <HighlightPeak>[];
    }

    final DateTime first = filtered.first.timestamp;

    // Group filtered messages by minute offset.
    final Map<int, List<AppMessage>> messagesByMinute =
        <int, List<AppMessage>>{};
    for (final AppMessage m in filtered) {
      final int minute = m.timestamp.difference(first).inMinutes;
      messagesByMinute.putIfAbsent(minute, () => <AppMessage>[]).add(m);
    }

    final List<HighlightPeak> peaks = <HighlightPeak>[];
    for (final MapEntry<int, int> entry in candidates.take(maxPeaks)) {
      final List<AppMessage> minuteMessages =
          messagesByMinute[entry.key] ?? const <AppMessage>[];
      peaks.add(HighlightPeak(
        minuteOffset: entry.key,
        label: _formatPeakLabel(entry.key),
        commentCount: entry.value,
        representativeComments: minuteMessages.take(3).toList(growable: false),
      ));
    }

    return peaks;
  }

  /// Filters out gift/nicoad messages and messages from NG users.
  static List<AppMessage> _filterDisplayable(
    List<AppMessage> messages, {
    Set<String> ngUserIds = const <String>{},
  }) {
    return messages.where((AppMessage m) {
      if (m.type == AppMessageType.gift || m.type == AppMessageType.nicoad) {
        return false;
      }
      final String? userId = m.userId;
      if (userId != null && ngUserIds.contains(userId)) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  static String _formatPeakLabel(int minuteOffset) {
    if (minuteOffset < 60) {
      return '開始${minuteOffset}分';
    }
    final int hours = minuteOffset ~/ 60;
    final int minutes = minuteOffset % 60;
    if (minutes == 0) {
      return '開始${hours}時間';
    }
    return '開始${hours}時間${minutes}分';
  }
}
