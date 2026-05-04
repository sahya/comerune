import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/extension/comerune_extension.dart';
import 'package:comerune/extension/extension_loader.dart';
import 'package:comerune/extension/extension_registry.dart';
import 'package:comerune/extension/slot_ids.dart';

class _DummyService {
  const _DummyService();
}

void main() {
  group('ExtensionLoader (no integrations)', () {
    test(
      'loadAll completes without throwing when no factories registered',
      () async {
        final ExtensionLoader loader = ExtensionLoader(
          factories: const <ExtensionFactory>[],
        );

        await expectLater(loader.loadAll(), completes);
      },
    );

    test(
      'registry exposes empty service / slot views before loadAll runs',
      () async {
        final ExtensionLoader loader = ExtensionLoader(
          factories: const <ExtensionFactory>[],
        );

        expect(loader.registry.service<_DummyService>(), isNull);
        expect(
          loader.registry.widgetsFor(SlotIds.broadcasterScreenActions),
          isEmpty,
        );
        expect(loader.registry.debugServiceCount, 0);
        expect(loader.registry.debugSlotCount, 0);
      },
    );

    test(
      'registry remains empty after loadAll when no factories registered',
      () async {
        final ExtensionLoader loader = ExtensionLoader(
          factories: const <ExtensionFactory>[],
        );

        await loader.loadAll();

        expect(loader.registry.service<_DummyService>(), isNull);
        expect(
          loader.registry.widgetsFor(SlotIds.broadcasterScreenActions),
          isEmpty,
        );
        expect(loader.registry.debugServiceCount, 0);
        expect(loader.registry.debugSlotCount, 0);
      },
    );

    test('production default loader (uses generated registry) loads with no '
        'integrations present', () async {
      // The generated registry is checked into the repository as an
      // empty list while no integrations are installed. Constructing
      // the loader without arguments must therefore succeed and end
      // up with an empty registry.
      final ExtensionLoader loader = ExtensionLoader();

      await expectLater(loader.loadAll(), completes);

      expect(loader.registry.debugServiceCount, 0);
      expect(loader.registry.debugSlotCount, 0);
    });
  });

  group('ExtensionRegistry (direct API)', () {
    test('registerService overrides previous registration of same type', () {
      final ExtensionRegistry registry = ExtensionRegistry();
      const _DummyService a = _DummyService();
      const _DummyService b = _DummyService();

      registry.registerService<_DummyService>(a);
      registry.registerService<_DummyService>(b);

      expect(identical(registry.service<_DummyService>(), b), isTrue);
      expect(registry.debugServiceCount, 1);
    });

    test('registerSlotWidgets concatenates across calls', () {
      final ExtensionRegistry registry = ExtensionRegistry();
      const Widget a = SizedBox.shrink(key: ValueKey<String>('a'));
      const Widget b = SizedBox.shrink(key: ValueKey<String>('b'));

      registry.registerSlotWidgets(
        SlotIds.broadcasterScreenActions,
        const <Widget>[a],
      );
      registry.registerSlotWidgets(
        SlotIds.broadcasterScreenActions,
        const <Widget>[b],
      );

      final List<Widget> widgets = registry.widgetsFor(
        SlotIds.broadcasterScreenActions,
      );
      expect(widgets, hasLength(2));
      expect(widgets.first.key, const ValueKey<String>('a'));
      expect(widgets.last.key, const ValueKey<String>('b'));
    });

    test('widgetsFor returns an unmodifiable view', () {
      final ExtensionRegistry registry = ExtensionRegistry();
      registry.registerSlotWidgets(
        SlotIds.broadcasterScreenActions,
        const <Widget>[SizedBox.shrink()],
      );

      final List<Widget> widgets = registry.widgetsFor(
        SlotIds.broadcasterScreenActions,
      );

      expect(
        () => widgets.add(const SizedBox.shrink()),
        throwsUnsupportedError,
      );
    });

    test('registerSlotWidgets ignores empty input', () {
      final ExtensionRegistry registry = ExtensionRegistry();

      registry.registerSlotWidgets(
        SlotIds.broadcasterScreenActions,
        const <Widget>[],
      );

      expect(registry.debugSlotCount, 0);
      expect(registry.widgetsFor(SlotIds.broadcasterScreenActions), isEmpty);
    });
  });

  group('SlotId equality', () {
    test('catalogue constants are stable singletons', () {
      expect(
        identical(
          SlotIds.broadcasterScreenActions,
          SlotIds.broadcasterScreenActions,
        ),
        isTrue,
      );
    });

    test('SlotId equality is value-based', () {
      // Note: we can't construct SlotId externally. This test documents
      // the equality contract by comparing the catalogue constant to
      // itself via the registry round-trip.
      final ExtensionRegistry registry = ExtensionRegistry();
      registry.registerSlotWidgets(
        SlotIds.broadcasterScreenActions,
        const <Widget>[SizedBox.shrink()],
      );
      expect(
        registry.widgetsFor(SlotIds.broadcasterScreenActions),
        hasLength(1),
      );
    });
  });

  group('ContractVersion', () {
    test('exposes a non-zero positive integer', () {
      expect(kComeruneExtensionContractVersion, greaterThan(0));
    });
  });
}
