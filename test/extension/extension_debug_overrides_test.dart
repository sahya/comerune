import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/extension/extension_debug_overrides.dart';
import 'package:comerune/extension/service_override_policy.dart';
import 'package:comerune/extension/slot_ids.dart';
import 'package:comerune/extension/slot_insert_order.dart';

void main() {
  group('debugResolveServicePolicy', () {
    test('returns fallback when in release mode (overrides ignored)', () {
      final ServiceOverridePolicy policy = debugResolveServicePolicy(
        fallback: ServiceOverridePolicy.extensionFirstFallback,
        contractName: 'AnyContract',
        isReleaseMode: true,
        perContract: const <String, String>{'AnyContract': 'hostOnly'},
        global: 'extensionOnly',
      );
      expect(policy, ServiceOverridePolicy.extensionFirstFallback);
    });

    test('returns fallback when neither global nor per-contract is set', () {
      final ServiceOverridePolicy policy = debugResolveServicePolicy(
        fallback: ServiceOverridePolicy.extensionFirstFallback,
        contractName: 'AnyContract',
        isReleaseMode: false,
        perContract: const <String, String>{},
        global: '',
      );
      expect(policy, ServiceOverridePolicy.extensionFirstFallback);
    });

    test('honours the global override when no per-contract is set', () {
      final ServiceOverridePolicy policy = debugResolveServicePolicy(
        fallback: ServiceOverridePolicy.extensionFirstFallback,
        contractName: 'AnyContract',
        isReleaseMode: false,
        perContract: const <String, String>{},
        global: 'hostOnly',
      );
      expect(policy, ServiceOverridePolicy.hostOnly);
    });

    test('per-contract override wins over global', () {
      final ServiceOverridePolicy policy = debugResolveServicePolicy(
        fallback: ServiceOverridePolicy.extensionFirstFallback,
        contractName: 'AnyContract',
        isReleaseMode: false,
        perContract: const <String, String>{'AnyContract': 'extensionOnly'},
        global: 'hostOnly',
      );
      expect(policy, ServiceOverridePolicy.extensionOnly);
    });

    test('falls back when global override is an unknown name', () {
      final ServiceOverridePolicy policy = debugResolveServicePolicy(
        fallback: ServiceOverridePolicy.hostFirstFallback,
        contractName: 'AnyContract',
        isReleaseMode: false,
        perContract: const <String, String>{},
        global: 'invalidValue',
      );
      expect(policy, ServiceOverridePolicy.hostFirstFallback);
    });

    test('falls back when per-contract override is an unknown name', () {
      final ServiceOverridePolicy policy = debugResolveServicePolicy(
        fallback: ServiceOverridePolicy.extensionFirstFallback,
        contractName: 'AnyContract',
        isReleaseMode: false,
        perContract: const <String, String>{'AnyContract': 'oops'},
        global: '',
      );
      expect(policy, ServiceOverridePolicy.extensionFirstFallback);
    });

    test('per-contract is only matched on exact key', () {
      final ServiceOverridePolicy policy = debugResolveServicePolicy(
        fallback: ServiceOverridePolicy.extensionFirstFallback,
        contractName: 'AnotherContract',
        isReleaseMode: false,
        perContract: const <String, String>{'AnyContract': 'hostOnly'},
        global: '',
      );
      expect(policy, ServiceOverridePolicy.extensionFirstFallback);
    });

    test('all four policy names parse correctly', () {
      for (final ServiceOverridePolicy expected
          in ServiceOverridePolicy.values) {
        final ServiceOverridePolicy policy = debugResolveServicePolicy(
          fallback: ServiceOverridePolicy.extensionFirstFallback,
          contractName: 'AnyContract',
          isReleaseMode: false,
          perContract: const <String, String>{},
          global: expected.name,
        );
        expect(policy, expected);
      }
    });
  });

  group('debugResolveSlotOrder', () {
    test('returns fallback when in release mode (overrides ignored)', () {
      final SlotInsertOrder order = debugResolveSlotOrder(
        fallback: SlotInsertOrder.hostFirst,
        slotId: SlotIds.broadcasterScreenActions,
        isReleaseMode: true,
        perSlot: const <String, String>{
          'broadcaster.screen.actions': 'hostOnly',
        },
        global: 'extensionOnly',
      );
      expect(order, SlotInsertOrder.hostFirst);
    });

    test('returns fallback when neither global nor per-slot is set', () {
      final SlotInsertOrder order = debugResolveSlotOrder(
        fallback: SlotInsertOrder.hostFirst,
        slotId: SlotIds.broadcasterScreenActions,
        isReleaseMode: false,
        perSlot: const <String, String>{},
        global: '',
      );
      expect(order, SlotInsertOrder.hostFirst);
    });

    test('honours the global override when no per-slot is set', () {
      final SlotInsertOrder order = debugResolveSlotOrder(
        fallback: SlotInsertOrder.hostFirst,
        slotId: SlotIds.broadcasterScreenActions,
        isReleaseMode: false,
        perSlot: const <String, String>{},
        global: 'hostOnly',
      );
      expect(order, SlotInsertOrder.hostOnly);
    });

    test('per-slot override wins over global', () {
      final SlotInsertOrder order = debugResolveSlotOrder(
        fallback: SlotInsertOrder.hostFirst,
        slotId: SlotIds.broadcasterScreenActions,
        isReleaseMode: false,
        perSlot: const <String, String>{
          'broadcaster.screen.actions': 'extensionOnly',
        },
        global: 'hostOnly',
      );
      expect(order, SlotInsertOrder.extensionOnly);
    });

    test('falls back when override is an unknown name', () {
      final SlotInsertOrder order = debugResolveSlotOrder(
        fallback: SlotInsertOrder.hostFirst,
        slotId: SlotIds.broadcasterScreenActions,
        isReleaseMode: false,
        perSlot: const <String, String>{},
        global: 'oops',
      );
      expect(order, SlotInsertOrder.hostFirst);
    });

    test('all four order names parse correctly', () {
      for (final SlotInsertOrder expected in SlotInsertOrder.values) {
        final SlotInsertOrder order = debugResolveSlotOrder(
          fallback: SlotInsertOrder.hostFirst,
          slotId: SlotIds.broadcasterScreenActions,
          isReleaseMode: false,
          perSlot: const <String, String>{},
          global: expected.name,
        );
        expect(order, expected);
      }
    });
  });

  group('debugIsExtensionDisabled', () {
    test('returns false in release mode regardless of disabledList', () {
      expect(
        debugIsExtensionDisabled(
          extensionName: 'foo',
          isReleaseMode: true,
          disabledList: 'foo,bar',
        ),
        isFalse,
      );
    });

    test('returns false when disabledList is empty', () {
      expect(
        debugIsExtensionDisabled(
          extensionName: 'foo',
          isReleaseMode: false,
          disabledList: '',
        ),
        isFalse,
      );
    });

    test('returns true when name appears in single-entry list', () {
      expect(
        debugIsExtensionDisabled(
          extensionName: 'foo',
          isReleaseMode: false,
          disabledList: 'foo',
        ),
        isTrue,
      );
    });

    test('returns true when name appears in multi-entry list', () {
      expect(
        debugIsExtensionDisabled(
          extensionName: 'bar',
          isReleaseMode: false,
          disabledList: 'foo,bar,baz',
        ),
        isTrue,
      );
    });

    test('trims whitespace around comma-separated entries', () {
      expect(
        debugIsExtensionDisabled(
          extensionName: 'bar',
          isReleaseMode: false,
          disabledList: 'foo, bar , baz',
        ),
        isTrue,
      );
    });

    test('returns false when name is absent from list', () {
      expect(
        debugIsExtensionDisabled(
          extensionName: 'qux',
          isReleaseMode: false,
          disabledList: 'foo,bar',
        ),
        isFalse,
      );
    });

    test('matches are case-sensitive', () {
      expect(
        debugIsExtensionDisabled(
          extensionName: 'Foo',
          isReleaseMode: false,
          disabledList: 'foo',
        ),
        isFalse,
      );
    });
  });

  group(
    'production resolveServicePolicy / resolveSlotOrder / isExtensionDisabled (smoke)',
    () {
      test(
        'production wrappers return the fallback when no dart-define is set',
        () {
          // No --dart-define is provided when running tests, so
          // every override key resolves to its empty default. The
          // production wrappers should therefore return the fallback
          // unchanged.
          expect(
            resolveServicePolicy(
              fallback: ServiceOverridePolicy.extensionFirstFallback,
              contractName: 'NotConfigured',
            ),
            ServiceOverridePolicy.extensionFirstFallback,
          );
          expect(
            resolveSlotOrder(
              fallback: SlotInsertOrder.hostFirst,
              slotId: SlotIds.broadcasterScreenActions,
            ),
            SlotInsertOrder.hostFirst,
          );
          expect(isExtensionDisabled(extensionName: 'AnyExtension'), isFalse);
        },
      );
    },
  );
}
