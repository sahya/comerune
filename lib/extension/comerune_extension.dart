import 'extension_registry.dart';

/// Contract version surfaced to extensions.
///
/// Bump this when the `ComeruneExtension` / `ExtensionRegistry` surface
/// changes in a backward-incompatible way. Extensions can read this
/// constant at compile time to refuse to load against an unsupported
/// host. The host loader does NOT currently enforce a minimum version;
/// the value exists so that future versions can.
const int kComeruneExtensionContractVersion = 1;

/// Implemented by every extension entry point.
///
/// An extension's package must export a top-level function with the
/// signature `ComeruneExtension createExtension()`. The host's
/// generated registry calls that factory once at startup and invokes
/// [register] on the returned instance.
///
/// Implementations should keep [register] cheap and side-effect free
/// beyond the calls it makes on the provided [ExtensionRegistry];
/// long-running initialisation should happen lazily inside the
/// services or widgets that get registered.
abstract class ComeruneExtension {
  const ComeruneExtension();

  /// Register services and / or slot widgets with the host.
  ///
  /// Throwing from this method does not crash the host; the loader
  /// catches the exception, logs a generic diagnostic, and continues
  /// loading remaining extensions. Implementations should still avoid
  /// throwing — partial registration may leave the extension in an
  /// inconsistent state.
  void register(ExtensionRegistry registry);
}
