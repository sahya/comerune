import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/presentation/screens/broadcaster_ng_list_screen.dart';
import 'package:comerune/presentation/screens/user_management_settings_screen.dart';

import '../../helpers/fake_broadcaster_ng_store.dart';
import '../../helpers/in_memory_shared_preferences.dart';

void main() {
  group('UserManagementSettingsScreen', () {
    testWidgets('shows favorite user list tile', (WidgetTester tester) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('favorite-user-list-tile')), findsOneWidget);
    });

    testWidgets(
      'broadcaster NG tile shows 未対応 and is disabled when no store is wired',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        await tester.pumpWidget(_buildScreen(settingsStore));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('broadcaster-ng-list-tile')),
          findsOneWidget,
        );
        expect(find.text('放送者別 NG 一覧'), findsOneWidget);
        expect(find.text('未対応'), findsOneWidget);

        final ListTile tile = tester.widget(
          find.byKey(const Key('broadcaster-ng-list-tile')),
        );
        expect(tile.enabled, isFalse);
        expect(tile.onTap, isNull);
      },
    );

    testWidgets(
      'broadcaster NG tile pushes BroadcasterNgListScreen when store wired',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        final FakeBroadcasterNgStore ngStore = FakeBroadcasterNgStore();

        await tester.pumpWidget(
          MaterialApp(
            home: UserManagementSettingsScreen(
              settingsStore: settingsStore,
              broadcasterNgStore: ngStore,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 0 件 form when no broadcaster slots exist yet.
        expect(find.text('未登録 / 放送者ごとに NG ユーザー / NG ワードを管理'), findsOneWidget);

        await tester.tap(find.byKey(const Key('broadcaster-ng-list-tile')));
        await tester.pumpAndSettle();

        expect(find.byType(BroadcasterNgListScreen), findsOneWidget);
      },
    );

    testWidgets(
      'broadcaster NG tile subtitle reflects broadcaster slot count',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        final FakeBroadcasterNgStore ngStore = FakeBroadcasterNgStore()
          ..seedBroadcaster('caster-a')
          ..seedBroadcaster('caster-b');

        await tester.pumpWidget(
          MaterialApp(
            home: UserManagementSettingsScreen(
              settingsStore: settingsStore,
              broadcasterNgStore: ngStore,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('2 件の放送者で設定済み / 放送者ごとに NG ユーザー / NG ワードを管理'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'dispose does not throw when broadcasterIdNotifier is provided',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        final ValueNotifier<String?> notifier = ValueNotifier<String?>(
          'broadcaster-1',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: UserManagementSettingsScreen(
              settingsStore: settingsStore,
              broadcasterIdNotifier: notifier,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.pumpWidget(const MaterialApp(home: Scaffold()));
        await tester.pumpAndSettle();

        notifier.value = 'broadcaster-2';
        await tester.pump();

        notifier.dispose();
      },
    );

    testWidgets('dispose does not throw when broadcasterIdNotifier is null', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(
        MaterialApp(
          home: UserManagementSettingsScreen(settingsStore: settingsStore),
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.pumpAndSettle();
    });
  });
}

Widget _buildScreen(SettingsStore settingsStore) {
  return MaterialApp(
    home: UserManagementSettingsScreen(settingsStore: settingsStore),
  );
}
