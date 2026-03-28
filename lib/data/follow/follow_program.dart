/// A live program from a followed broadcaster on niconico.
class FollowProgram {
  FollowProgram({
    required this.programId,
    required this.title,
    required this.providerName,
    this.providerIconUrl,
    String? communityName,
    this.beginAt,
  }) : communityName =
            (communityName != null && communityName.isNotEmpty)
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

  /// Returns a human-readable elapsed time string (e.g., "15分", "1時間23分").
  String? elapsedLabel() {
    final DateTime? start = beginAt;
    if (start == null) {
      return null;
    }

    final Duration elapsed = DateTime.now().difference(start);
    if (elapsed.isNegative) {
      return null;
    }

    final int totalMinutes = elapsed.inMinutes;
    if (totalMinutes < 1) {
      return '開始直後';
    }
    if (totalMinutes < 60) {
      return '$totalMinutes分';
    }

    final int hours = totalMinutes ~/ 60;
    final int minutes = totalMinutes % 60;
    if (minutes == 0) {
      return '$hours時間';
    }
    return '$hours時間$minutes分';
  }
}
