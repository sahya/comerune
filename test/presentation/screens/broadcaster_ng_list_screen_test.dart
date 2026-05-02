import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/presentation/screens/broadcaster_ng_detail_screen.dart';
import 'package:comerune/presentation/screens/broadcaster_ng_list_screen.dart';

import '../../helpers/fake_broadcaster_ng_store.dart';

Widget _buildScreen(
  FakeBroadcasterNgStore store, {
  ValueNotifier<String?>? activeNotifier,
}) {
  return MaterialApp(
    home: BroadcasterNgListScreen(
      broadcasterNgStore: store,
      broadcasterIdNotifier: activeNotifier,
    ),
  );
}

void main() {
  group('BroadcasterNgListScreen', () {
    testWidgets('shows the template tile and the empty-list notice when no '
        'broadcasters have per-broadcaster slots', (WidgetTester tester) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore();

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('broadcaster-ng-template-tile')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('broadcaster-ng-list-empty')),
        findsOneWidget,
      );
      expect(find.text('まだ放送者ごとの NG 設定はありません'), findsOneWidget);
    });

    testWidgets('renders broadcasters in listBroadcasters() order', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-a')
        ..seedBroadcaster('caster-b')
        ..seedBroadcaster('caster-c');

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('broadcaster-ng-tile-0')), findsOneWidget);
      expect(find.byKey(const Key('broadcaster-ng-tile-1')), findsOneWidget);
      expect(find.byKey(const Key('broadcaster-ng-tile-2')), findsOneWidget);
      expect(find.text('caster-a'), findsOneWidget);
      expect(find.text('caster-b'), findsOneWidget);
      expect(find.text('caster-c'), findsOneWidget);
      expect(find.byKey(const Key('broadcaster-ng-list-empty')), findsNothing);
    });

    testWidgets('decorates the active broadcaster with a 「現在接続中」 badge', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-a')
        ..seedBroadcaster('caster-b');
      final ValueNotifier<String?> notifier = ValueNotifier<String?>(
        'caster-b',
      );

      await tester.pumpWidget(_buildScreen(store, activeNotifier: notifier));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('broadcaster-ng-active-badge')),
        findsOneWidget,
      );
      expect(find.text('現在接続中'), findsOneWidget);

      notifier.dispose();
    });

    testWidgets('pull-to-refresh re-reads listBroadcasters()', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-a');

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      expect(find.text('caster-a'), findsOneWidget);
      expect(find.text('caster-b'), findsNothing);

      // Add a broadcaster behind the screen's back, then pull to refresh.
      store.seedBroadcaster('caster-b');

      await tester.fling(
        find.byKey(const Key('broadcaster-ng-list-view')),
        const Offset(0, 400),
        1500,
      );
      await tester.pumpAndSettle();

      expect(find.text('caster-b'), findsOneWidget);
    });

    testWidgets('tapping the template tile pushes the detail screen with '
        'broadcasterId == null', (WidgetTester tester) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore();

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('broadcaster-ng-template-tile')));
      await tester.pumpAndSettle();

      // Detail screen rendered.
      expect(find.byType(BroadcasterNgDetailScreen), findsOneWidget);
      expect(find.text('NG設定 — テンプレート'), findsOneWidget);
    });

    testWidgets('tapping a broadcaster tile pushes the detail screen with '
        'that scope', (WidgetTester tester) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-a');

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('broadcaster-ng-tile-0')));
      await tester.pumpAndSettle();

      expect(find.byType(BroadcasterNgDetailScreen), findsOneWidget);
      expect(find.text('NG設定 — caster-a'), findsOneWidget);
    });
  });
}
