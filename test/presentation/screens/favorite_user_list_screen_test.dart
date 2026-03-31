import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/models/user_name_resolution.dart';
import 'package:comerune/presentation/screens/favorite_user_list_screen.dart';

import '../../helpers/in_memory_shared_preferences.dart';

void main() {
  group('FavoriteUserListScreen', () {
    testWidgets(
        'displays "name (ID)" format when resolveUserName returns a name',
        (WidgetTester tester) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings initial =
          AppSettings.defaults.addFavoriteUserId('12345');
      await store.save(initial);

      await tester.pumpWidget(_buildScreen(
        store,
        userNameResolution: UserNameResolution(
          resolve: (String userId) {
            if (userId == '12345') {
              return 'テストユーザー';
            }
            return null;
          },
          requestResolve: (_) {},
          listenable: ChangeNotifier(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('テストユーザー (12345)'), findsOneWidget);
    });

    testWidgets('displays userId only when resolveUserName returns null',
        (WidgetTester tester) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings initial =
          AppSettings.defaults.addFavoriteUserId('99999');
      await store.save(initial);

      await tester.pumpWidget(_buildScreen(
        store,
        userNameResolution: UserNameResolution(
          resolve: (String userId) => null,
          requestResolve: (_) {},
          listenable: ChangeNotifier(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('99999'), findsOneWidget);
    });

    testWidgets('UI updates when userNameListenable notifies',
        (WidgetTester tester) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings initial =
          AppSettings.defaults.addFavoriteUserId('12345');
      await store.save(initial);

      final ChangeNotifier listenable = ChangeNotifier();
      final Map<String, String> nameMap = <String, String>{};

      await tester.pumpWidget(_buildScreen(
        store,
        userNameResolution: UserNameResolution(
          resolve: (String userId) => nameMap[userId],
          requestResolve: (_) {},
          listenable: listenable,
        ),
      ));
      await tester.pumpAndSettle();

      // Initially no name resolved — only userId is shown.
      expect(find.text('12345'), findsOneWidget);
      expect(find.text('テストユーザー (12345)'), findsNothing);

      // Simulate name resolution arriving.
      nameMap['12345'] = 'テストユーザー';
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      listenable.notifyListeners();
      await tester.pump();

      expect(find.text('テストユーザー (12345)'), findsOneWidget);

      listenable.dispose();
    });

    testWidgets('null userNameResolution does not crash', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings initial =
          AppSettings.defaults.addFavoriteUserId('55555');
      await store.save(initial);

      // userNameResolution is omitted (null).
      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      // Should render without throwing; userId shown as fallback.
      expect(find.byType(FavoriteUserListScreen), findsOneWidget);
      expect(find.text('55555'), findsOneWidget);
    });

    testWidgets('requestResolve is called for each favorite userId on init', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings initial = AppSettings.defaults
          .addFavoriteUserId('aaa')
          .addFavoriteUserId('bbb');
      await store.save(initial);

      final List<String> requested = <String>[];

      await tester.pumpWidget(_buildScreen(
        store,
        userNameResolution: UserNameResolution(
          resolve: (_) => null,
          requestResolve: requested.add,
          listenable: ChangeNotifier(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(requested, containsAll(<String>['aaa', 'bbb']));
    });

    testWidgets('delete confirmation dialog shows nickname when available',
        (WidgetTester tester) async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings initial =
          AppSettings.defaults.addFavoriteUserId('12345');
      await store.save(initial);

      await tester.pumpWidget(_buildScreen(
        store,
        userNameResolution: UserNameResolution(
          resolve: (String userId) {
            if (userId == '12345') {
              return 'お気に入り太郎';
            }
            return null;
          },
          requestResolve: (_) {},
          listenable: ChangeNotifier(),
        ),
      ));
      await tester.pumpAndSettle();

      // Tap delete button for the first item.
      await tester.tap(find.byKey(const Key('favorite-user-remove-0')));
      await tester.pumpAndSettle();

      // Confirm dialog should show nickname.
      expect(find.text('ユーザー削除'), findsOneWidget);
      expect(
        find.text('お気に入り太郎 (12345) を削除しますか？'),
        findsOneWidget,
      );
    });
  });
}

Widget _buildScreen(
  SettingsStore settingsStore, {
  UserNameResolution? userNameResolution,
}) {
  return MaterialApp(
    home: FavoriteUserListScreen(
      settingsStore: settingsStore,
      userNameResolution: userNameResolution,
    ),
  );
}
