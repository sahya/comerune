import 'package:flutter/foundation.dart';

import 'service_override_policy.dart';
import 'slot_ids.dart';
import 'slot_insert_order.dart';

/// Compile-time --dart-define lookups that let developers tweak the
/// optional-integration subsystem without rebuilding for a different
/// configuration.
///
/// All overrides are **strictly debug-only**:
/// - Public functions short-circuit on `kReleaseMode` and return the
///   provided fallback unchanged.
/// - The compile-time string lookups for the override values are
///   referenced only from code reachable in debug builds, so the AOT
///   compiler removes them from release binaries via tree-shaking.
///
/// Supported keys (all read via `String.fromEnvironment`):
///
/// - `COMERUNE_EXT_DISABLED` — comma-separated list of extension
///   names to skip during loading. Names match
///   `ComeruneExtension.name` (defaults to runtime type).
/// - `COMERUNE_EXT_POLICY` — global override for every service
///   contract's `ServiceOverridePolicy` (e.g. `hostOnly`). Per-
///   contract entries below take precedence when both are set.
/// - `COMERUNE_EXT_POLICY_<CONTRACT>` — per-contract override.
///   `<CONTRACT>` is the contract type's `toString()` mapped via the
///   table below; new service contracts add an entry here.
/// - `COMERUNE_EXT_SLOT_ORDER` — global override for every slot's
///   `SlotInsertOrder` (e.g. `hostOnly`). Per-slot entries below
///   take precedence.
/// - `COMERUNE_EXT_SLOT_ORDER_<SLOT_ID>` — per-slot override.
///   New slots add an entry here.
///
/// Unknown / mistyped values silently fall back to the provided
/// default rather than crashing — debug overrides should never
/// destabilise a running app.

const String _kGlobalPolicy = String.fromEnvironment('COMERUNE_EXT_POLICY');
const String _kGlobalSlotOrder = String.fromEnvironment(
  'COMERUNE_EXT_SLOT_ORDER',
);
const String _kDisabledExtensions = String.fromEnvironment(
  'COMERUNE_EXT_DISABLED',
);

/// Per-contract dart-define lookup table. The key is the contract
/// type's `Type.toString()`; the value is the result of
/// `String.fromEnvironment` for the corresponding key. Add new
/// entries here when introducing a new service contract that should
/// be controllable via dart-define.
const Map<String, String> _kPerContractPolicy = <String, String>{
  'BroadcastControlExtension': String.fromEnvironment(
    'COMERUNE_EXT_POLICY_BROADCAST_CONTROL_EXTENSION',
  ),
};

/// Per-slot dart-define lookup table. The key is the [SlotId.value]
/// string. Add new entries here when introducing a new slot that
/// should be controllable via dart-define.
const Map<String, String> _kPerSlotOrder = <String, String>{
  'broadcaster.screen.actions': String.fromEnvironment(
    'COMERUNE_EXT_SLOT_ORDER_BROADCASTER_SCREEN_ACTIONS',
  ),
};

/// Resolve the effective [ServiceOverridePolicy] for [contractName],
/// applying compile-time --dart-define overrides when in debug mode.
///
/// In release builds this always returns [fallback]; the explicit
/// `kReleaseMode` short-circuit guarantees the const lookup tables
/// below are not even referenced from the executed code path, so
/// the AOT compiler can tree-shake them out of release binaries.
ServiceOverridePolicy resolveServicePolicy({
  required ServiceOverridePolicy fallback,
  required String contractName,
}) {
  // Early-return BEFORE touching the const maps so AOT DCE can drop
  // both the maps and the dart-define value strings from the
  // release binary.
  if (kReleaseMode) {
    return fallback;
  }
  return debugResolveServicePolicy(
    fallback: fallback,
    contractName: contractName,
    isReleaseMode: false,
    perContract: _kPerContractPolicy,
    global: _kGlobalPolicy,
  );
}

/// Resolve the effective [SlotInsertOrder] for [slotId], applying
/// compile-time --dart-define overrides when in debug mode.
///
/// See [resolveServicePolicy] for the same release short-circuit
/// rationale.
SlotInsertOrder resolveSlotOrder({
  required SlotInsertOrder fallback,
  required SlotId slotId,
}) {
  if (kReleaseMode) {
    return fallback;
  }
  return debugResolveSlotOrder(
    fallback: fallback,
    slotId: slotId,
    isReleaseMode: false,
    perSlot: _kPerSlotOrder,
    global: _kGlobalSlotOrder,
  );
}

/// Whether the extension named [extensionName] should be skipped at
/// load time.
///
/// Always returns `false` in release builds; the disabled list is
/// not referenced from the executed code path in that case.
bool isExtensionDisabled({required String extensionName}) {
  if (kReleaseMode) {
    return false;
  }
  return debugIsExtensionDisabled(
    extensionName: extensionName,
    isReleaseMode: false,
    disabledList: _kDisabledExtensions,
  );
}

// ─────────────────────────────────────────────────────────────────────
// Test-only entry points. Each accepts the same inputs the production
// wrapper would compute from compile-time constants, so unit tests can
// exercise the full decision matrix (including the `isReleaseMode` arm)
// without rebuilding the application.
// ─────────────────────────────────────────────────────────────────────

@visibleForTesting
ServiceOverridePolicy debugResolveServicePolicy({
  required ServiceOverridePolicy fallback,
  required String contractName,
  required bool isReleaseMode,
  required Map<String, String> perContract,
  required String global,
}) {
  if (isReleaseMode) {
    return fallback;
  }
  final String per = perContract[contractName] ?? '';
  final String raw = per.isNotEmpty ? per : global;
  if (raw.isEmpty) {
    return fallback;
  }
  return _parseEnumByName(raw, ServiceOverridePolicy.values) ?? fallback;
}

@visibleForTesting
SlotInsertOrder debugResolveSlotOrder({
  required SlotInsertOrder fallback,
  required SlotId slotId,
  required bool isReleaseMode,
  required Map<String, String> perSlot,
  required String global,
}) {
  if (isReleaseMode) {
    return fallback;
  }
  final String per = perSlot[slotId.value] ?? '';
  final String raw = per.isNotEmpty ? per : global;
  if (raw.isEmpty) {
    return fallback;
  }
  return _parseEnumByName(raw, SlotInsertOrder.values) ?? fallback;
}

@visibleForTesting
bool debugIsExtensionDisabled({
  required String extensionName,
  required bool isReleaseMode,
  required String disabledList,
}) {
  if (isReleaseMode) {
    return false;
  }
  if (disabledList.isEmpty) {
    return false;
  }
  for (final String raw in disabledList.split(',')) {
    if (raw.trim() == extensionName) {
      return true;
    }
  }
  return false;
}

T? _parseEnumByName<T extends Enum>(String raw, List<T> values) {
  for (final T value in values) {
    if (value.name == raw) {
      return value;
    }
  }
  return null;
}
