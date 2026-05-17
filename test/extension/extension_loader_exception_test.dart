import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/extension/comerune_extension.dart';
import 'package:comerune/extension/extension_loader.dart';
import 'package:comerune/extension/extension_registry.dart';
import 'package:comerune/extension/slot_ids.dart';

class _MarkerService {
  const _MarkerService(this.label);
  final String label;
}

class _GoodExtension extends ComeruneExtension {
  const _GoodExtension(this.label);
  final String label;

  @override
  void register(ExtensionRegistry registry) {
    registry.registerService<_MarkerService>(_MarkerService(label));
    registry.registerSlotWidgets(SlotIds.broadcasterScreenActions, <Widget>[
      SizedBox.shrink(key: ValueKey<String>('good-$label')),
    ]);
  }
}

class _ThrowingFactoryException implements Exception {
  const _ThrowingFactoryException();
}

class _ThrowingRegisterException implements Exception {
  const _ThrowingRegisterException();
}

class _ThrowingExtension extends ComeruneExtension {
  const _ThrowingExtension();

  @override
  void register(ExtensionRegistry registry) {
    throw const _ThrowingRegisterException();
  }
}

ComeruneExtension _throwingFactory() => throw const _ThrowingFactoryException();

void main() {
  group('ExtensionLoader (defensive)', () {
    test('factory throwing does not stop subsequent factories', () async {
      final ExtensionLoader loader = ExtensionLoader(
        factories: <ExtensionFactory>[
          _throwingFactory,
          () => const _GoodExtension('after-throwing-factory'),
        ],
      );

      await loader.loadAll();

      final _MarkerService? marker = loader.registry.service<_MarkerService>();
      expect(marker, isNotNull);
      expect(marker!.label, 'after-throwing-factory');
    });

    test('register() throwing does not stop subsequent factories', () async {
      final ExtensionLoader loader = ExtensionLoader(
        factories: <ExtensionFactory>[
          () => const _ThrowingExtension(),
          () => const _GoodExtension('after-throwing-register'),
        ],
      );

      await loader.loadAll();

      final _MarkerService? marker = loader.registry.service<_MarkerService>();
      expect(marker, isNotNull);
      expect(marker!.label, 'after-throwing-register');
    });

    test('throwing factory does not register a partial extension', () async {
      final ExtensionLoader loader = ExtensionLoader(
        factories: <ExtensionFactory>[_throwingFactory],
      );

      await loader.loadAll();

      expect(loader.registry.service<_MarkerService>(), isNull);
      expect(
        loader.registry.widgetsFor(SlotIds.broadcasterScreenActions),
        isEmpty,
      );
    });

    test('mixed success and failure leaves the registry in a partial but '
        'consistent state', () async {
      final ExtensionLoader loader = ExtensionLoader(
        factories: <ExtensionFactory>[
          () => const _GoodExtension('first'),
          _throwingFactory,
          () => const _ThrowingExtension(),
          () => const _GoodExtension('last'),
        ],
      );

      await loader.loadAll();

      final _MarkerService? marker = loader.registry.service<_MarkerService>();
      // The registry's "last register wins" behaviour means the final
      // good extension should be the one observed — even though two
      // earlier factories threw.
      expect(marker, isNotNull);
      expect(marker!.label, 'last');

      // Both good extensions registered widgets; the throwing
      // extensions did not. We expect exactly two widgets in slot.
      expect(
        loader.registry.widgetsFor(SlotIds.broadcasterScreenActions),
        hasLength(2),
      );
    });

    test(
      'loadAll freezes the registry; second invocation is a no-op',
      () async {
        final ExtensionLoader loader = ExtensionLoader(
          factories: <ExtensionFactory>[() => const _GoodExtension('once')],
        );

        await loader.loadAll();
        expect(loader.registry.isFrozen, isTrue);

        // Second loadAll() must not crash and must not double-register —
        // the freeze ensures runtime configuration is stable after the
        // initial discovery completes.
        await loader.loadAll();

        expect(
          loader.registry.widgetsFor(SlotIds.broadcasterScreenActions),
          hasLength(1),
        );
        final _MarkerService? marker = loader.registry
            .service<_MarkerService>();
        expect(marker, isNotNull);
        expect(marker!.label, 'once');
      },
    );

    test('late register* calls after loadAll are silently ignored', () async {
      final ExtensionLoader loader = ExtensionLoader(
        factories: <ExtensionFactory>[() => const _GoodExtension('first')],
      );

      await loader.loadAll();

      // Simulate a misbehaving extension that calls back into the
      // registry after loadAll has completed (e.g. from a Timer it
      // scheduled inside register()).
      loader.registry.registerService<_MarkerService>(
        const _MarkerService('late'),
      );
      loader.registry.registerSlotWidgets(
        SlotIds.broadcasterScreenActions,
        const <Widget>[SizedBox.shrink(key: ValueKey<String>('late'))],
      );

      // Neither late call mutated the registry.
      expect(loader.registry.service<_MarkerService>()?.label, 'first');
      expect(
        loader.registry.widgetsFor(SlotIds.broadcasterScreenActions),
        hasLength(1),
      );
    });
  });
}
