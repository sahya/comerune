import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/comment_speech/src/models/replace_rule.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/domain/models/ng_word_rule.dart';

void main() {
  group('AppSettings toJson/fromJson', () {
    test('roundtrip: export then import produces equivalent settings', () {
      const AppSettings original = AppSettings.defaults;
      final Map<String, dynamic> json = original.toJson();
      final AppSettings restored = AppSettings.fromJson(json);

      expect(restored.themeMode, original.themeMode);
      expect(restored.autoReadEnabled, original.autoReadEnabled);
      expect(restored.speechEngine, original.speechEngine);
      expect(restored.bouyomiHost, original.bouyomiHost);
      expect(restored.voicevoxSpeaker, original.voicevoxSpeaker);
      expect(restored.voicevoxSpeed, original.voicevoxSpeed);
      expect(restored.voicevoxPitch, original.voicevoxPitch);
      expect(restored.voicevoxIntonation, original.voicevoxIntonation);
      expect(restored.voicevoxVolume, original.voicevoxVolume);
      expect(restored.queueLimit, original.queueLimit);
      expect(restored.maxDelaySeconds, original.maxDelaySeconds);
      expect(restored.omitUrl, original.omitUrl);
      expect(restored.suppressDuplicate, original.suppressDuplicate);
      expect(restored.ngWords, original.ngWords);
      expect(restored.commentFontSize, original.commentFontSize);
      expect(restored.ngWordRules, original.ngWordRules);
      expect(restored.dictionaryRules, original.dictionaryRules);
      expect(restored.debugMode, original.debugMode);
    });

    test('roundtrip with non-default values', () {
      final AppSettings original = AppSettings.defaults.copyWith(
        themeMode: AppThemeMode.dark,
        autoReadEnabled: true,
        voicevoxSpeaker: 42,
        voicevoxSpeed: 1.5,
        ngWords: 'bad\nwords',
        commentFontSize: 24,
        pastCommentFetchCount: PastCommentFetchCount.all,
        debugMode: true,
        dictionaryRules: const <ReplaceRule>[
          ReplaceRule(pattern: 'test', replacement: 'replaced'),
        ],
      );

      final Map<String, dynamic> json = original.toJson();
      final AppSettings restored = AppSettings.fromJson(json);

      expect(restored.themeMode, AppThemeMode.dark);
      expect(restored.autoReadEnabled, isTrue);
      expect(restored.voicevoxSpeaker, 42);
      expect(restored.voicevoxSpeed, 1.5);
      expect(restored.ngWords, 'bad\nwords');
      expect(restored.commentFontSize, 24);
      expect(restored.pastCommentFetchCount, PastCommentFetchCount.all);
      expect(restored.debugMode, isTrue);
      expect(restored.dictionaryRules.length, 1);
      expect(restored.dictionaryRules.first.pattern, 'test');
    });

    test('roundtrip via JSON string', () {
      const AppSettings original = AppSettings.defaults;
      final String jsonString = const JsonEncoder.withIndent(
        '  ',
      ).convert(original.toJson());
      final AppSettings restored = AppSettings.fromJsonString(jsonString);

      expect(restored.themeMode, original.themeMode);
      expect(restored.voicevoxSpeaker, original.voicevoxSpeaker);
      expect(restored.debugMode, original.debugMode);
    });

    test('version field is included in export', () {
      final Map<String, dynamic> json = AppSettings.defaults.toJson();
      expect(json['_version'], AppSettings.settingsVersion);
      expect(json['_version'], 1);
    });

    test('import with missing fields uses defaults', () {
      final AppSettings result = AppSettings.fromJson(<String, dynamic>{
        '_version': 1,
      });

      expect(result.themeMode, AppSettings.defaults.themeMode);
      expect(result.autoReadEnabled, AppSettings.defaults.autoReadEnabled);
      expect(result.voicevoxSpeaker, AppSettings.defaults.voicevoxSpeaker);
      expect(result.commentFontSize, AppSettings.defaults.commentFontSize);
      expect(result.dictionaryRules, AppSettings.defaults.dictionaryRules);
      expect(result.debugMode, AppSettings.defaults.debugMode);
    });

    test('import with empty map uses all defaults', () {
      final AppSettings result = AppSettings.fromJson(<String, dynamic>{});
      expect(result.themeMode, AppSettings.defaults.themeMode);
      expect(result.voicevoxSpeed, AppSettings.defaults.voicevoxSpeed);
    });

    test('import clamps out-of-range commentFontSize', () {
      final AppSettings tooSmall = AppSettings.fromJson(<String, dynamic>{
        'commentFontSize': 1,
      });
      expect(tooSmall.commentFontSize, commentFontSizeMin);

      final AppSettings tooLarge = AppSettings.fromJson(<String, dynamic>{
        'commentFontSize': 200,
      });
      expect(tooLarge.commentFontSize, commentFontSizeMax);
    });

    test('import with invalid dictionaryRules falls back to defaults', () {
      final AppSettings result = AppSettings.fromJson(<String, dynamic>{
        'dictionaryRules': 'not a list',
      });
      expect(result.dictionaryRules, AppSettings.defaults.dictionaryRules);
    });

    test(
      'import with malformed dictionaryRules items falls back to defaults',
      () {
        final AppSettings result = AppSettings.fromJson(<String, dynamic>{
          'dictionaryRules': <dynamic>[42, 'bad'],
        });
        expect(result.dictionaryRules, AppSettings.defaults.dictionaryRules);
      },
    );

    test('fromJsonString throws FormatException on invalid JSON', () {
      expect(
        () => AppSettings.fromJsonString('not json'),
        throwsFormatException,
      );
    });

    test('fromJsonString throws FormatException on JSON array', () {
      expect(
        () => AppSettings.fromJsonString('[1, 2, 3]'),
        throwsFormatException,
      );
    });

    test('ngWordRules roundtrip preserves pattern and enabled', () {
      final AppSettings original = AppSettings.defaults.copyWith(
        ngWordRules: const <NgWordRule>[
          NgWordRule(pattern: 'spam'),
          NgWordRule(pattern: 'disabled', enabled: false),
        ],
      );
      final Map<String, dynamic> json = original.toJson();
      final AppSettings restored = AppSettings.fromJson(json);

      expect(restored.ngWordRules.length, 2);
      expect(restored.ngWordRules[0].pattern, 'spam');
      expect(restored.ngWordRules[0].enabled, isTrue);
      expect(restored.ngWordRules[1].pattern, 'disabled');
      expect(restored.ngWordRules[1].enabled, isFalse);
    });

    test('import with invalid ngWordRules falls back to defaults', () {
      final AppSettings result = AppSettings.fromJson(<String, dynamic>{
        'ngWordRules': 'not a list',
      });
      expect(result.ngWordRules, AppSettings.defaults.ngWordRules);
    });

    test('import with malformed ngWordRules items falls back to defaults', () {
      final AppSettings result = AppSettings.fromJson(<String, dynamic>{
        'ngWordRules': <dynamic>[42, 'bad'],
      });
      expect(result.ngWordRules, AppSettings.defaults.ngWordRules);
    });

    test('unknown keys in JSON are ignored', () {
      final AppSettings result = AppSettings.fromJson(<String, dynamic>{
        '_version': 1,
        'unknownField': 'should be ignored',
        'anotherUnknown': 42,
      });
      expect(result.themeMode, AppSettings.defaults.themeMode);
    });
  });
}
