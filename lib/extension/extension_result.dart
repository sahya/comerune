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
/// [cause] is preserved for debug-mode logging only; release-build
/// loggers strip it to its `runtimeType` to avoid leaking
/// integration-specific surface area into platform logs. Call sites
/// should treat this similarly to [ExtensionResultUnsupported] but may
/// elect to surface a generic error to the user.
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
