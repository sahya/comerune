import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/presentation/screens/broadcaster_ng_detail_screen.dart';
import 'package:comerune/presentation/screens/ng_user_list_screen.dart';
import 'package:comerune/presentation/screens/ng_word_list_screen.dart';

import '../../helpers/fake_broadcaster_ng_store.dart';

void main() {
  group('BroadcasterNgDetailScreen', () {
    testWidgets('renders both NG users and NG words tiles with the scope '
        'label in the AppBar', (WidgetTester tester) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-1');

      await tester.pumpWidget(
        MaterialApp(
          home: BroadcasterNgDetailScreen(
            broadcasterNgStore: store,
            broadcasterId: 'caster-1',
            scopeLabel: 'caster-1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('broadcaster-ng-detail-users-tile')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('broadcaster-ng-detail-words-tile')),
        findsOneWidget,
      );
      expect(find.text('NG設定 — caster-1'), findsOneWidget);
    });

    testWidgets('tapping the NG users tile pushes NgUserListScreen', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-1');

      await tester.pumpWidget(
        MaterialApp(
          home: BroadcasterNgDetailScreen(
            broadcasterNgStore: store,
            broadcasterId: 'caster-1',
            scopeLabel: 'caster-1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('broadcaster-ng-detail-users-tile')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NgUserListScreen), findsOneWidget);
    });

    testWidgets('tapping the NG words tile pushes NgWordListScreen', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-1');

      await tester.pumpWidget(
        MaterialApp(
          home: BroadcasterNgDetailScreen(
            broadcasterNgStore: store,
            broadcasterId: 'caster-1',
            scopeLabel: 'caster-1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('broadcaster-ng-detail-words-tile')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NgWordListScreen), findsOneWidget);
    });

    testWidgets('template scope shows the template-specific banner', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore();

      await tester.pumpWidget(
        MaterialApp(
          home: BroadcasterNgDetailScreen(
            broadcasterNgStore: store,
            broadcasterId: null,
            scopeLabel: 'テンプレート',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('テンプレート（新規放送者の初期値）の編集です'), findsOneWidget);
    });
  });
}
