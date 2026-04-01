import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/presentation/widgets/empty_state_message.dart';

Widget _buildHarness({required Widget child}) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('EmptyStateMessage', () {
    testWidgets('renders message text', (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildHarness(child: const EmptyStateMessage(message: 'データがありません')),
      );

      expect(find.text('データがありません'), findsOneWidget);
    });

    testWidgets('is centered', (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildHarness(child: const EmptyStateMessage(message: 'テスト')),
      );

      final Finder text = find.text('テスト');
      expect(
        find.ancestor(of: text, matching: find.byType(Center)),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('keeps regression key for NG empty state', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildHarness(
          child: const EmptyStateMessage(
            key: Key('ng-user-list-empty'),
            message: 'NGユーザーIDは登録されていません',
          ),
        ),
      );

      expect(find.byKey(const Key('ng-user-list-empty')), findsOneWidget);
      expect(find.text('NGユーザーIDは登録されていません'), findsOneWidget);
    });
  });
}
