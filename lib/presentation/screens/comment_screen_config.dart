import 'package:meta/meta.dart';

import '../../domain/connection/connection_method.dart';

/// Program-level metadata for the comment screen.
@immutable
class CommentProgramInfo {
  const CommentProgramInfo({
    required this.lv,
    this.programTitle,
    this.broadcasterName,
    this.broadcasterUserId,
    this.broadcasterIconUrl,
    this.beginAt,
    this.connectionMethod,
  });

  /// The live program ID (e.g. "lv348712105").
  final String lv;

  /// The broadcast title.
  final String? programTitle;

  /// The broadcaster's display name.
  final String? broadcasterName;

  /// The broadcaster's user ID.
  final String? broadcasterUserId;

  /// The broadcaster's icon URL.
  final String? broadcasterIconUrl;

  /// When the broadcast started.
  final DateTime? beginAt;

  /// The connection method used to connect to the program.
  final ConnectionMethod? connectionMethod;
}

/// Statistics display configuration and live data.
@immutable
class CommentStatisticsConfig {
  const CommentStatisticsConfig({
    this.enabled = false,
    this.viewerCommentEnabled = true,
    this.activeUserEnabled = true,
    this.highlightPickupEnabled = false,
    this.viewerCount,
    this.totalCommentCount = 0,
    this.activeUserCount = 0,
  });

  /// Whether statistics display is enabled.
  final bool enabled;

  /// Whether viewer/comment count is shown.
  final bool viewerCommentEnabled;

  /// Whether active user count is shown.
  final bool activeUserEnabled;

  /// Whether highlight pickup is shown at broadcast end.
  final bool highlightPickupEnabled;

  /// Current viewer count (null when unavailable).
  final int? viewerCount;

  /// Total number of comments received.
  final int totalCommentCount;

  /// Number of active users in recent window.
  final int activeUserCount;
}
