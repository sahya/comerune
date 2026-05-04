import 'package:flutter/widgets.dart';

import 'slot_ids.dart';

/// Holds the runtime state populated by registered extensions.
///
/// Two kinds of registrations are supported:
///
/// 1. **Services** — a single value of a given Dart type. Look-up via
///    [service] returns `null` when no extension has registered that
///    type, so call sites can apply policy (see
///    `service_override_policy.dart`) without throwing.
/// 2. **Slot widgets** — zero-or-more widgets keyed by a [SlotId].
///    Look-up via [widgetsFor] always returns a list (possibly empty).
///
/// All getters are null- / empty-safe by construction so that callers
/// never have to defend against a missing extension.
class ExtensionRegistry {
  final Map<Type, Object> _services = <Type, Object>{};
  final Map<SlotId, List<Widget>> _slotWidgets = <SlotId, List<Widget>>{};
  bool _frozen = false;

  /// Whether the registry has been frozen (no further registrations
  /// will take effect). Set by [freeze]; intended for diagnostics.
  bool get isFrozen => _frozen;

  /// Lock the registry so that subsequent `register*` calls are
  /// ignored. Called by `ExtensionLoader.loadAll` after every factory
  /// has run; tests that construct a registry directly do not need to
  /// call this.
  ///
  /// The freeze is one-way: there is no `unfreeze()`. This guarantees
  /// the runtime configuration is stable for the lifetime of the app
  /// once startup completes.
  void freeze() {
    _frozen = true;
  }

  /// Register a service of compile-time type [T].
  ///
  /// If a service of the same type was already registered (by another
  /// extension or a previous register call) it is replaced. Order of
  /// registration is therefore observable; the loader documents that
  /// "last register wins" at the registry layer, but call sites apply
  /// `ServiceOverridePolicy` on top to choose between host and
  /// extension implementations.
  ///
  /// Calls made after [freeze] are silently ignored — they would
  /// otherwise let a late-running extension mutate runtime state in
  /// ways the host did not anticipate.
  void registerService<T extends Object>(T service) {
    if (_frozen) {
      _logRejectedAfterFreeze('registerService<$T>');
      return;
    }
    _services[T] = service;
  }

  /// Append [widgets] to the slot identified by [slotId].
  ///
  /// Multiple extensions may register widgets for the same slot; their
  /// widgets are concatenated in registration order. The host decides
  /// final rendering order via `SlotInsertOrder` at the call site.
  ///
  /// Calls made after [freeze] are silently ignored.
  void registerSlotWidgets(SlotId slotId, List<Widget> widgets) {
    if (_frozen) {
      _logRejectedAfterFreeze('registerSlotWidgets($slotId)');
      return;
    }
    if (widgets.isEmpty) {
      return;
    }
    _slotWidgets.putIfAbsent(slotId, () => <Widget>[]).addAll(widgets);
  }

  static void _logRejectedAfterFreeze(String call) {
    // Debug-only diagnostic; release builds stay silent so that a
    // misbehaving extension cannot use this path to surface noise in
    // platform logs.
    assert(() {
      debugPrint('[extension-registry] ignored after freeze: $call');
      return true;
    }());
  }

  /// Look up the registered service of type [T], or `null`.
  ///
  /// Never throws. Returning `null` is the canonical signal that no
  /// extension provides this capability.
  T? service<T extends Object>() {
    final Object? value = _services[T];
    if (value is T) {
      return value;
    }
    return null;
  }

  /// Read-only view of widgets registered for [slotId]. Empty if none.
  List<Widget> widgetsFor(SlotId slotId) {
    final List<Widget>? widgets = _slotWidgets[slotId];
    if (widgets == null || widgets.isEmpty) {
      return const <Widget>[];
    }
    return List<Widget>.unmodifiable(widgets);
  }

  /// Number of distinct service types currently registered. Intended
  /// for diagnostics and tests only.
  @visibleForTesting
  int get debugServiceCount => _services.length;

  /// Number of slots that have at least one widget registered.
  /// Intended for diagnostics and tests only.
  @visibleForTesting
  int get debugSlotCount => _slotWidgets.length;
}
