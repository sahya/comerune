/// Issue #727: shared broadcaster-ID redaction for developer-log output.
///
/// All filter-related code paths (migrator, codec, store) share this
/// helper so error messages emitted to device logs / crash reports never
/// carry the full broadcaster ID. Keeping it in one file ensures the
/// redaction policy is consistent across PRs.

/// Number of leading characters of a broadcaster ID kept verbatim in
/// redacted log output. Anything past this prefix is replaced with
/// `***`.
const int redactBroadcasterIdPrefixLength = 4;

/// Returns a short prefix-only form of [broadcasterId] suitable for
/// developer-log output.
///
/// IDs shorter than [redactBroadcasterIdPrefixLength] are reported as
/// `***` only — never returning enough material to recover the full ID.
String redactBroadcasterId(String broadcasterId) {
  if (broadcasterId.length > redactBroadcasterIdPrefixLength) {
    return '${broadcasterId.substring(0, redactBroadcasterIdPrefixLength)}***';
  }
  return '***';
}
