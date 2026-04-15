import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/comment_speech/src/models/replace_rule.dart';
import 'package:comerune/domain/models/app_settings.dart';

import '../../helpers/in_memory_shared_preferences.dart';

void main() {
  group('SharedPreferencesSettingsStore', () {
    test('showUserName defaults to true when not stored', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings loaded = await store.load();

      expect(loaded.showUserName, isTrue);
    });

    test('round-trips showUserName value', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings original = AppSettings.defaults.copyWith(
        showUserName: false,
      );
      await store.save(original);

      final AppSettings loaded = await store.load();

      expect(loaded.showUserName, isFalse);
    });

    test('commentFontSize defaults to 14 when not stored', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings loaded = await store.load();

      expect(loaded.commentFontSize, commentFontSizeDefault);
    });

    test('round-trips commentFontSize value', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      for (final double size in <double>[10, 14, 24, 36, 48]) {
        final AppSettings original = AppSettings.defaults.copyWith(
          commentFontSize: size,
        );
        await store.save(original);

        final AppSettings loaded = await store.load();

        expect(loaded.commentFontSize, size, reason: '$size should round-trip');
      }
    });

    test('migrates legacy enum commentFontSize values', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: prefs);

      // Simulate a legacy stored value.
      await prefs.setString('settings.comment.fontSize', 'xl');

      final AppSettings loaded = await store.load();

      expect(loaded.commentFontSize, 18);
    });

    test('clamps out-of-range commentFontSize to valid bounds', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: prefs);

      // Below minimum → clamp to min.
      await prefs.setString('settings.comment.fontSize', '0');
      AppSettings loaded = await store.load();
      expect(loaded.commentFontSize, commentFontSizeMin);

      // Above maximum → clamp to max.
      await prefs.setString('settings.comment.fontSize', '100');
      loaded = await store.load();
      expect(loaded.commentFontSize, commentFontSizeMax);
    });

    test('falls back to default for invalid commentFontSize strings', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: prefs);

      for (final String invalid in <String>['abc', '', 'unknown']) {
        await prefs.setString('settings.comment.fontSize', invalid);
        final AppSettings loaded = await store.load();
        expect(
          loaded.commentFontSize,
          commentFontSizeDefault,
          reason: '"$invalid" should fall back to default',
        );
      }
    });

    test('parses fractional commentFontSize correctly', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: prefs);

      await prefs.setString('settings.comment.fontSize', '14.5');
      final AppSettings loaded = await store.load();
      expect(loaded.commentFontSize, 14.5);
    });

    test(
      'ngProtectionNotificationEnabled defaults to false when not stored',
      () async {
        final SharedPreferencesSettingsStore store =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        final AppSettings loaded = await store.load();

        expect(loaded.ngProtectionNotificationEnabled, isFalse);
      },
    );

    test('round-trips ngProtectionNotificationEnabled value', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings original = AppSettings.defaults.copyWith(
        ngProtectionNotificationEnabled: true,
      );
      await store.save(original);

      final AppSettings loaded = await store.load();

      expect(loaded.ngProtectionNotificationEnabled, isTrue);
    });

    test('autoSaveCommentLog defaults to false when not stored', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings loaded = await store.load();

      expect(loaded.autoSaveCommentLog, isFalse);
    });

    test('round-trips autoSaveCommentLog value', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings original = AppSettings.defaults.copyWith(
        autoSaveCommentLog: true,
      );
      await store.save(original);

      final AppSettings loaded = await store.load();

      expect(loaded.autoSaveCommentLog, isTrue);
    });

    test(
      'autoSaveCommentLogPath defaults to empty string when not stored',
      () async {
        final SharedPreferencesSettingsStore store =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        final AppSettings loaded = await store.load();

        expect(loaded.autoSaveCommentLogPath, isEmpty);
      },
    );

    test('round-trips autoSaveCommentLogPath value', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings original = AppSettings.defaults.copyWith(
        autoSaveCommentLogPath: '/custom/path/to/logs',
      );
      await store.save(original);

      final AppSettings loaded = await store.load();

      expect(loaded.autoSaveCommentLogPath, '/custom/path/to/logs');
    });

    test(
      'showOperatorComment / showSystemMessage / showEmotion default to true '
      'when not stored',
      () async {
        final SharedPreferencesSettingsStore store =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        final AppSettings loaded = await store.load();

        expect(loaded.showOperatorComment, isTrue);
        expect(loaded.showSystemMessage, isTrue);
        expect(loaded.showEmotion, isTrue);
      },
    );

    test(
      'round-trips showOperatorComment / showSystemMessage / showEmotion',
      () async {
        final SharedPreferencesSettingsStore store =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        final AppSettings original = AppSettings.defaults.copyWith(
          showOperatorComment: false,
          showSystemMessage: false,
          showEmotion: false,
        );
        await store.save(original);

        final AppSettings loaded = await store.load();

        expect(loaded.showOperatorComment, isFalse);
        expect(loaded.showSystemMessage, isFalse);
        expect(loaded.showEmotion, isFalse);
      },
    );

    test('autoNicknameRegistration defaults to true when not stored', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings loaded = await store.load();

      expect(loaded.autoNicknameRegistration, isTrue);
    });

    test('round-trips autoNicknameRegistration value', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings original = AppSettings.defaults.copyWith(
        autoNicknameRegistration: false,
      );
      await store.save(original);

      final AppSettings loaded = await store.load();

      expect(loaded.autoNicknameRegistration, isFalse);
    });

    test('starPrefixHidingEnabled defaults to false when not stored', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings loaded = await store.load();

      expect(loaded.starPrefixHidingEnabled, isFalse);
    });

    test('round-trips starPrefixHidingEnabled value', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings original = AppSettings.defaults.copyWith(
        starPrefixHidingEnabled: true,
      );
      await store.save(original);

      final AppSettings loaded = await store.load();

      expect(loaded.starPrefixHidingEnabled, isTrue);
    });

    test('slashPrefixSkipEnabled defaults to true when not stored', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings loaded = await store.load();

      expect(loaded.slashPrefixSkipEnabled, isTrue);
    });

    test('round-trips slashPrefixSkipEnabled value', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings original = AppSettings.defaults.copyWith(
        slashPrefixSkipEnabled: false,
      );
      await store.save(original);

      final AppSettings loaded = await store.load();

      expect(loaded.slashPrefixSkipEnabled, isFalse);
    });

    test('themeMode defaults to light when not stored', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings loaded = await store.load();

      expect(loaded.themeMode, AppThemeMode.light);
    });

    test('round-trips themeMode value', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      for (final AppThemeMode mode in AppThemeMode.values) {
        final AppSettings original = AppSettings.defaults.copyWith(
          themeMode: mode,
        );
        await store.save(original);

        final AppSettings loaded = await store.load();

        expect(loaded.themeMode, mode);
      }
    });
    test('statisticsEnabled defaults to false when not stored', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings loaded = await store.load();

      expect(loaded.statisticsEnabled, isFalse);
    });

    test(
      'statisticsViewerCommentEnabled defaults to true when not stored',
      () async {
        final SharedPreferencesSettingsStore store =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        final AppSettings loaded = await store.load();

        expect(loaded.statisticsViewerCommentEnabled, isTrue);
      },
    );

    test(
      'statisticsActiveUserEnabled defaults to true when not stored',
      () async {
        final SharedPreferencesSettingsStore store =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        final AppSettings loaded = await store.load();

        expect(loaded.statisticsActiveUserEnabled, isTrue);
      },
    );

    test('round-trips statistics settings', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings original = AppSettings.defaults.copyWith(
        statisticsEnabled: true,
        statisticsViewerCommentEnabled: false,
        statisticsActiveUserEnabled: false,
      );
      await store.save(original);

      final AppSettings loaded = await store.load();

      expect(loaded.statisticsEnabled, isTrue);
      expect(loaded.statisticsViewerCommentEnabled, isFalse);
      expect(loaded.statisticsActiveUserEnabled, isFalse);
    });

    test(
      'dictionaryRules defaults to defaultNicoDictionaryRules when not stored',
      () async {
        final SharedPreferencesSettingsStore store =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        final AppSettings loaded = await store.load();

        expect(loaded.dictionaryRules, defaultNicoDictionaryRules);
      },
    );

    test('round-trips dictionaryRules', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      const List<ReplaceRule> rules = <ReplaceRule>[
        ReplaceRule(pattern: r'w+', replacement: 'わら'),
        ReplaceRule(pattern: '初見', replacement: 'しょけん', enabled: false),
      ];
      final AppSettings original = AppSettings.defaults.copyWith(
        dictionaryRules: rules,
      );
      await store.save(original);

      final AppSettings loaded = await store.load();

      expect(loaded.dictionaryRules.length, 2);
      expect(loaded.dictionaryRules[0].pattern, r'w+');
      expect(loaded.dictionaryRules[0].replacement, 'わら');
      expect(loaded.dictionaryRules[0].enabled, isTrue);
      expect(loaded.dictionaryRules[1].pattern, '初見');
      expect(loaded.dictionaryRules[1].replacement, 'しょけん');
      expect(loaded.dictionaryRules[1].enabled, isFalse);
    });

    test('round-trips empty dictionaryRules list', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings original = AppSettings.defaults.copyWith(
        dictionaryRules: const <ReplaceRule>[],
      );
      await store.save(original);

      final AppSettings loaded = await store.load();

      expect(loaded.dictionaryRules, isEmpty);
    });

    test('falls back to defaults for invalid dictionaryRules JSON', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: prefs);

      await prefs.setString('settings.speech.dictionaryRules', 'not-json');

      final AppSettings loaded = await store.load();

      expect(loaded.dictionaryRules, defaultNicoDictionaryRules);
    });

    test('readUserName defaults to false when not stored', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings loaded = await store.load();

      expect(loaded.readUserName, isFalse);
    });

    test('round-trips readUserName value', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings original = AppSettings.defaults.copyWith(
        readUserName: true,
      );
      await store.save(original);

      final AppSettings loaded = await store.load();

      expect(loaded.readUserName, isTrue);
    });

    test('voicevoxTermsAccepted defaults to false when not stored', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings loaded = await store.load();

      expect(loaded.voicevoxTermsAccepted, isFalse);
    });

    test('round-trips voicevoxTermsAccepted value', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings original = AppSettings.defaults.copyWith(
        voicevoxTermsAccepted: true,
      );
      await store.save(original);

      final AppSettings loaded = await store.load();

      expect(loaded.voicevoxTermsAccepted, isTrue);
    });

    test(
      'falls back to defaults for malformed dictionaryRules array',
      () async {
        final InMemorySharedPreferences prefs = InMemorySharedPreferences();
        final SharedPreferencesSettingsStore store =
            SharedPreferencesSettingsStore(prefs: prefs);

        await prefs.setString(
          'settings.speech.dictionaryRules',
          '[{"pattern": 123}]',
        );

        final AppSettings loaded = await store.load();

        expect(loaded.dictionaryRules, defaultNicoDictionaryRules);
      },
    );
  });
}
