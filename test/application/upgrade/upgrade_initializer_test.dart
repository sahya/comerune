import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/upgrade/upgrade_initializer.dart';

import '../../helpers/in_memory_shared_preferences.dart';

void main() {
  group('UpgradeInitializer', () {
    test('runs initialization on fresh install and stores version', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final UpgradeInitializer initializer = UpgradeInitializer(prefs: prefs);

      final bool ran = await initializer.run();

      expect(ran, isTrue);
      expect(
        prefs.getInt('app.initializationVersion'),
        UpgradeInitializer.currentVersion,
      );
    });

    test('does not run when already at current version', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      await prefs.setInt(
        'app.initializationVersion',
        UpgradeInitializer.currentVersion,
      );

      final UpgradeInitializer initializer = UpgradeInitializer(prefs: prefs);
      final bool ran = await initializer.run();

      expect(ran, isFalse);
    });

    test('clears ephemeral keys on upgrade', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      // Simulate old version with ephemeral data present.
      await prefs.setInt('app.initializationVersion', 0);
      await prefs.setDouble('settings.voicevox.preMuteVolume', 0.8);

      final UpgradeInitializer initializer = UpgradeInitializer(prefs: prefs);
      await initializer.run();

      expect(prefs.getDouble('settings.voicevox.preMuteVolume'), isNull);
    });

    test('preserves persistent settings keys on upgrade', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      await prefs.setInt('app.initializationVersion', 0);

      // Persistent keys that must survive upgrade.
      await prefs.setString('settings.themeMode', 'dark');
      await prefs.setBool('settings.autoReadEnabled', true);
      await prefs.setString('settings.speechEngine', 'voicevox');
      await prefs.setInt('settings.voicevox.speaker', 3);
      await prefs.setDouble('settings.voicevox.speedScale', 1.2);
      await prefs.setString('settings.filter.ngUserIds', 'user1\nuser2');
      await prefs.setString('settings.favoriteUserIds', 'fav1\nfav2');
      await prefs.setString(
        'settings.filter.ngWordRules',
        '[{"pattern":"test","enabled":true}]',
      );
      await prefs.setString(
        'settings.speech.dictionaryRules',
        '[{"pattern":"w+","replacement":"わら"}]',
      );
      await prefs.setBool('settings.comment.showUserName', true);
      await prefs.setString('settings.comment.fontSize', '16');
      await prefs.setBool('settings.voicevox.termsAccepted', true);

      final UpgradeInitializer initializer = UpgradeInitializer(prefs: prefs);
      await initializer.run();

      // All persistent keys must remain intact.
      expect(prefs.getString('settings.themeMode'), 'dark');
      expect(prefs.getBool('settings.autoReadEnabled'), isTrue);
      expect(prefs.getString('settings.speechEngine'), 'voicevox');
      expect(prefs.getInt('settings.voicevox.speaker'), 3);
      expect(prefs.getDouble('settings.voicevox.speedScale'), 1.2);
      expect(prefs.getString('settings.filter.ngUserIds'), 'user1\nuser2');
      expect(prefs.getString('settings.favoriteUserIds'), 'fav1\nfav2');
      expect(
        prefs.getString('settings.filter.ngWordRules'),
        '[{"pattern":"test","enabled":true}]',
      );
      expect(
        prefs.getString('settings.speech.dictionaryRules'),
        '[{"pattern":"w+","replacement":"わら"}]',
      );
      expect(prefs.getBool('settings.comment.showUserName'), isTrue);
      expect(prefs.getString('settings.comment.fontSize'), '16');
      expect(prefs.getBool('settings.voicevox.termsAccepted'), isTrue);
    });

    test('preserves user attribute keys on upgrade', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      await prefs.setInt('app.initializationVersion', 0);
      await prefs.setString(
        'usercolor.broadcaster1',
        '{"user1":{"c":4293467961,"n":"たろう"}}',
      );

      final UpgradeInitializer initializer = UpgradeInitializer(prefs: prefs);
      await initializer.run();

      expect(
        prefs.getString('usercolor.broadcaster1'),
        '{"user1":{"c":4293467961,"n":"たろう"}}',
      );
    });

    test('preserves onboarding completed flag on upgrade', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      await prefs.setInt('app.initializationVersion', 0);
      await prefs.setBool('onboarding.completed', true);

      final UpgradeInitializer initializer = UpgradeInitializer(prefs: prefs);
      await initializer.run();

      expect(prefs.getBool('onboarding.completed'), isTrue);
    });

    test('preserves migration version on upgrade', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      await prefs.setInt('app.initializationVersion', 0);
      await prefs.setInt('app.migrationVersion', 2);

      final UpgradeInitializer initializer = UpgradeInitializer(prefs: prefs);
      await initializer.run();

      expect(prefs.getInt('app.migrationVersion'), 2);
    });

    test('handles upgrade when no ephemeral keys exist in storage', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      // Version is behind but no ephemeral keys were ever stored.
      await prefs.setInt('app.initializationVersion', 0);
      await prefs.setString('settings.themeMode', 'dark');

      final UpgradeInitializer initializer = UpgradeInitializer(prefs: prefs);
      final bool ran = await initializer.run();

      expect(ran, isTrue);
      expect(
        prefs.getInt('app.initializationVersion'),
        UpgradeInitializer.currentVersion,
      );
      // Persistent key is untouched.
      expect(prefs.getString('settings.themeMode'), 'dark');
    });

    test('is idempotent when called multiple times', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final UpgradeInitializer initializer = UpgradeInitializer(prefs: prefs);

      await initializer.run();
      final bool secondRun = await initializer.run();

      expect(secondRun, isFalse);
      expect(
        prefs.getInt('app.initializationVersion'),
        UpgradeInitializer.currentVersion,
      );
    });

    test('does not run on version downgrade', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      // Stored version is higher than current (simulates downgrade).
      await prefs.setInt(
        'app.initializationVersion',
        UpgradeInitializer.currentVersion + 1,
      );
      await prefs.setDouble('settings.voicevox.preMuteVolume', 0.5);

      final UpgradeInitializer initializer = UpgradeInitializer(prefs: prefs);
      final bool ran = await initializer.run();

      expect(ran, isFalse);
      // Ephemeral key is NOT cleared on downgrade.
      expect(prefs.getDouble('settings.voicevox.preMuteVolume'), 0.5);
    });
  });

  group('StorageKeyCategory', () {
    test('categoryOf returns ephemeral for preMuteVolume', () {
      expect(
        UpgradeInitializer.categoryOf('settings.voicevox.preMuteVolume'),
        StorageKeyCategory.ephemeral,
      );
    });

    test('categoryOf returns persistent for user setting keys', () {
      const List<String> persistentKeys = <String>[
        'settings.themeMode',
        'settings.autoReadEnabled',
        'settings.speechEngine',
        'settings.voicevox.speaker',
        'settings.voicevox.speedScale',
        'settings.voicevox.termsAccepted',
        'settings.filter.ngWordRules',
        'settings.filter.ngUserIds',
        'settings.favoriteUserIds',
        'settings.speech.dictionaryRules',
        'settings.comment.showUserName',
        'settings.comment.fontSize',
        'settings.statistics.enabled',
        'settings.debugMode',
      ];

      for (final String key in persistentKeys) {
        expect(
          UpgradeInitializer.categoryOf(key),
          StorageKeyCategory.persistent,
          reason: '$key should be persistent',
        );
      }
    });

    test('categoryOf returns persistent for unknown keys', () {
      expect(
        UpgradeInitializer.categoryOf('some.unknown.key'),
        StorageKeyCategory.persistent,
      );
    });
  });
}
