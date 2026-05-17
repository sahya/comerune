import 'package:flutter/widgets.dart';

import 'extension_registry.dart';

/// Inherited widget that exposes the host's [ExtensionRegistry] to the
/// widget tree.
///
/// Mounted once near the top of the app (typically wrapping
/// `MaterialApp`) so any descendant — slot widgets, screens that need
/// to look up service contracts — can read the registry without
/// passing it down through constructors.
///
/// The registry instance is expected to be stable for the lifetime of
/// the app: extensions register during startup via
/// `ExtensionLoader.loadAll`, the registry is then frozen, and
/// thereafter only read. [updateShouldNotify] uses identity equality
/// because the typical case is a single registry per app session — a
/// new registry instance signals a genuine bootstrap restart.
class ExtensionScope extends InheritedWidget {
  const ExtensionScope({
    super.key,
    required this.registry,
    required super.child,
  });

  final ExtensionRegistry registry;

  /// Look up the registry, throwing if the scope is missing.
  ///
  /// Use this from code that fundamentally requires the registry
  /// (slot composition helpers, etc.). For widgets that should
  /// degrade gracefully when no registry has been mounted, prefer
  /// [maybeOf].
  static ExtensionRegistry of(BuildContext context) {
    final ExtensionScope? scope = context
        .dependOnInheritedWidgetOfExactType<ExtensionScope>();
    assert(
      scope != null,
      'ExtensionScope.of() called with a context that does not contain an '
      'ExtensionScope. Mount one near the top of the app (typically wrapping '
      'MaterialApp) so descendants can resolve the optional-integration '
      'registry.',
    );
    return scope!.registry;
  }

  /// Look up the registry, returning `null` when the scope is missing.
  ///
  /// Useful in tests and isolated screens that may be inflated outside
  /// the app shell.
  static ExtensionRegistry? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ExtensionScope>()
        ?.registry;
  }

  @override
  bool updateShouldNotify(ExtensionScope oldWidget) =>
      !identical(registry, oldWidget.registry);
}
