import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/presentation/screens/broadcaster_ng_edit_screen.dart';
import 'package:comerune/presentation/screens/ng_user_list_view.dart';
import 'package:comerune/presentation/screens/ng_word_list_view.dart';

import '../../helpers/fake_broadcaster_ng_store.dart';

void main() {
  group('BroadcasterNgEditScreen', () {
    testWidgets('renders both NGユーザー and NGワード tabs with their labels', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-1');

      await tester.pumpWidget(
        MaterialApp(
          home: BroadcasterNgEditScreen(
            broadcasterNgStore: store,
            broadcasterId: 'caster-1',
            scopeLabel: 'caster-1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('broadcaster-ng-edit-tab-bar')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('broadcaster-ng-edit-users-tab')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('broadcaster-ng-edit-words-tab')),
        findsOneWidget,
      );
      expect(find.text('NGユーザー'), findsOneWidget);
      expect(find.text('NGワード'), findsOneWidget);
      expect(find.byIcon(Icons.person_off), findsWidgets);
      expect(find.byIcon(Icons.block), findsOneWidget);
    });

    testWidgets('AppBar title contains the scope label', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-1');

      await tester.pumpWidget(
        MaterialApp(
          home: BroadcasterNgEditScreen(
            broadcasterNgStore: store,
            broadcasterId: 'caster-1',
            scopeLabel: 'caster-1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('NG設定 — caster-1'), findsOneWidget);
    });

    testWidgets(
      'broadcaster scope (non-null id) does NOT show the template banner',
      (WidgetTester tester) async {
        final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
          ..seedBroadcaster('caster-1');

        await tester.pumpWidget(
          MaterialApp(
            home: BroadcasterNgEditScreen(
              broadcasterNgStore: store,
              broadcasterId: 'caster-1',
              scopeLabel: 'caster-1',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('broadcaster-ng-edit-template-banner')),
          findsNothing,
        );
      },
    );

    testWidgets('template scope (null id) shows the template banner', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore();

      await tester.pumpWidget(
        MaterialApp(
          home: BroadcasterNgEditScreen(
            broadcasterNgStore: store,
            broadcasterId: null,
            scopeLabel: 'テンプレート',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('broadcaster-ng-edit-template-banner')),
        findsOneWidget,
      );
      expect(find.text('テンプレート: 新規放送者の初期値として使われます'), findsOneWidget);
    });

    testWidgets('initial tab is NGユーザー (NgUserListView visible)', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-1');

      await tester.pumpWidget(
        MaterialApp(
          home: BroadcasterNgEditScreen(
            broadcasterNgStore: store,
            broadcasterId: 'caster-1',
            scopeLabel: 'caster-1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NgUserListView), findsOneWidget);
    });

    testWidgets('switching to NGワード tab shows NgWordListView', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-1');

      await tester.pumpWidget(
        MaterialApp(
          home: BroadcasterNgEditScreen(
            broadcasterNgStore: store,
            broadcasterId: 'caster-1',
            scopeLabel: 'caster-1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('broadcaster-ng-edit-words-tab')));
      await tester.pumpAndSettle();

      expect(find.byType(NgWordListView), findsOneWidget);
      // The NG word add button lives inside the words tab body.
      expect(find.byKey(const Key('ng-word-add-button')), findsOneWidget);
    });

    testWidgets('long scopeLabel is truncated in the AppBar title', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-1');
      const String longLabel =
          'this-is-a-very-long-broadcaster-label-1234567890';

      await tester.pumpWidget(
        MaterialApp(
          home: BroadcasterNgEditScreen(
            broadcasterNgStore: store,
            broadcasterId: 'caster-1',
            scopeLabel: longLabel,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Truncated to 20 chars + ellipsis.
      expect(find.text('NG設定 — this-is-a-very-long-…'), findsOneWidget);
    });
  });
}
