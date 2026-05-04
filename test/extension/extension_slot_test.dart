import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/extension/extension_registry.dart';
import 'package:comerune/extension/extension_scope.dart';
import 'package:comerune/extension/extension_slot.dart';
import 'package:comerune/extension/slot_ids.dart';
import 'package:comerune/extension/slot_insert_order.dart';

void main() {
  group('composeSlotChildrenInOrder', () {
    const List<String> host = <String>['h1', 'h2'];
    const List<String> ext = <String>['e1', 'e2'];

    test('hostFirst concatenates host then extension', () {
      expect(
        composeSlotChildrenInOrder(
          order: SlotInsertOrder.hostFirst,
          hostChildren: host,
          extensionChildren: ext,
        ),
        <String>['h1', 'h2', 'e1', 'e2'],
      );
    });

    test('extensionFirst concatenates extension then host', () {
      expect(
        composeSlotChildrenInOrder(
          order: SlotInsertOrder.extensionFirst,
          hostChildren: host,
          extensionChildren: ext,
        ),
        <String>['e1', 'e2', 'h1', 'h2'],
      );
    });

    test('hostOnly returns host children unchanged', () {
      expect(
        composeSlotChildrenInOrder(
          order: SlotInsertOrder.hostOnly,
          hostChildren: host,
          extensionChildren: ext,
        ),
        <String>['h1', 'h2'],
      );
    });

    test('extensionOnly returns extension children unchanged', () {
      expect(
        composeSlotChildrenInOrder(
          order: SlotInsertOrder.extensionOnly,
          hostChildren: host,
          extensionChildren: ext,
        ),
        <String>['e1', 'e2'],
      );
    });

    test('hostFirst with empty extension returns host (identity is OK)', () {
      const List<String> empty = <String>[];
      final List<String> result = composeSlotChildrenInOrder(
        order: SlotInsertOrder.hostFirst,
        hostChildren: host,
        extensionChildren: empty,
      );
      expect(result, host);
    });

    test('extensionFirst with empty extension returns host', () {
      const List<String> empty = <String>[];
      final List<String> result = composeSlotChildrenInOrder(
        order: SlotInsertOrder.extensionFirst,
        hostChildren: host,
        extensionChildren: empty,
      );
      expect(result, host);
    });
  });

  group('resolveSlotChildren (widget tree)', () {
    Widget _wrapWithScope(ExtensionRegistry registry, Widget child) {
      return MaterialApp(
        home: ExtensionScope(registry: registry, child: child),
      );
    }

    testWidgets('returns host children when no ExtensionScope is mounted', (
      WidgetTester tester,
    ) async {
      List<Text>? captured;

      // Intentionally NOT wrapping in ExtensionScope — this mirrors
      // legacy widget tests that pump a screen without the app shell.
      // The slot must degrade gracefully to host-only output.
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              captured = resolveSlotChildren<Text>(
                context,
                slotId: SlotIds.broadcasterScreenActions,
                hostChildren: const <Text>[Text('host-only')],
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(captured!.map((Text t) => t.data).toList(), <String>['host-only']);
    });

    testWidgets('returns host children when no extension widget registered', (
      WidgetTester tester,
    ) async {
      final ExtensionRegistry registry = ExtensionRegistry();
      List<Text>? captured;

      await tester.pumpWidget(
        _wrapWithScope(
          registry,
          Builder(
            builder: (BuildContext context) {
              captured = resolveSlotChildren<Text>(
                context,
                slotId: SlotIds.broadcasterScreenActions,
                hostChildren: const <Text>[Text('host-1'), Text('host-2')],
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(captured, hasLength(2));
      expect(captured!.map((Text t) => t.data).toList(), <String>[
        'host-1',
        'host-2',
      ]);
    });

    testWidgets('appends extension widgets after host (hostFirst default)', (
      WidgetTester tester,
    ) async {
      final ExtensionRegistry registry = ExtensionRegistry();
      registry.registerSlotWidgets(
        SlotIds.broadcasterScreenActions,
        const <Widget>[Text('ext-1'), Text('ext-2')],
      );
      List<Text>? captured;

      await tester.pumpWidget(
        _wrapWithScope(
          registry,
          Builder(
            builder: (BuildContext context) {
              captured = resolveSlotChildren<Text>(
                context,
                slotId: SlotIds.broadcasterScreenActions,
                hostChildren: const <Text>[Text('host-1')],
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(captured!.map((Text t) => t.data).toList(), <String>[
        'host-1',
        'ext-1',
        'ext-2',
      ]);
    });

    testWidgets(
      'drops extension widgets that do not match the requested type',
      (WidgetTester tester) async {
        final ExtensionRegistry registry = ExtensionRegistry();
        registry.registerSlotWidgets(
          SlotIds.broadcasterScreenActions,
          const <Widget>[Text('ext-text'), Icon(Icons.star)],
        );
        List<Text>? captured;

        await tester.pumpWidget(
          _wrapWithScope(
            registry,
            Builder(
              builder: (BuildContext context) {
                // Only Text widgets should be picked up; Icon is filtered.
                captured = resolveSlotChildren<Text>(
                  context,
                  slotId: SlotIds.broadcasterScreenActions,
                  hostChildren: const <Text>[],
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        expect(captured!.map((Text t) => t.data).toList(), <String>[
          'ext-text',
        ]);
      },
    );
  });
}
