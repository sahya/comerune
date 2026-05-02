import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/data/filter/broadcaster_ng_store.dart';
import 'package:comerune/domain/models/ng_word_rule.dart';
import 'package:comerune/presentation/screens/ng_word_list_screen.dart';

import '../../helpers/fake_broadcaster_ng_store.dart';

Widget _buildScreen(
  FakeBroadcasterNgStore store, {
  required String? broadcasterId,
  required String scopeLabel,
}) {
  return MaterialApp(
    home: NgWordListScreen(
      broadcasterNgStore: store,
      broadcasterId: broadcasterId,
      scopeLabel: scopeLabel,
    ),
  );
}

void main() {
  group('NgWordListScreen (broadcaster scope)', () {
    testWidgets('shows loading then displays rule list', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster(
          'caster-1',
          rules: const <NgWordRule>[
            NgWordRule(pattern: 'badword'),
            NgWordRule(pattern: 'another', enabled: false),
          ],
        );

      await tester.pumpWidget(
        _buildScreen(store, broadcasterId: 'caster-1', scopeLabel: 'caster-1'),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ng-word-list')), findsOneWidget);
      expect(find.text('badword'), findsOneWidget);
      expect(find.text('another'), findsOneWidget);
    });

    testWidgets('shows empty message when no rules exist', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-1');

      await tester.pumpWidget(
        _buildScreen(store, broadcasterId: 'caster-1', scopeLabel: 'caster-1'),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ng-word-list-empty')), findsOneWidget);
      expect(find.text('NGワードは登録されていません'), findsOneWidget);
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

      expect(find.byKey(const Key('ng-word-local-notice')), findsOneWidget);
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
      expect(find.byKey(const Key('ng-word-local-notice')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();
    });

    testWidgets('toggle rule enabled state and persist', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster(
          'caster-1',
          rules: const <NgWordRule>[NgWordRule(pattern: 'word1')],
        );

      await tester.pumpWidget(
        _buildScreen(store, broadcasterId: 'caster-1', scopeLabel: 'caster-1'),
      );
      await tester.pumpAndSettle();

      final Switch toggle = tester.widget(
        find.byKey(const Key('ng-word-toggle-0')),
      );
      expect(toggle.value, isTrue);

      await tester.tap(find.byKey(const Key('ng-word-toggle-0')));
      await tester.pumpAndSettle();

      final List<NgWordRule> persisted = await store.loadNgWordRules(
        'caster-1',
      );
      expect(persisted.first.enabled, isFalse);
    });

    testWidgets('delete rule with confirmation dialog', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster(
          'caster-1',
          rules: const <NgWordRule>[NgWordRule(pattern: 'to-delete')],
        );

      await tester.pumpWidget(
        _buildScreen(store, broadcasterId: 'caster-1', scopeLabel: 'caster-1'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ng-word-delete-0')));
      await tester.pumpAndSettle();

      expect(find.text('NGワード削除'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ng-word-delete-confirm-button')));
      await tester.pumpAndSettle();

      expect(find.text('to-delete'), findsNothing);

      final List<NgWordRule> persisted = await store.loadNgWordRules(
        'caster-1',
      );
      expect(persisted, isEmpty);
    });

    testWidgets('add rule via dialog', (WidgetTester tester) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-1');

      await tester.pumpWidget(
        _buildScreen(store, broadcasterId: 'caster-1', scopeLabel: 'caster-1'),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ng-word-list-empty')), findsOneWidget);

      await tester.tap(find.byKey(const Key('ng-word-add-button')));
      await tester.pumpAndSettle();

      expect(find.text('NGワード追加'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('ng-word-add-input')),
        'newword',
      );
      await tester.tap(find.byKey(const Key('ng-word-add-confirm-button')));
      await tester.pumpAndSettle();

      expect(find.text('newword'), findsOneWidget);

      final List<NgWordRule> persisted = await store.loadNgWordRules(
        'caster-1',
      );
      expect(persisted.length, 1);
      expect(persisted.first.pattern, 'newword');
      expect(persisted.first.enabled, isTrue);
    });

    testWidgets('rejects invalid regex with snackbar error', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-1');

      await tester.pumpWidget(
        _buildScreen(store, broadcasterId: 'caster-1', scopeLabel: 'caster-1'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ng-word-add-button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('ng-word-add-input')),
        '[invalid',
      );
      await tester.tap(find.byKey(const Key('ng-word-add-confirm-button')));
      await tester.pumpAndSettle();

      expect(find.text('無効なパターンです'), findsOneWidget);

      final List<NgWordRule> persisted = await store.loadNgWordRules(
        'caster-1',
      );
      expect(persisted, isEmpty);
    });

    testWidgets('ignores empty input from add dialog', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster('caster-1');

      await tester.pumpWidget(
        _buildScreen(store, broadcasterId: 'caster-1', scopeLabel: 'caster-1'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ng-word-add-button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ng-word-add-confirm-button')));
      await tester.pumpAndSettle();

      final List<NgWordRule> persisted = await store.loadNgWordRules(
        'caster-1',
      );
      expect(persisted, isEmpty);
    });

    testWidgets('rejects duplicate pattern with snackbar', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster(
          'caster-1',
          rules: const <NgWordRule>[NgWordRule(pattern: 'existing')],
        );

      await tester.pumpWidget(
        _buildScreen(store, broadcasterId: 'caster-1', scopeLabel: 'caster-1'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ng-word-add-button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('ng-word-add-input')),
        'existing',
      );
      await tester.tap(find.byKey(const Key('ng-word-add-confirm-button')));
      await tester.pumpAndSettle();

      expect(find.text('同じパターンが既に登録されています'), findsOneWidget);

      final List<NgWordRule> persisted = await store.loadNgWordRules(
        'caster-1',
      );
      expect(persisted.length, 1);
    });

    testWidgets('disabled rule shows greyed out text', (
      WidgetTester tester,
    ) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedBroadcaster(
          'caster-1',
          rules: const <NgWordRule>[
            NgWordRule(pattern: 'disabled-word', enabled: false),
          ],
        );

      await tester.pumpWidget(
        _buildScreen(store, broadcasterId: 'caster-1', scopeLabel: 'caster-1'),
      );
      await tester.pumpAndSettle();

      final Text text = tester.widget(find.text('disabled-word'));
      expect(text.style?.color, Colors.grey);
    });
  });

  group('NgWordListScreen (template scope)', () {
    testWidgets('reads and writes the template list when broadcasterId is '
        'null', (WidgetTester tester) async {
      final FakeBroadcasterNgStore store = FakeBroadcasterNgStore()
        ..seedTemplate(rules: const <NgWordRule>[NgWordRule(pattern: 'tpl')]);

      await tester.pumpWidget(
        _buildScreen(store, broadcasterId: null, scopeLabel: 'テンプレート'),
      );
      await tester.pumpAndSettle();

      expect(find.text('tpl'), findsOneWidget);

      // Add another pattern; verify it lands in the template store.
      await tester.tap(find.byKey(const Key('ng-word-add-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('ng-word-add-input')),
        'tpl-new',
      );
      await tester.tap(find.byKey(const Key('ng-word-add-confirm-button')));
      await tester.pumpAndSettle();

      final List<NgWordRule> tpl = await store.loadTemplateNgWordRules();
      expect(tpl.map((NgWordRule r) => r.pattern).toList(), <String>[
        'tpl',
        'tpl-new',
      ]);
    });
  });

  group('NgWordListScreen (load failure)', () {
    testWidgets('shows error UI with retry when the store throws', (
      WidgetTester tester,
    ) async {
      final _ThrowingBroadcasterNgStore store = _ThrowingBroadcasterNgStore();

      await tester.pumpWidget(
        MaterialApp(
          home: NgWordListScreen(
            broadcasterNgStore: store,
            broadcasterId: 'caster-1',
            scopeLabel: 'caster-1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ng-word-list-error')), findsOneWidget);
      expect(find.text('NG リストの読込みに失敗しました'), findsOneWidget);
      expect(find.byKey(const Key('ng-word-list-retry')), findsOneWidget);

      // Retry succeeds when the throw flag is cleared.
      store.shouldThrow = false;
      await tester.tap(find.byKey(const Key('ng-word-list-retry')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ng-word-list-error')), findsNothing);
    });
  });
}

class _ThrowingBroadcasterNgStore implements BroadcasterNgStore {
  bool shouldThrow = true;

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
    return <String>{};
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
