import 'package:comerune/application/onboarding/onboarding_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_shared_preferences.dart';

void main() {
  group('SharedPreferencesOnboardingStore', () {
    late InMemorySharedPreferences prefs;
    late SharedPreferencesOnboardingStore store;

    setUp(() {
      prefs = InMemorySharedPreferences();
      store = SharedPreferencesOnboardingStore(prefs: prefs);
    });

    test('isCompleted returns false when never marked', () {
      expect(store.isCompleted(), isFalse);
    });

    test('isCompleted returns true after markCompleted', () async {
      await store.markCompleted();
      expect(store.isCompleted(), isTrue);
    });

    test('persists value across new store instances', () async {
      await store.markCompleted();

      final SharedPreferencesOnboardingStore store2 =
          SharedPreferencesOnboardingStore(prefs: prefs);
      expect(store2.isCompleted(), isTrue);
    });
  });
}
