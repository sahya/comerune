/// Builds a niconico user icon URL from a numeric user ID.
///
/// Returns `null` for null/empty/non-numeric IDs.
String? buildNicoIconUrl(String? userId) {
  if (userId == null || userId.isEmpty) {
    return null;
  }
  final int? numericId = int.tryParse(userId);
  if (numericId == null || numericId <= 0) {
    return null;
  }
  final int prefix = numericId ~/ 10000;
  return 'https://secure-dcdn.cdn.nimg.jp/nicoaccount/usericon/$prefix/$numericId.jpg';
}
