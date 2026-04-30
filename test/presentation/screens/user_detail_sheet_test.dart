import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/presentation/screens/user_detail_sheet.dart';

// ARGB32 value of kUserColorPalette.first (Color(0xFFE53935)).
const int _kFirstColorValue = 0xFFE53935;

// A color value that is intentionally outside of the preset palette.
const int _kCustomColorValue = 0xFF123456;

void main() {
  group('UserDetailSheet', () {
    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('displays user ID and resolved name', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(
          userId: '12345',
          resolvedUserName: 'テストさん',
          allMessages: const <AppMessage>[],
        ),
      );
      await openSheet(tester);

      expect(find.text('ID: 12345'), findsOneWidget);
      expect(find.text('名前: テストさん'), findsOneWidget);
    });

    testWidgets('hides name when resolvedUserName is null', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(userId: '99999', allMessages: const <AppMessage>[]),
      );
      await openSheet(tester);

      expect(find.text('ID: 99999'), findsOneWidget);
      expect(find.byKey(const Key('user-detail-name')), findsNothing);
    });

    testWidgets('shows no-comments message when user has no comments', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(userId: '12345', allMessages: const <AppMessage>[]),
      );
      await openSheet(tester);

      expect(find.text('この放送でのコメントはありません'), findsOneWidget);
    });

    testWidgets('shows comment list filtered by user ID', (
      WidgetTester tester,
    ) async {
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'msg-1',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: '12345',
          content: 'hello',
          type: AppMessageType.chat,
        ),
        AppMessage(
          id: 'msg-2',
          timestamp: DateTime(2026, 3, 22, 12, 1, 0),
          userId: '99999',
          content: 'other user',
          type: AppMessageType.chat,
        ),
        AppMessage(
          id: 'msg-3',
          timestamp: DateTime(2026, 3, 22, 12, 2, 0),
          userId: '12345',
          content: 'world',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildSheet(userId: '12345', allMessages: messages),
      );
      await openSheet(tester);

      expect(find.textContaining('コメント履歴（2件）'), findsOneWidget);
      expect(find.text('hello'), findsOneWidget);
      expect(find.text('world'), findsOneWidget);
      expect(find.text('other user'), findsNothing);
    });

    testWidgets('shows NG登録 button when user is not NG', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(
          userId: '12345',
          allMessages: const <AppMessage>[],
          isNgUser: false,
        ),
      );
      await openSheet(tester);

      expect(find.text('NG登録'), findsOneWidget);
    });

    testWidgets('shows NG解除 button when user is NG', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(
          userId: '12345',
          allMessages: const <AppMessage>[],
          isNgUser: true,
        ),
      );
      await openSheet(tester);

      expect(find.text('NG解除'), findsOneWidget);
    });

    testWidgets('onToggleNgUser is called when NG button is tapped', (
      WidgetTester tester,
    ) async {
      int toggleCount = 0;

      await tester.pumpWidget(
        _buildSheet(
          userId: '12345',
          allMessages: const <AppMessage>[],
          onToggleNgUser: () {
            toggleCount += 1;
          },
        ),
      );
      await openSheet(tester);

      await tester.tap(find.byKey(const Key('ng-user-toggle-button')));
      await tester.pumpAndSettle();

      expect(toggleCount, 1);
    });

    testWidgets('shows color palette when onColorChanged is provided', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(
          userId: '12345',
          allMessages: const <AppMessage>[],
          onColorChanged: (_) {},
        ),
      );
      await openSheet(tester);

      expect(find.text('コメント色'), findsOneWidget);
      expect(find.byKey(const Key('user-color-palette')), findsOneWidget);
    });

    testWidgets('hides color palette when onColorChanged is null', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(userId: '12345', allMessages: const <AppMessage>[]),
      );
      await openSheet(tester);

      expect(find.text('コメント色'), findsNothing);
      expect(find.byKey(const Key('user-color-palette')), findsNothing);
    });

    testWidgets('tapping a color calls onColorChanged', (
      WidgetTester tester,
    ) async {
      int? selectedColor;

      await tester.pumpWidget(
        _buildSheet(
          userId: '12345',
          allMessages: const <AppMessage>[],
          onColorChanged: (int value) {
            selectedColor = value;
          },
        ),
      );
      await openSheet(tester);

      // Tap the first color in the palette.
      const int firstColorValue = _kFirstColorValue;
      await tester.tap(find.byKey(const Key('user-color-$firstColorValue')));
      await tester.pumpAndSettle();

      expect(selectedColor, firstColorValue);
    });

    testWidgets('shows reset button when currentColorValue is set', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(
          userId: '12345',
          allMessages: const <AppMessage>[],
          currentColorValue: _kFirstColorValue,
          onColorChanged: (_) {},
          onColorRemoved: () {},
        ),
      );
      await openSheet(tester);

      expect(find.text('リセット'), findsOneWidget);
    });

    testWidgets('hides reset button when currentColorValue is null', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(
          userId: '12345',
          allMessages: const <AppMessage>[],
          onColorChanged: (_) {},
        ),
      );
      await openSheet(tester);

      expect(find.text('リセット'), findsNothing);
    });

    testWidgets('shows custom color button when palette is visible', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(
          userId: '12345',
          allMessages: const <AppMessage>[],
          onColorChanged: (_) {},
        ),
      );
      await openSheet(tester);

      expect(find.byKey(const Key('user-color-custom-button')), findsOneWidget);
    });

    testWidgets('tapping custom color button shows color picker dialog', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(
          userId: '12345',
          allMessages: const <AppMessage>[],
          onColorChanged: (_) {},
        ),
      );
      await openSheet(tester);

      await tester.tap(find.byKey(const Key('user-color-custom-button')));
      await tester.pumpAndSettle();

      expect(find.text('カスタムカラー'), findsOneWidget);
      expect(find.byType(ColorPicker), findsOneWidget);
      expect(find.text('適用'), findsOneWidget);
      expect(find.text('キャンセル'), findsOneWidget);
    });

    testWidgets('cancel on custom dialog does not call onColorChanged', (
      WidgetTester tester,
    ) async {
      int callCount = 0;

      await tester.pumpWidget(
        _buildSheet(
          userId: '12345',
          allMessages: const <AppMessage>[],
          onColorChanged: (_) {
            callCount += 1;
          },
        ),
      );
      await openSheet(tester);

      await tester.tap(find.byKey(const Key('user-color-custom-button')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('user-color-custom-dialog-cancel-button')),
      );
      await tester.pumpAndSettle();

      expect(callCount, 0);
    });

    testWidgets(
      'apply on custom dialog calls onColorChanged with picked color',
      (WidgetTester tester) async {
        int? selectedColor;

        await tester.pumpWidget(
          _buildSheet(
            userId: '12345',
            allMessages: const <AppMessage>[],
            // Start with a preset color so the dialog opens with that color.
            currentColorValue: _kFirstColorValue,
            onColorChanged: (int value) {
              selectedColor = value;
            },
          ),
        );
        await openSheet(tester);

        await tester.tap(find.byKey(const Key('user-color-custom-button')));
        await tester.pumpAndSettle();

        // Apply without changing the color: onColorChanged should be called
        // with the initial (preset) color value, confirming the apply path.
        await tester.tap(
          find.byKey(const Key('user-color-custom-dialog-apply-button')),
        );
        await tester.pumpAndSettle();

        expect(selectedColor, _kFirstColorValue);
      },
    );

    testWidgets(
      'apply forwards the latest color from picker.onColorChanged callback',
      (WidgetTester tester) async {
        int? selectedColor;

        await tester.pumpWidget(
          _buildSheet(
            userId: '12345',
            allMessages: const <AppMessage>[],
            currentColorValue: _kFirstColorValue,
            onColorChanged: (int value) {
              selectedColor = value;
            },
          ),
        );
        await openSheet(tester);

        await tester.tap(find.byKey(const Key('user-color-custom-button')));
        await tester.pumpAndSettle();

        // Drive the ColorPicker's onColorChanged callback directly to
        // simulate the user picking a color inside the wheel without
        // depending on the picker's internal slider/touch implementation.
        final ColorPicker picker = tester.widget<ColorPicker>(
          find.byType(ColorPicker),
        );
        picker.onColorChanged(const Color(_kCustomColorValue));

        await tester.tap(
          find.byKey(const Key('user-color-custom-dialog-apply-button')),
        );
        await tester.pumpAndSettle();

        expect(selectedColor, _kCustomColorValue);
      },
    );

    testWidgets(
      'reopening dialog with a custom color initializes picker with that color',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _buildSheet(
            userId: '12345',
            allMessages: const <AppMessage>[],
            currentColorValue: _kCustomColorValue,
            onColorChanged: (_) {},
            onColorRemoved: () {},
          ),
        );
        await openSheet(tester);

        await tester.tap(find.byKey(const Key('user-color-custom-button')));
        await tester.pumpAndSettle();

        final ColorPicker picker = tester.widget<ColorPicker>(
          find.byType(ColorPicker),
        );
        expect(picker.pickerColor, const Color(_kCustomColorValue));
      },
    );

    testWidgets(
      'custom color button shows check mark when current color is not a preset',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _buildSheet(
            userId: '12345',
            allMessages: const <AppMessage>[],
            currentColorValue: _kCustomColorValue,
            onColorChanged: (_) {},
            onColorRemoved: () {},
          ),
        );
        await openSheet(tester);

        final Finder customButton = find.byKey(
          const Key('user-color-custom-button'),
        );
        expect(customButton, findsOneWidget);

        // When a custom (non-preset) color is selected, the button shows a
        // check icon. When no custom color is selected, it shows an add icon.
        expect(
          find.descendant(of: customButton, matching: find.byIcon(Icons.check)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: customButton, matching: find.byIcon(Icons.add)),
          findsNothing,
        );
      },
    );

    testWidgets(
      'custom color button shows add icon when current color is a preset',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _buildSheet(
            userId: '12345',
            allMessages: const <AppMessage>[],
            currentColorValue: _kFirstColorValue,
            onColorChanged: (_) {},
            onColorRemoved: () {},
          ),
        );
        await openSheet(tester);

        final Finder customButton = find.byKey(
          const Key('user-color-custom-button'),
        );
        expect(
          find.descendant(of: customButton, matching: find.byIcon(Icons.add)),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'preset color tap still works with custom button present (regression)',
      (WidgetTester tester) async {
        int? selectedColor;

        await tester.pumpWidget(
          _buildSheet(
            userId: '12345',
            allMessages: const <AppMessage>[],
            onColorChanged: (int value) {
              selectedColor = value;
            },
          ),
        );
        await openSheet(tester);

        const int firstColorValue = _kFirstColorValue;
        await tester.tap(find.byKey(const Key('user-color-$firstColorValue')));
        await tester.pumpAndSettle();

        expect(selectedColor, firstColorValue);
      },
    );

    testWidgets('tapping reset calls onColorRemoved', (
      WidgetTester tester,
    ) async {
      bool removeCalled = false;

      await tester.pumpWidget(
        _buildSheet(
          userId: '12345',
          allMessages: const <AppMessage>[],
          currentColorValue: _kFirstColorValue,
          onColorChanged: (_) {},
          onColorRemoved: () {
            removeCalled = true;
          },
        ),
      );
      await openSheet(tester);

      await tester.tap(find.byKey(const Key('user-color-reset-button')));
      await tester.pumpAndSettle();

      expect(removeCalled, isTrue);
    });
  });
}

Widget _buildSheet({
  required String userId,
  String? resolvedUserName,
  required List<AppMessage> allMessages,
  bool isNgUser = false,
  VoidCallback? onToggleNgUser,
  int? currentColorValue,
  void Function(int)? onColorChanged,
  VoidCallback? onColorRemoved,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (BuildContext context) {
          return ElevatedButton(
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => UserDetailSheet(
                  userId: userId,
                  resolvedUserName: resolvedUserName,
                  allMessages: allMessages,
                  isNgUser: isNgUser,
                  onToggleNgUser: onToggleNgUser ?? () {},
                  currentColorValue: currentColorValue,
                  onColorChanged: onColorChanged,
                  onColorRemoved: onColorRemoved,
                ),
              );
            },
            child: const Text('open'),
          );
        },
      ),
    ),
  );
}
