import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/main.dart';

import 'helpers/in_memory_shared_preferences.dart';
import 'helpers/in_memory_user_session_store.dart';

void main() {
  testWidgets('ComeruneApp boots to select screen', (
    WidgetTester tester,
  ) async {
    final SettingsStore settingsStore = SharedPreferencesSettingsStore(
      prefs: InMemorySharedPreferences(),
    );

    await tester.pumpWidget(
      ComeruneApp(
        settingsStore: settingsStore,
        initialSettings: AppSettings.defaults,
        userSessionStore: InMemoryUserSessionStore(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('select_screen_input')), findsOneWidget);
    expect(
      find.byKey(const Key('select_screen_connect_button')),
      findsOneWidget,
    );
    expect(find.text('接続開始'), findsOneWidget);
  });
}
