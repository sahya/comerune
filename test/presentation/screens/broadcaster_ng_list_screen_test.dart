import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/data/filter/broadcaster_ng_store.dart';
import 'package:comerune/domain/models/ng_word_rule.dart';
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

      expect(
        find.byKey(const Key('broadcaster-ng-list-broadcaster-tile-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('broadcaster-ng-list-broadcaster-tile-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('broadcaster-ng-list-broadcaster-tile-2')),
        findsOneWidget,
      );
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

      await tester.tap(
        find.byKey(const Key('broadcaster-ng-list-broadcaster-tile-0')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BroadcasterNgDetailScreen), findsOneWidget);
      expect(find.text('NG設定 — caster-a'), findsOneWidget);
    });

    testWidgets(
      'badge follows the active-broadcaster notifier across changes',
      (WidgetTester tester) async {
        final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
          ..seedBroadcaster('b1')
          ..seedBroadcaster('b2');
        final ValueNotifier<String?> notifier = ValueNotifier<String?>('b1');

        await tester.pumpWidget(_buildScreen(store, activeNotifier: notifier));
        await tester.pumpAndSettle();

        // Initially, badge sits under "b1".
        final ListTile tile0 = tester.widget(
          find.byKey(const Key('broadcaster-ng-list-broadcaster-tile-0')),
        );
        expect(
          (tile0.subtitle as Text?)?.key,
          const Key('broadcaster-ng-active-badge'),
        );
        final ListTile tile1Initial = tester.widget(
          find.byKey(const Key('broadcaster-ng-list-broadcaster-tile-1')),
        );
        expect(tile1Initial.subtitle, isNull);

        // Mutate the notifier; the badge should move to "b2".
        notifier.value = 'b2';
        await tester.pump();

        final ListTile tile0After = tester.widget(
          find.byKey(const Key('broadcaster-ng-list-broadcaster-tile-0')),
        );
        expect(tile0After.subtitle, isNull);
        final ListTile tile1After = tester.widget(
          find.byKey(const Key('broadcaster-ng-list-broadcaster-tile-1')),
        );
        expect(
          (tile1After.subtitle as Text?)?.key,
          const Key('broadcaster-ng-active-badge'),
        );

        notifier.dispose();
      },
    );

    testWidgets('keeps previous list when listBroadcasters() throws', (
      WidgetTester tester,
    ) async {
      final _ThrowingListBroadcasterNgStore store =
          _ThrowingListBroadcasterNgStore();

      await tester.pumpWidget(
        MaterialApp(home: BroadcasterNgListScreen(broadcasterNgStore: store)),
      );
      await tester.pumpAndSettle();

      // Initial list (built in initState before we flip the throw flag) is
      // empty. Pull-to-refresh after a throw should not crash.
      store.shouldThrow = true;
      await tester.fling(
        find.byKey(const Key('broadcaster-ng-list-view')),
        const Offset(0, 400),
        1500,
      );
      await tester.pumpAndSettle();

      // Empty-state still rendered, no exception thrown.
      expect(
        find.byKey(const Key('broadcaster-ng-list-empty')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows SnackBar when pull-to-refresh fails', (
      WidgetTester tester,
    ) async {
      final _ThrowingListBroadcasterNgStore store =
          _ThrowingListBroadcasterNgStore();

      await tester.pumpWidget(
        MaterialApp(home: BroadcasterNgListScreen(broadcasterNgStore: store)),
      );
      await tester.pumpAndSettle();

      store.shouldThrow = true;
      await tester.fling(
        find.byKey(const Key('broadcaster-ng-list-view')),
        const Offset(0, 400),
        1500,
      );
      await tester.pumpAndSettle();

      expect(find.text('放送者一覧の更新に失敗しました'), findsOneWidget);
    });
  });
}

class _ThrowingListBroadcasterNgStore implements BroadcasterNgStore {
  bool shouldThrow = false;

  @override
  List<String> listBroadcasters() {
    if (shouldThrow) {
      throw StateError('boom');
    }
    return const <String>[];
  }

  @override
  Future<void> addNgUserId(String broadcasterId, String userId) async {}

  @override
  Future<void> flushPendingWrites() async {}

  @override
  Future<BroadcasterNgPayload> loadBroadcasterNgAttributes(
    String broadcasterId,
  ) async => (ngUserIds: <String>{}, rules: <NgWordRule>[]);

  @override
  Future<Set<String>> loadNgUserIds(String broadcasterId) async => <String>{};

  @override
  Future<List<NgWordRule>> loadNgWordRules(String broadcasterId) async =>
      <NgWordRule>[];

  @override
  Future<Set<String>> loadTemplateNgUserIds() async => <String>{};

  @override
  Future<List<NgWordRule>> loadTemplateNgWordRules() async => <NgWordRule>[];

  @override
  Future<void> removeNgUserId(String broadcasterId, String userId) async {}

  @override
  Future<void> saveNgUserIds(
    String broadcasterId,
    Iterable<String> ids,
  ) async {}

  @override
  Future<void> saveNgWordRules(
    String broadcasterId,
    List<NgWordRule> rules,
  ) async {}

  @override
  Future<void> saveTemplateNgUserIds(Iterable<String> ids) async {}

  @override
  Future<void> saveTemplateNgWordRules(List<NgWordRule> rules) async {}
}
