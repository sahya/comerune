import '../../domain/utils/elapsed_formatter.dart';

/// A live program from a followed broadcaster on niconico.
class FollowProgram {
  FollowProgram({
    required this.programId,
    required this.title,
    required this.providerName,
    this.providerIconUrl,
    String? communityName,
    this.beginAt,
  }) : communityName = (communityName != null && communityName.isNotEmpty)
            ? communityName
            : null;

  /// The program ID (e.g., "lv348712105").
  final String programId;

  /// The broadcast title.
  final String title;

  /// The broadcaster's display name.
  final String providerName;

  /// The broadcaster's icon URL (small, typically 50x50).
  final String? providerIconUrl;

  /// The community or channel name, if available.
  final String? communityName;

  /// When the broadcast started (ISO 8601 or Unix timestamp from API).
  final DateTime? beginAt;

  /// Returns an elapsed time string in `H:MM:SS` format, or null if
  /// [beginAt] is null or in the future.
  String? elapsedLabel() => formatElapsed(beginAt);
}
