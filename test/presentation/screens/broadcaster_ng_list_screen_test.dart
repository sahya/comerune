import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/data/filter/broadcaster_ng_store.dart';
import 'package:comerune/domain/models/ng_word_rule.dart';
import 'package:comerune/presentation/screens/broadcaster_ng_edit_screen.dart';
import 'package:comerune/presentation/screens/broadcaster_ng_list_screen.dart';

import '../../helpers/fake_broadcaster_ng_store.dart';

Widget _buildScreen(
  FakeBroadcasterNgStore store, {
  ValueNotifier<String?>? activeNotifier,
  String? Function(String broadcasterId)? nameResolver,
  Map<String, String> Function()? namesSnapshot,
}) {
  return MaterialApp(
    home: BroadcasterNgListScreen(
      broadcasterNgStore: store,
      broadcasterIdNotifier: activeNotifier,
      broadcasterNameResolver: nameResolver,
      broadcasterNamesSnapshot: namesSnapshot,
    ),
  );
}

void main() {
  group('BroadcasterNgListScreen', () {
    testWidgets('shows the empty-list notice when no broadcasters have '
        'per-broadcaster slots, and does NOT show a template tile', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore();

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('broadcaster-ng-template-tile')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('broadcaster-ng-list-empty')),
        findsOneWidget,
      );
      expect(find.text('まだ放送者ごとの NG 設定はありません'), findsOneWidget);
      // Tutorial line.
      expect(
        find.text('コメント画面で長押しして NG 登録すると、その放送者の設定として記録されます'),
        findsOneWidget,
      );
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
      // Without a name resolver, tile titles are raw broadcaster IDs.
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

    testWidgets('tile title shows 名前(ID) when the resolver returns a name', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-a');

      await tester.pumpWidget(
        _buildScreen(
          store,
          nameResolver: (String id) => id == 'caster-a' ? 'Alice' : null,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alice(caster-a)'), findsOneWidget);
      // Raw ID should not appear on its own as the tile title.
      expect(find.text('caster-a'), findsNothing);
    });

    testWidgets('tile title shows just ID when the resolver returns null', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-a');

      await tester.pumpWidget(
        _buildScreen(store, nameResolver: (String id) => null),
      );
      await tester.pumpAndSettle();

      expect(find.text('caster-a'), findsOneWidget);
      // No "()" rendering for unknown names.
      expect(find.textContaining('()'), findsNothing);
    });

    testWidgets('tile title shows just ID when the resolver returns empty', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-a');

      await tester.pumpWidget(
        _buildScreen(store, nameResolver: (String id) => ''),
      );
      await tester.pumpAndSettle();

      expect(find.text('caster-a'), findsOneWidget);
      expect(find.textContaining('()'), findsNothing);
    });

    testWidgets('tapping a tile pushes the edit screen with scopeLabel == '
        'name when name is known', (WidgetTester tester) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-a');

      await tester.pumpWidget(
        _buildScreen(
          store,
          nameResolver: (String id) => id == 'caster-a' ? 'Alice' : null,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('broadcaster-ng-list-broadcaster-tile-0')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BroadcasterNgEditScreen), findsOneWidget);
      // AppBar title is "NG 設定 - <name>" (just the name, no parenthesised ID).
      expect(find.text('NG 設定 - Alice'), findsOneWidget);
    });

    testWidgets('tapping a tile pushes the edit screen with scopeLabel == ID '
        'when name is unknown', (WidgetTester tester) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-a');

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('broadcaster-ng-list-broadcaster-tile-0')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BroadcasterNgEditScreen), findsOneWidget);
      expect(find.text('NG 設定 - caster-a'), findsOneWidget);
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

    testWidgets('prefers the snapshot over the per-id resolver', (
      WidgetTester tester,
    ) async {
      // If the snapshot path is taken, the throwing resolver must never
      // be invoked — and names should still render from the snapshot.
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-a')
        ..seedBroadcaster('caster-b');

      await tester.pumpWidget(
        _buildScreen(
          store,
          nameResolver: (String id) =>
              throw StateError('resolver should not be called'),
          namesSnapshot: () => <String, String>{
            'caster-a': 'Alice',
            'caster-b': 'Bob',
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Alice(caster-a)'), findsOneWidget);
      expect(find.text('Bob(caster-b)'), findsOneWidget);
    });

    testWidgets('snapshot missing the broadcasterId falls back to ID-only '
        '(does NOT consult per-id resolver)', (WidgetTester tester) async {
      // Snapshot path is authoritative once chosen: when the snapshot is
      // non-null but does not contain a key for `broadcasterId`, the tile
      // renders as raw ID — the per-id resolver is intentionally not
      // consulted as a secondary fallback. This locks in that contract.
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-a');

      await tester.pumpWidget(
        _buildScreen(
          store,
          nameResolver: (String id) =>
              throw StateError('resolver should not be called'),
          // Snapshot is supplied (non-null) but doesn't have caster-a.
          namesSnapshot: () => const <String, String>{},
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('caster-a'), findsOneWidget);
      expect(find.textContaining('()'), findsNothing);
    });

    testWidgets('long 名前(ID) renders without overflow on a narrow viewport', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(240, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const String longName = 'とても長い放送者名前ABCDEFGHIJKLMNOPQRSTUVWXYZ';
      const String longId = 'broadcaster-id-0123456789-0123456789-0123456789';
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster(longId);

      await tester.pumpWidget(
        _buildScreen(
          store,
          nameResolver: (String id) => id == longId ? longName : null,
        ),
      );
      await tester.pumpAndSettle();

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
