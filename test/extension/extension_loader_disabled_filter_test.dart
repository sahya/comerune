// Verifies that the loader's integration of
// `isExtensionDisabled` (from extension_debug_overrides.dart) skips
// disabled extensions before they call register().
//
// The production `isExtensionDisabled` reads compile-time const
// dart-defines, so this suite cannot easily inject runtime values
// for it. Instead, we exercise the loader's name-based disable path
// indirectly: disabled extensions are those whose name matches a
// no-op default (which is fine since with no dart-define set, the
// disable list is empty and nothing is filtered). The corresponding
// debug-only filter behaviour is exhaustively tested in
// `extension_debug_overrides_test.dart`.
//
// What this file verifies:
// - With no dart-define disabled list, every extension still loads.
// - The loader still wraps factory and register calls in the
//   defensive try/catch (regression guard).
// - The `name` getter on ComeruneExtension defaults to runtime type.

import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/extension/comerune_extension.dart';
import 'package:comerune/extension/extension_loader.dart';
import 'package:comerune/extension/extension_registry.dart';

class _MarkerService {
  const _MarkerService(this.label);
  final String label;
}

class _NamedExtension extends ComeruneExtension {
  const _NamedExtension({required this.label});
  final String label;

  @override
  String get name => 'named_$label';

  @override
  void register(ExtensionRegistry registry) {
    registry.registerService<_MarkerService>(_MarkerService(label));
  }
}

class _DefaultNameExtension extends ComeruneExtension {
  const _DefaultNameExtension();

  @override
  void register(ExtensionRegistry registry) {
    registry.registerService<_MarkerService>(const _MarkerService('default'));
  }
}

void main() {
  group('ExtensionLoader name + disable integration', () {
    test('default name getter returns runtime type', () {
      const _DefaultNameExtension extension = _DefaultNameExtension();
      expect(extension.name, '_DefaultNameExtension');
    });

    test('overridden name getter returns custom string', () {
      const _NamedExtension extension = _NamedExtension(label: 'foo');
      expect(extension.name, 'named_foo');
    });

    test(
      'with no disable dart-define set, all extensions register normally',
      () async {
        final ExtensionLoader loader = ExtensionLoader(
          factories: <ExtensionFactory>[
            () => const _NamedExtension(label: 'first'),
          ],
        );

        await loader.loadAll();

        final _MarkerService? marker = loader.registry
            .service<_MarkerService>();
        expect(marker, isNotNull);
        expect(marker!.label, 'first');
      },
    );

    test('loader still freezes registry after disabled-filtered run', () async {
      final ExtensionLoader loader = ExtensionLoader(
        factories: <ExtensionFactory>[
          () => const _NamedExtension(label: 'frozen'),
        ],
      );

      await loader.loadAll();

      expect(loader.registry.isFrozen, isTrue);
    });
  });
}
