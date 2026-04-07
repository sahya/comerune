import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/domain/models/ng_word_rule.dart';
import 'package:comerune/presentation/screens/ng_word_list_screen.dart';

import '../../helpers/in_memory_shared_preferences.dart';

Widget _buildScreen(SettingsStore store) {
  return MaterialApp(
    home: NgWordListScreen(settingsStore: store),
  );
}

void main() {
  group('NgWordListScreen', () {
    testWidgets('shows loading then displays rule list', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings initial = AppSettings.defaults.copyWith(
        ngWordRules: const <NgWordRule>[
          NgWordRule(pattern: 'badword'),
          NgWordRule(pattern: 'another', enabled: false),
        ],
      );
      await store.save(initial);

      await tester.pumpWidget(_buildScreen(store));

      // Loading indicator is shown initially.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();

      // Rules are displayed.
      expect(find.byKey(const Key('ng-word-list')), findsOneWidget);
      expect(find.text('badword'), findsOneWidget);
      expect(find.text('another'), findsOneWidget);
    });

    testWidgets('shows empty message when no rules exist', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings initial = AppSettings.defaults.copyWith(
        ngWordRules: const <NgWordRule>[],
      );
      await store.save(initial);

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ng-word-list-empty')), findsOneWidget);
      expect(find.text('NGワードは登録されていません'), findsOneWidget);
    });

    testWidgets('toggle rule enabled state and persist', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings initial = AppSettings.defaults.copyWith(
        ngWordRules: const <NgWordRule>[
          NgWordRule(pattern: 'word1'),
        ],
      );
      await store.save(initial);

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      // Initially enabled — find the Switch and verify.
      final Switch toggle = tester.widget(
        find.byKey(const Key('ng-word-toggle-0')),
      );
      expect(toggle.value, isTrue);

      // Tap to toggle off.
      await tester.tap(find.byKey(const Key('ng-word-toggle-0')));
      await tester.pumpAndSettle();

      // Verify persisted.
      final AppSettings loaded = await store.load();
      expect(loaded.ngWordRules.first.enabled, isFalse);
    });

    testWidgets('delete rule with confirmation dialog', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings initial = AppSettings.defaults.copyWith(
        ngWordRules: const <NgWordRule>[
          NgWordRule(pattern: 'to-delete'),
        ],
      );
      await store.save(initial);

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      // Tap delete button.
      await tester.tap(find.byKey(const Key('ng-word-delete-0')));
      await tester.pumpAndSettle();

      // Confirm dialog appears.
      expect(find.text('NGワード削除'), findsOneWidget);
      expect(find.text('「to-delete」を削除しますか？'), findsOneWidget);

      // Confirm deletion.
      await tester.tap(find.byKey(const Key('ng-word-delete-confirm-button')));
      await tester.pumpAndSettle();

      // Rule removed from UI.
      expect(find.text('to-delete'), findsNothing);

      // Verify persisted.
      final AppSettings loaded = await store.load();
      expect(loaded.ngWordRules, isEmpty);
    });

    testWidgets('add rule via dialog', (WidgetTester tester) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      await store.save(AppSettings.defaults);

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      // Initially empty.
      expect(find.byKey(const Key('ng-word-list-empty')), findsOneWidget);

      // Tap add button.
      await tester.tap(find.byKey(const Key('ng-word-add-button')));
      await tester.pumpAndSettle();

      // Dialog appears.
      expect(find.text('NGワード追加'), findsOneWidget);

      // Enter a pattern.
      await tester.enterText(
        find.byKey(const Key('ng-word-add-input')),
        'newword',
      );
      await tester.tap(find.byKey(const Key('ng-word-add-confirm-button')));
      await tester.pumpAndSettle();

      // Rule appears in list.
      expect(find.text('newword'), findsOneWidget);

      // Verify persisted.
      final AppSettings loaded = await store.load();
      expect(loaded.ngWordRules.length, 1);
      expect(loaded.ngWordRules.first.pattern, 'newword');
      expect(loaded.ngWordRules.first.enabled, isTrue);
    });

    testWidgets('rejects invalid regex with snackbar error', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      await store.save(AppSettings.defaults);

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      // Tap add button.
      await tester.tap(find.byKey(const Key('ng-word-add-button')));
      await tester.pumpAndSettle();

      // Enter an invalid regex pattern.
      await tester.enterText(
        find.byKey(const Key('ng-word-add-input')),
        '[invalid',
      );
      await tester.tap(find.byKey(const Key('ng-word-add-confirm-button')));
      await tester.pumpAndSettle();

      // Error snackbar is shown.
      expect(find.text('無効なパターンです'), findsOneWidget);

      // No rule was added.
      final AppSettings loaded = await store.load();
      expect(loaded.ngWordRules, isEmpty);
    });

    testWidgets('ignores empty input from add dialog', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      await store.save(AppSettings.defaults);

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      // Tap add button.
      await tester.tap(find.byKey(const Key('ng-word-add-button')));
      await tester.pumpAndSettle();

      // Submit empty input.
      await tester.tap(find.byKey(const Key('ng-word-add-confirm-button')));
      await tester.pumpAndSettle();

      // Nothing added — still empty.
      final AppSettings loaded = await store.load();
      expect(loaded.ngWordRules, isEmpty);
    });

    testWidgets('rejects duplicate pattern with snackbar', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings initial = AppSettings.defaults.copyWith(
        ngWordRules: const <NgWordRule>[
          NgWordRule(pattern: 'existing'),
        ],
      );
      await store.save(initial);

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      // Tap add button.
      await tester.tap(find.byKey(const Key('ng-word-add-button')));
      await tester.pumpAndSettle();

      // Enter a duplicate pattern.
      await tester.enterText(
        find.byKey(const Key('ng-word-add-input')),
        'existing',
      );
      await tester.tap(find.byKey(const Key('ng-word-add-confirm-button')));
      await tester.pumpAndSettle();

      // Error snackbar is shown.
      expect(find.text('同じパターンが既に登録されています'), findsOneWidget);

      // No duplicate added.
      final AppSettings loaded = await store.load();
      expect(loaded.ngWordRules.length, 1);
    });

    testWidgets('disabled rule shows greyed out text', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings initial = AppSettings.defaults.copyWith(
        ngWordRules: const <NgWordRule>[
          NgWordRule(pattern: 'disabled-word', enabled: false),
        ],
      );
      await store.save(initial);

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      final Text text = tester.widget(
        find.text('disabled-word'),
      );
      expect(text.style?.color, Colors.grey);
    });
  });
}
