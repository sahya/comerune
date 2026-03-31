import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/onboarding/onboarding_store.dart';
import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/main.dart';

import 'helpers/in_memory_shared_preferences.dart';
import 'helpers/in_memory_user_session_store.dart';

void main() {
  testWidgets('ComeruneApp boots to select screen',
      (WidgetTester tester) async {
    final InMemorySharedPreferences prefs = InMemorySharedPreferences();
    final SettingsStore settingsStore = SharedPreferencesSettingsStore(
      prefs: prefs,
    );

    // Mark onboarding as completed so SelectScreen is shown.
    final OnboardingStore onboardingStore =
        SharedPreferencesOnboardingStore(prefs: prefs);
    await onboardingStore.markCompleted();

    await tester.pumpWidget(
      ComeruneApp(
        settingsStore: settingsStore,
        initialSettings: AppSettings.defaults,
        userSessionStore: InMemoryUserSessionStore(),
        onboardingStore: onboardingStore,
      ),
    );
    await tester.pumpAndSettle();

    // Flush follow-program fetch retry timers (exponential backoff:
    // 1s + 2s) so no pending timer remains after the test.
    await tester.pump(const Duration(seconds: 4));

    expect(find.byKey(const Key('select_screen_input')), findsOneWidget);
    expect(
      find.byKey(const Key('select_screen_connect_button')),
      findsOneWidget,
    );
    expect(find.text('接続開始'), findsOneWidget);
  });

  testWidgets('ComeruneApp shows onboarding when not completed',
      (WidgetTester tester) async {
    final InMemorySharedPreferences prefs = InMemorySharedPreferences();
    final SettingsStore settingsStore = SharedPreferencesSettingsStore(
      prefs: prefs,
    );
    final OnboardingStore onboardingStore =
        SharedPreferencesOnboardingStore(prefs: prefs);

    await tester.pumpWidget(
      ComeruneApp(
        settingsStore: settingsStore,
        initialSettings: AppSettings.defaults,
        userSessionStore: InMemoryUserSessionStore(),
        onboardingStore: onboardingStore,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('comerune へようこそ'), findsOneWidget);
    expect(find.byKey(const Key('select_screen_input')), findsNothing);
  });
}
