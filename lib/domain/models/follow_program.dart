import '../utils/elapsed_formatter.dart';

/// Status of a niconico live program.
enum ProgramStatus {
  /// Program is scheduled but not yet started.
  reserved,

  /// Program is in test/preview mode.
  test,

  /// Program is actively broadcasting.
  onAir,

  /// Program has ended.
  ended,
}

/// Parses a status string from the API into a [ProgramStatus].
///
/// Returns `null` for unrecognised values.
ProgramStatus? parseProgramStatus(String? status) {
  switch (status) {
    case 'reserved':
      return ProgramStatus.reserved;
    case 'test':
      return ProgramStatus.test;
    case 'on_air':
    case 'onAir':
      return ProgramStatus.onAir;
    case 'end':
    case 'ended':
      return ProgramStatus.ended;
    default:
      return null;
  }
}

/// A live program from a followed broadcaster on niconico.
class FollowProgram {
  FollowProgram({
    required this.programId,
    required this.title,
    required this.providerName,
    this.providerIconUrl,
    String? communityName,
    this.beginAt,
    this.endAt,
    this.isOwnBroadcast = false,
    this.status,
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

  /// When the broadcast is scheduled to end.
  final DateTime? endAt;

  /// Whether this program is the logged-in user's own broadcast.
  final bool isOwnBroadcast;

  /// Current status of the program.
  final ProgramStatus? status;

  /// Whether the broadcast can be started (reserved or test state).
  bool get canStart =>
      status == ProgramStatus.reserved || status == ProgramStatus.test;

  /// Whether the broadcast can be ended (currently on air).
  bool get canEnd => status == ProgramStatus.onAir;

  /// Returns an elapsed time string in `H:MM:SS` format, or null if
  /// [beginAt] is null or in the future.
  String? elapsedLabel() => formatElapsed(beginAt);

  /// Returns a copy with updated fields.
  FollowProgram copyWith({ProgramStatus? status, DateTime? endAt}) {
    return FollowProgram(
      programId: programId,
      title: title,
      providerName: providerName,
      providerIconUrl: providerIconUrl,
      communityName: communityName,
      beginAt: beginAt,
      endAt: endAt ?? this.endAt,
      isOwnBroadcast: isOwnBroadcast,
      status: status ?? this.status,
    );
  }
}
