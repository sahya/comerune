import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/extension/extension_registry.dart';
import 'package:comerune/extension/extension_scope.dart';

void main() {
  group('ExtensionScope', () {
    testWidgets('exposes the registry to descendants via of()', (
      WidgetTester tester,
    ) async {
      final ExtensionRegistry registry = ExtensionRegistry();
      ExtensionRegistry? captured;

      await tester.pumpWidget(
        MaterialApp(
          home: ExtensionScope(
            registry: registry,
            child: Builder(
              builder: (BuildContext context) {
                captured = ExtensionScope.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(identical(captured, registry), isTrue);
    });

    testWidgets('maybeOf returns null when no scope is mounted', (
      WidgetTester tester,
    ) async {
      ExtensionRegistry? captured;
      bool wasNull = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              final ExtensionRegistry? maybe = ExtensionScope.maybeOf(context);
              captured = maybe;
              wasNull = maybe == null;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(captured, isNull);
      expect(wasNull, isTrue);
    });

    testWidgets('maybeOf returns the registry when mounted', (
      WidgetTester tester,
    ) async {
      final ExtensionRegistry registry = ExtensionRegistry();
      ExtensionRegistry? captured;

      await tester.pumpWidget(
        MaterialApp(
          home: ExtensionScope(
            registry: registry,
            child: Builder(
              builder: (BuildContext context) {
                captured = ExtensionScope.maybeOf(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(identical(captured, registry), isTrue);
    });

    test('updateShouldNotify only returns true on a different identity', () {
      // Direct unit test of the contract — independent of the broader
      // element-tree rebuild semantics that make widget-level tests of
      // this method brittle (a parent setState() rebuilds descendants
      // regardless of InheritedWidget notification).
      final ExtensionRegistry registry1 = ExtensionRegistry();
      final ExtensionRegistry registry2 = ExtensionRegistry();
      const Widget child = SizedBox.shrink();

      final ExtensionScope a = ExtensionScope(
        registry: registry1,
        child: child,
      );
      final ExtensionScope b = ExtensionScope(
        registry: registry1,
        child: child,
      );
      final ExtensionScope c = ExtensionScope(
        registry: registry2,
        child: child,
      );

      expect(a.updateShouldNotify(b), isFalse);
      expect(a.updateShouldNotify(c), isTrue);
    });
  });
}
