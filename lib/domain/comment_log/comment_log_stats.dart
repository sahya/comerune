import '../models/app_message.dart';

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
    final List<AppMessage> filtered = messages.where((AppMessage m) {
      if (m.type == AppMessageType.gift || m.type == AppMessageType.nicoad) {
        return false;
      }
      final String? userId = m.userId;
      if (userId != null && ngUserIds.contains(userId)) {
        return false;
      }
      return true;
    }).toList(growable: false);

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
