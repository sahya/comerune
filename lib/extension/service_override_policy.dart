/// Resolution strategy used when a host call site has both a host
/// implementation and (optionally) an extension implementation.
enum ServiceOverridePolicy {
  /// Always invoke the host implementation. Any registered extension is
  /// ignored. Used as a "kill switch" for development / debugging.
  hostOnly,

  /// Invoke the host implementation first; if it signals "unsupported"
  /// (per the contract of the call site), fall back to the extension.
  hostFirstFallback,

  /// Invoke the extension first; if no extension is registered or it
  /// returns an unsupported / failure result, fall back to the host
  /// implementation. This is the default for service contracts that
  /// represent capabilities the host can only partially provide.
  extensionFirstFallback,

  /// Only invoke the extension. The host has no implementation; if the
  /// extension is absent the call site reports "unsupported" to its
  /// caller. Used for service contracts where the host genuinely cannot
  /// provide an implementation.
  extensionOnly,
}
