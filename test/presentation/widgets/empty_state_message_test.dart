import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/presentation/widgets/empty_state_message.dart';

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Widget _buildWidget(EmptyStateMessage widget) {
  return MaterialApp(
    home: Scaffold(body: widget),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('EmptyStateMessage', () {
    testWidgets('renders the supplied message text',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildWidget(
          const EmptyStateMessage(message: 'データがありません'),
        ),
      );

      expect(find.text('データがありません'), findsOneWidget);
    });

    testWidgets('wraps text in a Center widget', (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildWidget(
          const EmptyStateMessage(message: 'テスト'),
        ),
      );

      // The Center must be an ancestor of the Text.
      final Finder text = find.text('テスト');
      expect(
        find.ancestor(of: text, matching: find.byType(Center)),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('applies EdgeInsets.all(24) padding',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildWidget(
          const EmptyStateMessage(message: 'テスト'),
        ),
      );

      // Find the Padding widget that is a direct descendant of Center.
      final Finder center = find.byType(Center).first;
      final Finder padding = find.descendant(
        of: center,
        matching: find.byType(Padding),
      );

      expect(padding, findsAtLeastNWidgets(1));

      final Padding paddingWidget = tester.widget<Padding>(padding.first);
      expect(paddingWidget.padding, const EdgeInsets.all(24));
    });

    testWidgets('renders text with fontSize 14', (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildWidget(
          const EmptyStateMessage(message: 'フォントサイズ確認'),
        ),
      );

      final Text textWidget = tester.widget<Text>(find.text('フォントサイズ確認'));
      expect(textWidget.style?.fontSize, 14.0);
    });

    testWidgets('defaults textAlign to null when not supplied',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildWidget(
          const EmptyStateMessage(message: 'テスト'),
        ),
      );

      final Text textWidget = tester.widget<Text>(find.text('テスト'));
      expect(textWidget.textAlign, isNull);
    });

    testWidgets('passes through a supplied textAlign value',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildWidget(
          const EmptyStateMessage(
            message: 'テスト',
            textAlign: TextAlign.center,
          ),
        ),
      );

      final Text textWidget = tester.widget<Text>(find.text('テスト'));
      expect(textWidget.textAlign, TextAlign.center);
    });

    testWidgets('accepts a widget key', (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildWidget(
          const EmptyStateMessage(
            key: Key('my-empty-state'),
            message: 'テスト',
          ),
        ),
      );

      expect(find.byKey(const Key('my-empty-state')), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Regression: keys used in NgUserListScreen and FavoriteUserListScreen
    // -----------------------------------------------------------------------
    testWidgets(
        'ng-user-list-empty Key is findable and shows the expected message',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildWidget(
          const EmptyStateMessage(
            key: Key('ng-user-list-empty'),
            message: 'NGユーザーIDは登録されていません',
          ),
        ),
      );

      expect(find.byKey(const Key('ng-user-list-empty')), findsOneWidget);
      expect(find.text('NGユーザーIDは登録されていません'), findsOneWidget);
    });

    testWidgets(
        'favorite-user-list-empty Key is findable and shows the expected message',
        (WidgetTester tester) async {
      const String message = 'お気に入りユーザーIDは登録されていません\n'
          '右下のボタンからユーザーIDを追加すると\n'
          '接続画面に放送中の番組が表示されます';

      await tester.pumpWidget(
        _buildWidget(
          const EmptyStateMessage(
            key: Key('favorite-user-list-empty'),
            message: message,
            textAlign: TextAlign.center,
          ),
        ),
      );

      expect(find.byKey(const Key('favorite-user-list-empty')), findsOneWidget);
      expect(find.text(message), findsOneWidget);

      final Text textWidget = tester.widget<Text>(find.text(message));
      expect(textWidget.textAlign, TextAlign.center);
    });
  });
}
