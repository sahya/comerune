import 'package:flutter/widgets.dart';

import 'extension_debug_overrides.dart';
import 'extension_registry.dart';
import 'extension_scope.dart';
import 'slot_ids.dart';
import 'slot_insert_order.dart';

/// Compose host- and extension-provided children for an extension UI
/// slot in the configured insertion order.
///
/// Returns a single combined list whose elements are drawn from
/// [hostChildren] and from `ExtensionRegistry.widgetsFor(slotId)`.
/// Extension widgets that are not assignable to [T] are silently
/// dropped — the slot's documented contract specifies what type
/// each registered widget must implement, and extensions that
/// violate the contract should not break the host's UI.
///
/// The composition order is determined by [resolveSlotOrder] (which
/// honours `--dart-define=COMERUNE_EXT_SLOT_ORDER*` overrides in
/// debug builds). [fallback] is used when no override is in effect;
/// most call sites pass [SlotInsertOrder.hostFirst] so that host UI
/// remains the primary affordance and extension widgets append
/// after it.
///
/// When called from a context without a mounted [ExtensionScope]
/// (typical of unit tests that pump a screen without the app shell),
/// the slot degrades to [hostChildren] alone. Production code mounts
/// the scope at the [MaterialApp] level so production callers always
/// see extension widgets when registered.
List<T> resolveSlotChildren<T extends Widget>(
  BuildContext context, {
  required SlotId slotId,
  required List<T> hostChildren,
  SlotInsertOrder fallback = SlotInsertOrder.hostFirst,
}) {
  final ExtensionRegistry? registry = ExtensionScope.maybeOf(context);
  if (registry == null) {
    return hostChildren;
  }
  final List<T> extensionChildren = registry
      .widgetsFor(slotId)
      .whereType<T>()
      .toList(growable: false);
  final SlotInsertOrder order = resolveSlotOrder(
    fallback: fallback,
    slotId: slotId,
  );
  return _composeInOrder(
    order: order,
    hostChildren: hostChildren,
    extensionChildren: extensionChildren,
  );
}

@visibleForTesting
List<T> composeSlotChildrenInOrder<T>({
  required SlotInsertOrder order,
  required List<T> hostChildren,
  required List<T> extensionChildren,
}) => _composeInOrder(
  order: order,
  hostChildren: hostChildren,
  extensionChildren: extensionChildren,
);

List<T> _composeInOrder<T>({
  required SlotInsertOrder order,
  required List<T> hostChildren,
  required List<T> extensionChildren,
}) {
  switch (order) {
    case SlotInsertOrder.hostFirst:
      if (extensionChildren.isEmpty) {
        return hostChildren;
      }
      return <T>[...hostChildren, ...extensionChildren];
    case SlotInsertOrder.extensionFirst:
      if (extensionChildren.isEmpty) {
        return hostChildren;
      }
      return <T>[...extensionChildren, ...hostChildren];
    case SlotInsertOrder.hostOnly:
      return hostChildren;
    case SlotInsertOrder.extensionOnly:
      return extensionChildren;
  }
}
