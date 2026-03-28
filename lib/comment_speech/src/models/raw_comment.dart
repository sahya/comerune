/// A comment received from the live stream before normalization.
class RawComment {
  final String id;
  final String text;
  final String? userId;
  final int postedAtEpochMs;
  final int? score;
  final bool isOwner;

  const RawComment({
    required this.id,
    required this.text,
    this.userId,
    required this.postedAtEpochMs,
    this.score,
    this.isOwner = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'text': text,
        'userId': userId,
        'postedAtEpochMs': postedAtEpochMs,
        'score': score,
        'isOwner': isOwner,
      };
}
