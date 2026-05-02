import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/presentation/screens/ng_user_list_screen.dart';

import '../../helpers/fake_broadcaster_ng_store.dart';

void main() {
  group('NgUserListScreen (broadcaster scope)', () {
    testWidgets('shows empty message when no NG user IDs exist', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-1');

      await tester.pumpWidget(
        _buildScreen(store, broadcasterId: 'caster-1', scopeLabel: 'caster-1'),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ng-user-list-empty')), findsOneWidget);
      expect(find.text('NGユーザーIDは登録されていません'), findsOneWidget);
    });

    testWidgets('shows local-only settings notice after load', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-1');

      await tester.pumpWidget(
        _buildScreen(store, broadcasterId: 'caster-1', scopeLabel: 'caster-1'),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ng-user-local-notice')), findsOneWidget);
      expect(find.textContaining('ニコニコのサービスとは連携していません'), findsOneWidget);
    });

    testWidgets('shows local-only settings notice while loading', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-1');

      await tester.pumpWidget(
        _buildScreen(store, broadcasterId: 'caster-1', scopeLabel: 'caster-1'),
      );
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

      await tester.pumpWidget(
        _buildScreen(store, broadcasterId: 'caster-1', scopeLabel: 'caster-1'),
      );
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

      await tester.pumpWidget(
        _buildScreen(store, broadcasterId: 'caster-1', scopeLabel: 'caster-1'),
      );
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

      await tester.pumpWidget(
        _buildScreen(store, broadcasterId: 'caster-1', scopeLabel: 'caster-1'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ng-user-remove-0')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      expect(find.text('user123'), findsOneWidget);

      final Set<String> remaining = await store.loadNgUserIds('caster-1');
      expect(remaining, <String>{'user123'});
    });

    testWidgets('shows scope label in app bar subtitle', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-1');

      await tester.pumpWidget(
        _buildScreen(store, broadcasterId: 'caster-1', scopeLabel: 'caster-1'),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ng-user-scope-label')), findsOneWidget);
      expect(find.text('NGユーザーID — caster-1'), findsOneWidget);
    });
  });

  group('NgUserListScreen (template scope)', () {
    testWidgets('reads and writes the template list when broadcasterId is '
        'null', (WidgetTester tester) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedTemplate(userIds: <String>{'tpl-user'});

      await tester.pumpWidget(
        _buildScreen(store, broadcasterId: null, scopeLabel: 'テンプレート'),
      );
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
}

Widget _buildScreen(
  FakeBroadcasterNgStore store, {
  required String? broadcasterId,
  required String scopeLabel,
}) {
  return MaterialApp(
    home: NgUserListScreen(
      broadcasterNgStore: store,
      broadcasterId: broadcasterId,
      scopeLabel: scopeLabel,
    ),
  );
}
