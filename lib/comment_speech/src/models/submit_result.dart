/// Result of submitting a comment for speech synthesis.
class SubmitResult {
  final bool accepted;
  final bool skipped;
  final String? normalizedText;
  final String? skipReason;
  final int queueSize;

  const SubmitResult({
    required this.accepted,
    required this.skipped,
    this.normalizedText,
    this.skipReason,
    required this.queueSize,
  });

  factory SubmitResult.fromMap(Map<String, dynamic> map) => SubmitResult(
        accepted: map['accepted'] as bool,
        skipped: map['skipped'] as bool,
        normalizedText: map['normalizedText'] as String?,
        skipReason: map['skipReason'] as String?,
        queueSize: map['queueSize'] as int,
      );
}
