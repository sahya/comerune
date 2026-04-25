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

    test(
      'showGiftComment / showNicoadComment default to true when not stored',
      () async {
        final SharedPreferencesSettingsStore store =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        final AppSettings loaded = await store.load();

        expect(loaded.showGiftComment, isTrue);
        expect(loaded.showNicoadComment, isTrue);
      },
    );

    test('round-trips showGiftComment / showNicoadComment', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings original = AppSettings.defaults.copyWith(
        showGiftComment: false,
        showNicoadComment: false,
      );
      await store.save(original);

      final AppSettings loaded = await store.load();

      expect(loaded.showGiftComment, isFalse);
      expect(loaded.showNicoadComment, isFalse);
    });

    test(
      'readGiftComment / readNicoadComment default to false when not stored',
      () async {
        final SharedPreferencesSettingsStore store =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        final AppSettings loaded = await store.load();

        expect(loaded.readGiftComment, isFalse);
        expect(loaded.readNicoadComment, isFalse);
      },
    );

    test('round-trips readGiftComment / readNicoadComment', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings original = AppSettings.defaults.copyWith(
        readGiftComment: true,
        readNicoadComment: true,
      );
      await store.save(original);

      final AppSettings loaded = await store.load();

      expect(loaded.readGiftComment, isTrue);
      expect(loaded.readNicoadComment, isTrue);
    });

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

    // --- Android TTS engine tests ---

    test('androidTts fields default correctly when not stored', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings loaded = await store.load();

      expect(loaded.speechEngine, SpeechEngine.voicevox);
      expect(loaded.androidTtsSpeed, 1.0);
      expect(loaded.androidTtsPitch, 1.0);
      expect(loaded.androidTtsVolume, 1.0);
    });

    test('round-trips speechEngine=androidTts', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings original = AppSettings.defaults.copyWith(
        speechEngine: SpeechEngine.androidTts,
      );
      await store.save(original);

      final AppSettings loaded = await store.load();

      expect(loaded.speechEngine, SpeechEngine.androidTts);
    });

    test('round-trips androidTtsSpeed value', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings original = AppSettings.defaults.copyWith(
        androidTtsSpeed: 1.5,
      );
      await store.save(original);

      final AppSettings loaded = await store.load();

      expect(loaded.androidTtsSpeed, 1.5);
    });

    test('round-trips androidTtsPitch value', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings original = AppSettings.defaults.copyWith(
        androidTtsPitch: 0.8,
      );
      await store.save(original);

      final AppSettings loaded = await store.load();

      expect(loaded.androidTtsPitch, 0.8);
    });

    test('round-trips androidTtsVolume value', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings original = AppSettings.defaults.copyWith(
        androidTtsVolume: 0.3,
      );
      await store.save(original);

      final AppSettings loaded = await store.load();

      expect(loaded.androidTtsVolume, 0.3);
    });

    test('round-trips all androidTts parameters together', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings original = AppSettings.defaults.copyWith(
        speechEngine: SpeechEngine.androidTts,
        androidTtsSpeed: 1.8,
        androidTtsPitch: 0.6,
        androidTtsVolume: 0.5,
      );
      await store.save(original);

      final AppSettings loaded = await store.load();

      expect(loaded.speechEngine, SpeechEngine.androidTts);
      expect(loaded.androidTtsSpeed, 1.8);
      expect(loaded.androidTtsPitch, 0.6);
      expect(loaded.androidTtsVolume, 0.5);
    });

    test(
      'speechEngine load falls back to voicevox for unknown stored value',
      () async {
        final InMemorySharedPreferences prefs = InMemorySharedPreferences();
        final SharedPreferencesSettingsStore store =
            SharedPreferencesSettingsStore(prefs: prefs);

        await prefs.setString('settings.speechEngine', 'unknownEngine');

        final AppSettings loaded = await store.load();

        expect(loaded.speechEngine, SpeechEngine.voicevox);
      },
    );

    test('speechEngine round-trips all three engine values', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      for (final SpeechEngine engine in SpeechEngine.values) {
        final AppSettings original = AppSettings.defaults.copyWith(
          speechEngine: engine,
        );
        await store.save(original);

        final AppSettings loaded = await store.load();

        expect(
          loaded.speechEngine,
          engine,
          reason: '${engine.name} should round-trip',
        );
      }
    });

    test('androidTts boundary: speed at min (0.5) and max (2.0)', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings atMin = AppSettings.defaults.copyWith(
        androidTtsSpeed: 0.5,
      );
      await store.save(atMin);
      AppSettings loaded = await store.load();
      expect(loaded.androidTtsSpeed, 0.5);

      final AppSettings atMax = AppSettings.defaults.copyWith(
        androidTtsSpeed: 2.0,
      );
      await store.save(atMax);
      loaded = await store.load();
      expect(loaded.androidTtsSpeed, 2.0);
    });

    test('androidTts boundary: pitch at min (0.5) and max (2.0)', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings atMin = AppSettings.defaults.copyWith(
        androidTtsPitch: 0.5,
      );
      await store.save(atMin);
      AppSettings loaded = await store.load();
      expect(loaded.androidTtsPitch, 0.5);

      final AppSettings atMax = AppSettings.defaults.copyWith(
        androidTtsPitch: 2.0,
      );
      await store.save(atMax);
      loaded = await store.load();
      expect(loaded.androidTtsPitch, 2.0);
    });

    test('androidTts boundary: volume at min (0.0) and max (1.0)', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings atMin = AppSettings.defaults.copyWith(
        androidTtsVolume: 0.0,
      );
      await store.save(atMin);
      AppSettings loaded = await store.load();
      expect(loaded.androidTtsVolume, 0.0);

      final AppSettings atMax = AppSettings.defaults.copyWith(
        androidTtsVolume: 1.0,
      );
      await store.save(atMax);
      loaded = await store.load();
      expect(loaded.androidTtsVolume, 1.0);
    });

    test(
      'speechEngine load falls back to voicevox for removed bouyomi value',
      () async {
        final InMemorySharedPreferences prefs = InMemorySharedPreferences();
        final SharedPreferencesSettingsStore store =
            SharedPreferencesSettingsStore(prefs: prefs);

        await prefs.setString('settings.speechEngine', 'bouyomi');

        final AppSettings loaded = await store.load();

        expect(loaded.speechEngine, SpeechEngine.voicevox);
      },
    );

    test(
      'preset display category toggles default to false when not stored',
      () async {
        final SharedPreferencesSettingsStore store =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        final AppSettings loaded = await store.load();

        expect(loaded.showViolentComment, isFalse);
        expect(loaded.showSexualComment, isFalse);
        expect(loaded.showDiscriminationComment, isFalse);
        expect(loaded.showMinorsRelatedComment, isFalse);
      },
    );

    test('round-trips all four preset display category toggles', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings original = AppSettings.defaults.copyWith(
        showViolentComment: true,
        showSexualComment: true,
        showDiscriminationComment: true,
        showMinorsRelatedComment: true,
      );
      await store.save(original);

      final AppSettings loaded = await store.load();

      expect(loaded.showViolentComment, isTrue);
      expect(loaded.showSexualComment, isTrue);
      expect(loaded.showDiscriminationComment, isTrue);
      expect(loaded.showMinorsRelatedComment, isTrue);
    });

    test('preset display toggles are persisted independently', () async {
      // Toggling only one of the four flags must not flip the others.
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await store.save(AppSettings.defaults.copyWith(showSexualComment: true));

      final AppSettings loaded = await store.load();
      expect(loaded.showSexualComment, isTrue);
      expect(loaded.showViolentComment, isFalse);
      expect(loaded.showDiscriminationComment, isFalse);
      expect(loaded.showMinorsRelatedComment, isFalse);
    });

    // -------------------------------------------------------------------
    // Issue #697: pre-mute volume is now stored per engine. The Android TTS
    // pre-mute slot is independent from the existing VOICEVOX pre-mute slot
    // so that switching engines while muted does not lose either engine's
    // saved volume.
    // -------------------------------------------------------------------
    test(
      'loadPreMuteAndroidTtsVolume returns null when not stored (Issue #697)',
      () {
        final SharedPreferencesSettingsStore store =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        expect(store.loadPreMuteAndroidTtsVolume(), isNull);
      },
    );

    test(
      'savePreMuteAndroidTtsVolume round-trips a value (Issue #697)',
      () async {
        final SharedPreferencesSettingsStore store =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        await store.savePreMuteAndroidTtsVolume(0.7);

        expect(store.loadPreMuteAndroidTtsVolume(), 0.7);
      },
    );

    test(
      'savePreMuteAndroidTtsVolume(null) clears the stored value (Issue #697)',
      () async {
        final SharedPreferencesSettingsStore store =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        await store.savePreMuteAndroidTtsVolume(0.5);
        await store.savePreMuteAndroidTtsVolume(null);

        expect(store.loadPreMuteAndroidTtsVolume(), isNull);
      },
    );

    test(
      'pre-mute slots are stored independently per engine (Issue #697)',
      () async {
        // Regression guard: writing to the Android TTS slot must not affect
        // the VOICEVOX slot, and vice versa. Without separate keys the
        // AppBar-driven mute would silently overwrite either engine's
        // pre-mute when the user switched engines while muted.
        final SharedPreferencesSettingsStore store =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        await store.savePreMuteVolume(1.5);
        await store.savePreMuteAndroidTtsVolume(0.8);

        expect(store.loadPreMuteVolume(), 1.5);
        expect(store.loadPreMuteAndroidTtsVolume(), 0.8);

        // Clearing one slot must leave the other untouched.
        await store.savePreMuteVolume(null);
        expect(store.loadPreMuteVolume(), isNull);
        expect(store.loadPreMuteAndroidTtsVolume(), 0.8);
      },
    );
  });
}
