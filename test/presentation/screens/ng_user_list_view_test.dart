import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/data/filter/broadcaster_ng_store.dart';
import 'package:comerune/domain/models/ng_word_rule.dart';
import 'package:comerune/presentation/screens/ng_user_list_view.dart';

import '../../helpers/fake_broadcaster_ng_store.dart';

Widget _buildView(
  FakeBroadcasterNgStore store, {
  required String? broadcasterId,
}) {
  return MaterialApp(
    home: Scaffold(
      body: NgUserListView(
        broadcasterNgStore: store,
        broadcasterId: broadcasterId,
      ),
    ),
  );
}

void main() {
  group('NgUserListView (broadcaster scope)', () {
    testWidgets('shows empty message when no NG user IDs exist', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-1');

      await tester.pumpWidget(_buildView(store, broadcasterId: 'caster-1'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ng-user-list-empty')), findsOneWidget);
      expect(find.text('NGユーザーIDは登録されていません'), findsOneWidget);
    });

    testWidgets('shows local-only settings notice after load', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-1');

      await tester.pumpWidget(_buildView(store, broadcasterId: 'caster-1'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ng-user-local-notice')), findsOneWidget);
      expect(find.textContaining('ニコニコのサービスとは連携していません'), findsOneWidget);
    });

    testWidgets('shows local-only settings notice while loading', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-1');

      await tester.pumpWidget(_buildView(store, broadcasterId: 'caster-1'));
      // Do NOT pumpAndSettle: the notice must be visible even before the
      // settings load completes.
      expect(find.byKey(const Key('ng-user-local-notice')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();
    });

    testWidgets('displays registered NG user IDs as list', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-1', userIds: <String>{'user123', 'user456'});

      await tester.pumpWidget(_buildView(store, broadcasterId: 'caster-1'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ng-user-id-list')), findsOneWidget);
      expect(find.text('user123'), findsOneWidget);
      expect(find.text('user456'), findsOneWidget);
      expect(find.byKey(const Key('ng-user-remove-0')), findsOneWidget);
      expect(find.byKey(const Key('ng-user-remove-1')), findsOneWidget);
    });

    testWidgets('removes NG user ID after confirmation', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-1', userIds: <String>{'user123', 'user456'});

      await tester.pumpWidget(_buildView(store, broadcasterId: 'caster-1'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ng-user-remove-0')));
      await tester.pumpAndSettle();

      expect(find.text('NG解除'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ng-remove-confirm-button')));
      await tester.pumpAndSettle();

      expect(find.text('user456'), findsOneWidget);
      // Snackbar feedback should appear.
      expect(find.textContaining('のNGを解除しました'), findsOneWidget);

      // Verify persistence on the store.
      final Set<String> remaining = await store.loadNgUserIds('caster-1');
      expect(remaining.length, 1);
      expect(remaining.contains('user456'), isTrue);
    });

    testWidgets('cancel dialog does not remove NG user ID', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-1', userIds: <String>{'user123'});

      await tester.pumpWidget(_buildView(store, broadcasterId: 'caster-1'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ng-user-remove-0')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      expect(find.text('user123'), findsOneWidget);

      final Set<String> remaining = await store.loadNgUserIds('caster-1');
      expect(remaining, <String>{'user123'});
    });
  });

  group('NgUserListView (template scope)', () {
    testWidgets('reads and writes the template list when broadcasterId is '
        'null', (WidgetTester tester) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedTemplate(userIds: <String>{'tpl-user'});

      await tester.pumpWidget(_buildView(store, broadcasterId: null));
      await tester.pumpAndSettle();

      expect(find.text('tpl-user'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ng-user-remove-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ng-remove-confirm-button')));
      await tester.pumpAndSettle();

      // Template should be empty now.
      final Set<String> tpl = await store.loadTemplateNgUserIds();
      expect(tpl, isEmpty);
    });
  });

  group('NgUserListView (load failure)', () {
    testWidgets('shows error UI with retry when the store throws', (
      WidgetTester tester,
    ) async {
      final _ThrowingBroadcasterNgStore store = _ThrowingBroadcasterNgStore();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NgUserListView(
              broadcasterNgStore: store,
              broadcasterId: 'caster-1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ng-user-list-error')), findsOneWidget);
      expect(find.text('NG リストの読込みに失敗しました'), findsOneWidget);
      expect(find.byKey(const Key('ng-user-list-retry')), findsOneWidget);

      // Retry succeeds when the throw flag is cleared.
      store.shouldThrow = false;
      await tester.tap(find.byKey(const Key('ng-user-list-retry')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ng-user-list-error')), findsNothing);
    });

    testWidgets('retry recovers and renders the list correctly', (
      WidgetTester tester,
    ) async {
      final _ThrowingBroadcasterNgStore store = _ThrowingBroadcasterNgStore()
        ..seededIds = <String>{'recovered-user'};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NgUserListView(
              broadcasterNgStore: store,
              broadcasterId: 'caster-1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ng-user-list-error')), findsOneWidget);

      // Flip throw flag and retry.
      store.shouldThrow = false;
      await tester.tap(find.byKey(const Key('ng-user-list-retry')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ng-user-list-error')), findsNothing);
      expect(find.byKey(const Key('ng-user-id-list')), findsOneWidget);
      expect(find.text('recovered-user'), findsOneWidget);
    });
  });
}

class _ThrowingBroadcasterNgStore implements BroadcasterNgStore {
  bool shouldThrow = true;
  Set<String> seededIds = <String>{};

  @override
  Future<void> addNgUserId(String broadcasterId, String userId) async {}

  @override
  Future<void> flushPendingWrites() async {}

  @override
  List<String> listBroadcasters() => const <String>[];

  @override
  Future<BroadcasterNgPayload> loadBroadcasterNgAttributes(
    String broadcasterId,
  ) async => (ngUserIds: <String>{}, rules: <NgWordRule>[]);

  @override
  Future<Set<String>> loadNgUserIds(String broadcasterId) async {
    if (shouldThrow) throw StateError('boom');
    return seededIds.toSet();
  }

  @override
  Future<List<NgWordRule>> loadNgWordRules(String broadcasterId) async {
    if (shouldThrow) throw StateError('boom');
    return <NgWordRule>[];
  }

  @override
  Future<Set<String>> loadTemplateNgUserIds() async {
    if (shouldThrow) throw StateError('boom');
    return <String>{};
  }

  @override
  Future<List<NgWordRule>> loadTemplateNgWordRules() async {
    if (shouldThrow) throw StateError('boom');
    return <NgWordRule>[];
  }

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
