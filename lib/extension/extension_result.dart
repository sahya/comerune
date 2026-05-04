/// Outcome of an extension service invocation.
///
/// All values returned across the host / extension boundary are wrapped
/// in [ExtensionResult] so the host never has to defend against
/// uncaught exceptions or "missing extension" sentinels at every call
/// site. Pattern-match exhaustively to handle every case.
sealed class ExtensionResult<T> {
  const ExtensionResult();
}

/// The extension produced a normal value.
final class ExtensionResultOk<T> extends ExtensionResult<T> {
  const ExtensionResultOk(this.value);

  final T value;

  @override
  bool operator ==(Object other) =>
      other is ExtensionResultOk<T> && other.value == value;

  @override
  int get hashCode => Object.hash(ExtensionResultOk<T>, value);

  @override
  String toString() => 'ExtensionResultOk($value)';
}

/// No extension is registered for the requested capability, or the
/// extension explicitly reported "not supported" for the given input.
///
/// Call sites should respond by either falling back to a host
/// implementation (when [ServiceOverridePolicy] permits it) or by
/// surfacing a "feature unavailable" UX.
final class ExtensionResultUnsupported<T> extends ExtensionResult<T> {
  const ExtensionResultUnsupported();

  @override
  bool operator ==(Object other) => other is ExtensionResultUnsupported<T>;

  @override
  int get hashCode => (ExtensionResultUnsupported<T>).hashCode;

  @override
  String toString() => 'ExtensionResultUnsupported()';
}

/// The extension threw an exception while handling the call.
///
/// [cause] is the original exception captured at the boundary and is
/// always preserved in this object — the host's defensive logger
/// (`logExtensionDiagnostic` in `_logging.dart`) sanitises it for
/// log output (debug: full error; release: dropped), but the field
/// itself is unconditionally readable.
///
/// **Callers must not log [cause] directly.** Doing so bypasses the
/// release-mode sanitisation and could leak integration-specific
/// exception class names or messages into platform logs (logcat /
/// Console). If a caller needs to surface failure information, it
/// should either:
/// - emit its own generic message via `logExtensionDiagnostic`; or
/// - pattern-match on `cause` to extract specific safe details
///   (e.g. an `int` error code), without printing the object itself.
///
/// Call sites that simply want to fall back to a host UX should
/// treat this similarly to [ExtensionResultUnsupported].
final class ExtensionResultFailure<T> extends ExtensionResult<T> {
  const ExtensionResultFailure(this.cause);

  final Object cause;

  @override
  bool operator ==(Object other) =>
      other is ExtensionResultFailure<T> && other.cause == cause;

  @override
  int get hashCode => Object.hash(ExtensionResultFailure<T>, cause);

  @override
  String toString() => 'ExtensionResultFailure($cause)';
}
