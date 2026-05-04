import 'package:flutter/foundation.dart';

import '../app_logging.dart';
import 'comerune_extension.dart';
import 'extension_registry.dart';
import 'generated/registry.g.dart';

/// Type alias for the per-extension factory function emitted into the
/// generated registry.
typedef ExtensionFactory = ComeruneExtension Function();

/// Loads optional integrations into an [ExtensionRegistry] without ever
/// letting a misbehaving integration crash the host.
///
/// The loader iterates a list of factory functions (defaulting to the
/// generated `kExtensionFactories` list) and, for each one, runs the
/// factory and calls `register` inside a single try/catch. Any failure
/// is logged with a generic diagnostic and the remaining factories
/// continue to run. The registry is exposed via [registry] so the host
/// can wire it into the widget tree after `loadAll` completes.
class ExtensionLoader {
  /// Construct a loader.
  ///
  /// The optional [registry] argument is for tests; production code
  /// uses the default which creates a fresh empty registry.
  ///
  /// The optional [factories] argument lets tests inject a controlled
  /// set of factories (including ones that throw) without touching the
  /// generated file. Production code uses the default which reads from
  /// the generated registry.
  ExtensionLoader({
    ExtensionRegistry? registry,
    List<ExtensionFactory>? factories,
  }) : _registry = registry ?? ExtensionRegistry(),
       _factories = factories ?? kExtensionFactories;

  final ExtensionRegistry _registry;
  final List<ExtensionFactory> _factories;

  /// The registry populated by [loadAll]. Safe to read before
  /// [loadAll] completes (it will simply be empty).
  ExtensionRegistry get registry => _registry;

  /// Run every factory and register the resulting extension.
  ///
  /// Defensive guarantees:
  /// - One factory throwing does not stop the others.
  /// - One extension's `register` throwing does not stop the others.
  /// - Diagnostics never include endpoint URLs, secret values, or
  ///   integration-specific identifiers — only a generic
  ///   "optional integration unavailable" message.
  ///
  /// The detailed cause is only emitted in debug builds via
  /// `appErrorLog`, which strips the error to its `runtimeType` in
  /// release builds.
  Future<void> loadAll() async {
    for (final ExtensionFactory factory in _factories) {
      ComeruneExtension extension;
      try {
        extension = factory();
      } catch (error, stackTrace) {
        _logUnavailable('factory', error, stackTrace);
        continue;
      }
      try {
        extension.register(_registry);
      } catch (error, stackTrace) {
        _logUnavailable('register', error, stackTrace);
      }
    }
    // Lock the registry so any late `register*` call (e.g. from a
    // misbehaving extension that schedules a Timer) is observed and
    // ignored rather than silently mutating the runtime configuration.
    _registry.freeze();
  }

  // Logger name in debug includes the subsystem for greppability;
  // release builds emit only the generic 'comerune' name so that
  // platform logs (logcat / Console) do not advertise the existence
  // of an optional-integration subsystem.
  static const String _logName = kDebugMode ? 'comerune.extension' : 'comerune';

  void _logUnavailable(String stage, Object error, StackTrace stackTrace) {
    appErrorLog(
      name: _logName,
      message: 'optional integration unavailable',
      error: kDebugMode ? error : null,
      stackTrace: kDebugMode ? stackTrace : null,
    );
    // Stage is intentionally only logged in debug to keep release logs
    // free of integration-specific surface area. `assert` is stripped
    // from release builds.
    assert(() {
      debugPrint('[extension-loader] stage=$stage error=$error');
      return true;
    }());
  }
}
