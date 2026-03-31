import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/comment_speech/src/models/replace_rule.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/dictionary_rules_screen.dart';

import '../../helpers/in_memory_shared_preferences.dart';

void main() {
  group('DictionaryRulesScreen', () {
    testWidgets('shows loading then displays rule list', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings initial = AppSettings.defaults.copyWith(
        dictionaryRules: const <ReplaceRule>[
          ReplaceRule(pattern: r'[wｗ]{3,}', replacement: 'わらわら'),
          ReplaceRule(pattern: r'8{3,}', replacement: 'ぱちぱちぱち'),
        ],
      );
      await store.save(initial);

      await tester.pumpWidget(_buildScreen(store));

      // Loading indicator is shown initially.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();

      // Rules are displayed.
      expect(find.byKey(const Key('dictionary-rules-list')), findsOneWidget);
      expect(find.text(r'[wｗ]{3,}'), findsOneWidget);
      expect(find.text('わらわら'), findsOneWidget);
      expect(find.text(r'8{3,}'), findsOneWidget);
      expect(find.text('ぱちぱちぱち'), findsOneWidget);
    });

    testWidgets('shows empty message when no rules exist', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings initial = AppSettings.defaults.copyWith(
        dictionaryRules: const <ReplaceRule>[],
      );
      await store.save(initial);

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dictionary-rules-empty')), findsOneWidget);
      expect(find.text('辞書ルールは登録されていません'), findsOneWidget);
    });

    testWidgets('toggle rule enabled state and persist', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings initial = AppSettings.defaults.copyWith(
        dictionaryRules: const <ReplaceRule>[
          ReplaceRule(pattern: 'test', replacement: 'テスト'),
        ],
      );
      await store.save(initial);

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      // Toggle the switch (initially enabled).
      final Finder toggle = find.byKey(const Key('dictionary-rule-toggle-0'));
      expect(toggle, findsOneWidget);

      await tester.tap(toggle);
      await tester.pumpAndSettle();

      // Verify persistence: rule should now be disabled.
      final AppSettings loaded = await store.load();
      expect(loaded.dictionaryRules.length, 1);
      expect(loaded.dictionaryRules[0].enabled, false);
    });

    testWidgets('built-in rules cannot be deleted but can be disabled', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final ReplaceRule builtInRule = defaultNicoDictionaryRules.firstWhere(
        (ReplaceRule rule) => rule.pattern == '初見',
      );
      final AppSettings initial = AppSettings.defaults.copyWith(
        dictionaryRules: <ReplaceRule>[builtInRule],
      );
      await store.save(initial);

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      final IconButton deleteButton = tester.widget(
        find.byKey(const Key('dictionary-rule-delete-0')),
      );
      expect(deleteButton.onPressed, isNull);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);

      await tester.tap(find.byKey(const Key('dictionary-rule-toggle-0')));
      await tester.pumpAndSettle();

      final AppSettings loaded = await store.load();
      expect(loaded.dictionaryRules, hasLength(1));
      expect(loaded.dictionaryRules.first.enabled, isFalse);
    });

    testWidgets('delete rule with confirmation dialog', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings initial = AppSettings.defaults.copyWith(
        dictionaryRules: const <ReplaceRule>[
          ReplaceRule(pattern: 'aaa', replacement: 'bbb'),
          ReplaceRule(pattern: 'ccc', replacement: 'ddd'),
        ],
      );
      await store.save(initial);

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      // Tap delete for the first rule.
      await tester.tap(find.byKey(const Key('dictionary-rule-delete-0')));
      await tester.pumpAndSettle();

      // Confirm dialog appears.
      expect(find.text('ルール削除'), findsOneWidget);
      expect(find.text('パターン「aaa」を削除しますか？'), findsOneWidget);

      // Tap confirm.
      await tester.tap(find.byKey(const Key('rule-delete-confirm-button')));
      await tester.pumpAndSettle();

      // First rule should be removed.
      expect(find.text('aaa'), findsNothing);
      expect(find.text('ccc'), findsOneWidget);

      // Snackbar feedback.
      expect(find.text('「aaa」を削除しました'), findsOneWidget);

      // Verify persistence.
      final AppSettings loaded = await store.load();
      expect(loaded.dictionaryRules.length, 1);
      expect(loaded.dictionaryRules[0].pattern, 'ccc');
    });

    testWidgets('cancel delete dialog does not remove rule', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings initial = AppSettings.defaults.copyWith(
        dictionaryRules: const <ReplaceRule>[
          ReplaceRule(pattern: 'keep', replacement: 'kept'),
        ],
      );
      await store.save(initial);

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('dictionary-rule-delete-0')));
      await tester.pumpAndSettle();

      // Tap cancel.
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      // Rule should still be present.
      expect(find.text('keep'), findsOneWidget);

      final AppSettings loaded = await store.load();
      expect(loaded.dictionaryRules.length, 1);
    });

    testWidgets('add new rule via form', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings initial = AppSettings.defaults.copyWith(
        dictionaryRules: const <ReplaceRule>[],
      );
      await store.save(initial);

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      // Tap add button.
      await tester.tap(find.byKey(const Key('dictionary-add-button')));
      await tester.pumpAndSettle();

      // Fill in the form.
      await tester.enterText(
        find.byKey(const Key('rule-pattern-field')),
        r'[wｗ]+',
      );
      await tester.enterText(
        find.byKey(const Key('rule-replacement-field')),
        'わら',
      );

      // Save.
      await tester.tap(find.byKey(const Key('rule-form-save-button')));
      await tester.pumpAndSettle();

      // Rule should appear in the list.
      expect(find.text(r'[wｗ]+'), findsOneWidget);
      expect(find.text('わら'), findsOneWidget);

      // Verify persistence.
      final AppSettings loaded = await store.load();
      expect(loaded.dictionaryRules.length, 1);
      expect(loaded.dictionaryRules[0].pattern, r'[wｗ]+');
      expect(loaded.dictionaryRules[0].replacement, 'わら');
      expect(loaded.dictionaryRules[0].enabled, true);
    });

    testWidgets('edit existing rule via form', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings initial = AppSettings.defaults.copyWith(
        dictionaryRules: const <ReplaceRule>[
          ReplaceRule(pattern: 'old', replacement: 'ancient'),
        ],
      );
      await store.save(initial);

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      // Tap the rule tile to edit.
      await tester.tap(find.byKey(const Key('dictionary-rule-tile-0')));
      await tester.pumpAndSettle();

      // Verify form is pre-filled.
      expect(
        find.widgetWithText(TextFormField, 'old'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextFormField, 'ancient'),
        findsOneWidget,
      );

      // Edit the pattern field.
      await tester.enterText(
        find.byKey(const Key('rule-pattern-field')),
        'new',
      );
      await tester.enterText(
        find.byKey(const Key('rule-replacement-field')),
        'modern',
      );

      // Save.
      await tester.tap(find.byKey(const Key('rule-form-save-button')));
      await tester.pumpAndSettle();

      // Updated rule should appear.
      expect(find.text('new'), findsOneWidget);
      expect(find.text('modern'), findsOneWidget);
      expect(find.text('old'), findsNothing);
      expect(find.text('ancient'), findsNothing);

      // Verify persistence.
      final AppSettings loaded = await store.load();
      expect(loaded.dictionaryRules.length, 1);
      expect(loaded.dictionaryRules[0].pattern, 'new');
      expect(loaded.dictionaryRules[0].replacement, 'modern');
    });

    testWidgets('invalid regex pattern shows error and blocks save', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings initial = AppSettings.defaults.copyWith(
        dictionaryRules: const <ReplaceRule>[],
      );
      await store.save(initial);

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      // Tap add button.
      await tester.tap(find.byKey(const Key('dictionary-add-button')));
      await tester.pumpAndSettle();

      // Enter an invalid regex pattern.
      await tester.enterText(
        find.byKey(const Key('rule-pattern-field')),
        '[invalid',
      );
      await tester.enterText(
        find.byKey(const Key('rule-replacement-field')),
        'test',
      );

      // Try to save.
      await tester.tap(find.byKey(const Key('rule-form-save-button')));
      await tester.pumpAndSettle();

      // Error message should appear.
      expect(find.text('無効な正規表現パターンです'), findsOneWidget);

      // Should still be on the form screen (not navigated back).
      expect(find.byKey(const Key('rule-form-body')), findsOneWidget);

      // Nothing should be persisted.
      final AppSettings loaded = await store.load();
      expect(loaded.dictionaryRules, isEmpty);
    });

    testWidgets('empty pattern shows error and blocks save', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings initial = AppSettings.defaults.copyWith(
        dictionaryRules: const <ReplaceRule>[],
      );
      await store.save(initial);

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      // Tap add button.
      await tester.tap(find.byKey(const Key('dictionary-add-button')));
      await tester.pumpAndSettle();

      // Leave pattern empty and try to save.
      await tester.tap(find.byKey(const Key('rule-form-save-button')));
      await tester.pumpAndSettle();

      // Error message should appear.
      expect(find.text('パターンを入力してください'), findsOneWidget);

      // Should still be on the form screen.
      expect(find.byKey(const Key('rule-form-body')), findsOneWidget);
    });
  });
}

Widget _buildScreen(SettingsStore settingsStore) {
  return MaterialApp(
    home: DictionaryRulesScreen(settingsStore: settingsStore),
  );
}
