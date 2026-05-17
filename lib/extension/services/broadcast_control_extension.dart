import '../extension_result.dart';

/// Optional integration point for broadcast-control capabilities the
/// host cannot provide on its own.
///
/// The host exposes no built-in implementation: when no extension is
/// registered, every method returns [ExtensionResultUnsupported] and
/// call sites hide the related affordances. Concrete behaviour comes
/// entirely from an integration package distributed under
/// `integrations/<name>/`.
///
/// Implementations must:
/// - Never throw across this boundary; surface failures via
///   [ExtensionResultFailure] so the host's defensive logger can
///   sanitise them in release builds.
/// - Return [ExtensionResultUnsupported] when a request cannot be
///   serviced for non-error reasons (capability not implemented,
///   not applicable to the current session, etc.) so the host can
///   fall back to its own UX without distinguishing failure modes.
abstract class BroadcastControlExtension {
  const BroadcastControlExtension();

  /// Request that the active broadcast be extended by [by] from its
  /// current scheduled end. Returns [ExtensionResultOk] with `null`
  /// payload on success.
  ///
  /// The host does not interpret [by] beyond passing it through; the
  /// extension is responsible for clamping or rejecting durations its
  /// backing service does not accept.
  Future<ExtensionResult<void>> extendBroadcast({required Duration by});
}
