import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/ng_user_list_screen.dart';

import '../../helpers/in_memory_shared_preferences.dart';

void main() {
  group('NgUserListScreen', () {
    testWidgets('shows empty message when no NG user IDs exist', (
      WidgetTester tester,
    ) async {
      final SettingsStore store = SharedPreferencesSettingsStore(
        prefs: InMemorySharedPreferences(),
      );

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ng-user-list-empty')), findsOneWidget);
      expect(find.text('NGユーザーIDは登録されていません'), findsOneWidget);
    });

    testWidgets('displays registered NG user IDs as list', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      // Pre-save settings with NG user IDs.
      final AppSettings initial = AppSettings.defaults
          .addNgUserId('user123')
          .addNgUserId('user456');
      await store.save(initial);

      await tester.pumpWidget(_buildScreen(store));
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
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings initial = AppSettings.defaults
          .addNgUserId('user123')
          .addNgUserId('user456');
      await store.save(initial);

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      // Tap delete button for the first item.
      await tester.tap(find.byKey(const Key('ng-user-remove-0')));
      await tester.pumpAndSettle();

      // Confirm dialog should appear.
      expect(find.text('NG解除'), findsOneWidget);
      expect(find.text('ユーザーID「user123」のNG登録を解除しますか？'), findsOneWidget);

      // Tap confirm button.
      await tester.tap(find.byKey(const Key('ng-remove-confirm-button')));
      await tester.pumpAndSettle();

      // user123 should be removed from the list.
      expect(find.text('user123'), findsNothing);
      expect(find.text('user456'), findsOneWidget);

      // Snackbar feedback should appear.
      expect(find.text('user123 のNGを解除しました'), findsOneWidget);

      // Verify persistence.
      final AppSettings loaded = await store.load();
      expect(loaded.ngUserIdSet, <String>{'user456'});
    });

    testWidgets('cancel dialog does not remove NG user ID', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings initial = AppSettings.defaults.addNgUserId('user123');
      await store.save(initial);

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ng-user-remove-0')));
      await tester.pumpAndSettle();

      // Tap cancel.
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      // user123 should still be present.
      expect(find.text('user123'), findsOneWidget);

      final AppSettings loaded = await store.load();
      expect(loaded.ngUserIdSet, <String>{'user123'});
    });

    testWidgets('shows empty message after removing last NG user ID', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings initial = AppSettings.defaults.addNgUserId('onlyUser');
      await store.save(initial);

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ng-user-remove-0')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ng-remove-confirm-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ng-user-list-empty')), findsOneWidget);
      expect(find.text('NGユーザーIDは登録されていません'), findsOneWidget);
    });
  });
}

Widget _buildScreen(SettingsStore settingsStore) {
  return MaterialApp(home: NgUserListScreen(settingsStore: settingsStore));
}
