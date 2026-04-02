import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/presentation/screens/user_detail_sheet.dart';

// ARGB32 value of kUserColorPalette.first (Color(0xFFE53935)).
const int _kFirstColorValue = 0xFFE53935;

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
