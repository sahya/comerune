import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/presentation/screens/nickname_list_screen.dart';

import '../../helpers/in_memory_user_attribute_store.dart';

void main() {
  group('NicknameListScreen', () {
    testWidgets('shows empty message when no nickname exists', (
      WidgetTester tester,
    ) async {
      final InMemoryUserAttributeStore store = InMemoryUserAttributeStore();

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nickname-list-empty')), findsOneWidget);
      expect(find.text('コテハンは登録されていません'), findsOneWidget);
    });

    testWidgets('edits nickname and persists updated value', (
      WidgetTester tester,
    ) async {
      final InMemoryUserAttributeStore store = InMemoryUserAttributeStore();
      await store.setNickname(
        broadcasterId: 'broadcaster',
        userId: '100',
        nickname: '旧コテハン',
      );

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      expect(find.text('旧コテハン'), findsOneWidget);

      await tester.tap(find.byKey(const Key('nickname-edit-0')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('nickname-edit-field')),
        '新コテハン',
      );
      await tester.tap(find.byKey(const Key('nickname-edit-save-button')));
      await tester.pumpAndSettle();

      expect(find.text('新コテハン'), findsOneWidget);
      expect(find.text('旧コテハン'), findsNothing);

      final Map<String, String> saved = await store.loadNicknames(
        'broadcaster',
      );
      expect(saved, <String, String>{'100': '新コテハン'});
    });

    testWidgets('clear button removes nickname', (WidgetTester tester) async {
      final InMemoryUserAttributeStore store = InMemoryUserAttributeStore();
      await store.setNickname(
        broadcasterId: 'broadcaster',
        userId: '100',
        nickname: '削除対象',
      );

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nickname-edit-0')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nickname-edit-clear-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nickname-list-empty')), findsOneWidget);

      final Map<String, String> saved = await store.loadNicknames(
        'broadcaster',
      );
      expect(saved, isEmpty);
    });
  });
}

Widget _buildScreen(InMemoryUserAttributeStore store) {
  return MaterialApp(
    home: NicknameListScreen(
      userAttributeStore: store,
      broadcasterId: 'broadcaster',
    ),
  );
}
