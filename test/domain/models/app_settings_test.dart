import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/comment_speech/src/models/replace_rule.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/domain/models/ng_word_rule.dart';

void main() {
  group('AppThemeModeValue.fromStorageValue', () {
    test('returns light for null', () {
      expect(AppThemeModeValue.fromStorageValue(null), AppThemeMode.light);
    });

    test('returns light for unknown value', () {
      expect(AppThemeModeValue.fromStorageValue('garbage'), AppThemeMode.light);
    });

    test('returns light for empty string', () {
      expect(AppThemeModeValue.fromStorageValue(''), AppThemeMode.light);
    });

    test('returns system for "system" string', () {
      expect(AppThemeModeValue.fromStorageValue('system'), AppThemeMode.system);
    });

    test('round-trips all enum values via storageValue', () {
      for (final AppThemeMode mode in AppThemeMode.values) {
        expect(AppThemeModeValue.fromStorageValue(mode.storageValue), mode);
      }
    });
  });

  group('PastCommentFetchCountValue.fromStorageValue', () {
    test('returns default count100 for unknown value', () {
      expect(
        PastCommentFetchCountValue.fromStorageValue('unexpected'),
        PastCommentFetchCount.count100,
      );
    });
  });

  group('PastCommentFetchCountValue.label', () {
    test('uses spec label for all option', () {
      expect(PastCommentFetchCount.all.label, '全部（上限あり）');
    });
  });

  group('ngUserIdSet', () {
    test('returns empty set for empty string', () {
      const AppSettings settings = AppSettings.defaults;
      expect(settings.ngUserIdSet, isEmpty);
    });

    test('parses newline-separated user IDs', () {
      final AppSettings settings = AppSettings.defaults.copyWith(
        ngUserIds: '123\n456\n789',
      );
      expect(settings.ngUserIdSet, <String>{'123', '456', '789'});
    });

    test('trims whitespace and ignores blank lines', () {
      final AppSettings settings = AppSettings.defaults.copyWith(
        ngUserIds: ' 123 \n\n 456 \n',
      );
      expect(settings.ngUserIdSet, <String>{'123', '456'});
    });
  });

  group('isNgUser', () {
    test('returns false for null userId', () {
      const AppSettings settings = AppSettings.defaults;
      expect(settings.isNgUser(null), isFalse);
    });

    test('returns true for registered NG user', () {
      final AppSettings settings = AppSettings.defaults.copyWith(
        ngUserIds: '123\n456',
      );
      expect(settings.isNgUser('123'), isTrue);
      expect(settings.isNgUser('456'), isTrue);
      expect(settings.isNgUser('789'), isFalse);
    });
  });

  group('addNgUserId', () {
    test('adds new user ID', () {
      final AppSettings updated = AppSettings.defaults.addNgUserId('123');
      expect(updated.ngUserIdSet, <String>{'123'});
    });

    test('does not duplicate existing ID', () {
      final AppSettings initial = AppSettings.defaults.copyWith(
        ngUserIds: '123',
      );
      final AppSettings updated = initial.addNgUserId('123');
      expect(identical(updated, initial), isTrue);
    });
  });

  group('comment prefix defaults', () {
    test('starPrefixHidingEnabled defaults to false', () {
      expect(AppSettings.defaults.starPrefixHidingEnabled, isFalse);
    });

    test('slashPrefixSkipEnabled defaults to true', () {
      expect(AppSettings.defaults.slashPrefixSkipEnabled, isTrue);
    });

    test('copyWith updates prefix settings', () {
      final AppSettings updated = AppSettings.defaults.copyWith(
        starPrefixHidingEnabled: true,
        slashPrefixSkipEnabled: false,
      );
      expect(updated.starPrefixHidingEnabled, isTrue);
      expect(updated.slashPrefixSkipEnabled, isFalse);
    });
  });

  group('removeNgUserId', () {
    test('removes existing user ID', () {
      final AppSettings initial = AppSettings.defaults.copyWith(
        ngUserIds: '123\n456',
      );
      final AppSettings updated = initial.removeNgUserId('123');
      expect(updated.ngUserIdSet, <String>{'456'});
    });

    test('returns same instance if ID not present', () {
      final AppSettings initial = AppSettings.defaults.copyWith(
        ngUserIds: '123',
      );
      final AppSettings updated = initial.removeNgUserId('999');
      expect(identical(updated, initial), isTrue);
    });
  });

  group('ngWordList', () {
    test('returns empty list for empty string', () {
      const AppSettings settings = AppSettings.defaults;
      expect(settings.ngWordList, isEmpty);
    });

    test('returns empty list for whitespace-only string', () {
      final AppSettings settings = AppSettings.defaults.copyWith(
        ngWords: '  \n  \n  ',
      );
      expect(settings.ngWordList, isEmpty);
    });

    test('parses newline-separated NG words and lower-cases them', () {
      final AppSettings settings = AppSettings.defaults.copyWith(
        ngWords: 'Spam\nBad\nTEST',
      );
      expect(settings.ngWordList, <String>['spam', 'bad', 'test']);
    });

    test('trims whitespace and ignores blank lines', () {
      final AppSettings settings = AppSettings.defaults.copyWith(
        ngWords: ' Spam \n\n Bad \n',
      );
      expect(settings.ngWordList, <String>['spam', 'bad']);
    });

    test('uses ngWordRules when populated, returning only enabled rules', () {
      final AppSettings settings = AppSettings.defaults.copyWith(
        ngWordRules: const <NgWordRule>[
          NgWordRule(pattern: 'Enabled'),
          NgWordRule(pattern: 'Disabled', enabled: false),
          NgWordRule(pattern: '  TRIMMED  '),
        ],
      );
      expect(settings.ngWordList, <String>['enabled', 'trimmed']);
    });

    test('falls back to ngWords when ngWordRules is empty', () {
      final AppSettings settings = AppSettings.defaults.copyWith(
        ngWords: 'legacy',
        ngWordRules: const <NgWordRule>[],
      );
      expect(settings.ngWordList, <String>['legacy']);
    });
  });

  group('containsNgWord', () {
    test('returns false when no NG words configured', () {
      const AppSettings settings = AppSettings.defaults;
      expect(settings.containsNgWord('hello world'), isFalse);
    });

    test('returns true when content contains an NG word', () {
      final AppSettings settings = AppSettings.defaults.copyWith(
        ngWords: 'spam\nbad',
      );
      expect(settings.containsNgWord('this is spam content'), isTrue);
    });

    test('matching is case-insensitive', () {
      final AppSettings settings = AppSettings.defaults.copyWith(
        ngWords: 'Spam',
      );
      expect(settings.containsNgWord('SPAM message'), isTrue);
      expect(settings.containsNgWord('spam message'), isTrue);
      expect(settings.containsNgWord('SpAm message'), isTrue);
    });

    test('returns false when content does not match any NG word', () {
      final AppSettings settings = AppSettings.defaults.copyWith(
        ngWords: 'spam\nbad',
      );
      expect(settings.containsNgWord('hello world'), isFalse);
    });

    test('matches partial words (substring match)', () {
      final AppSettings settings = AppSettings.defaults.copyWith(
        ngWords: 'spam',
      );
      expect(settings.containsNgWord('antispam filter'), isTrue);
    });
  });

  group('commentTwoLineEnabled', () {
    test('defaults to false', () {
      expect(AppSettings.defaults.commentTwoLineEnabled, isFalse);
    });

    test('copyWith updates commentTwoLineEnabled', () {
      final AppSettings updated = AppSettings.defaults.copyWith(
        commentTwoLineEnabled: true,
      );
      expect(updated.commentTwoLineEnabled, isTrue);
    });

    test('copyWith preserves commentTwoLineEnabled when not specified', () {
      final AppSettings initial = AppSettings.defaults.copyWith(
        commentTwoLineEnabled: true,
      );
      final AppSettings updated = initial.copyWith(showUserName: false);
      expect(updated.commentTwoLineEnabled, isTrue);
    });
  });

  group('commentZebraStripingEnabled', () {
    test('defaults to false', () {
      expect(AppSettings.defaults.commentZebraStripingEnabled, isFalse);
    });

    test('copyWith updates commentZebraStripingEnabled', () {
      final AppSettings updated = AppSettings.defaults.copyWith(
        commentZebraStripingEnabled: true,
      );
      expect(updated.commentZebraStripingEnabled, isTrue);
    });

    test(
      'copyWith preserves commentZebraStripingEnabled when not specified',
      () {
        final AppSettings initial = AppSettings.defaults.copyWith(
          commentZebraStripingEnabled: true,
        );
        final AppSettings updated = initial.copyWith(debugMode: true);
        expect(updated.commentZebraStripingEnabled, isTrue);
      },
    );
  });

  group('dictionaryRules', () {
    test('defaults include nico dictionary rules', () {
      expect(AppSettings.defaults.dictionaryRules, defaultNicoDictionaryRules);
      expect(AppSettings.defaults.dictionaryRules, isNotEmpty);
    });

    test('default rules contain w→わら pattern', () {
      final bool hasWara = AppSettings.defaults.dictionaryRules.any(
        (ReplaceRule r) => r.replacement == 'わら',
      );
      expect(hasWara, isTrue);
    });

    test('default rules contain 8→ぱちぱちぱち pattern', () {
      final bool hasPachi = AppSettings.defaults.dictionaryRules.any(
        (ReplaceRule r) => r.replacement == 'ぱちぱちぱち',
      );
      expect(hasPachi, isTrue);
    });

    test('copyWith replaces dictionaryRules', () {
      const List<ReplaceRule> custom = <ReplaceRule>[
        ReplaceRule(pattern: 'test', replacement: 'テスト'),
      ];
      final AppSettings updated = AppSettings.defaults.copyWith(
        dictionaryRules: custom,
      );
      expect(updated.dictionaryRules, custom);
    });

    test('all default rules are enabled', () {
      for (final ReplaceRule rule in defaultNicoDictionaryRules) {
        expect(
          rule.enabled,
          isTrue,
          reason: '${rule.pattern} should be enabled',
        );
      }
    });

    test('all default rule patterns are valid regular expressions', () {
      for (final ReplaceRule rule in defaultNicoDictionaryRules) {
        expect(
          () => RegExp(rule.pattern),
          returnsNormally,
          reason: '${rule.pattern} should be a valid regex',
        );
      }
    });

    test('identifies built-in rules as protected', () {
      expect(
        isDefaultNicoDictionaryRule(defaultNicoDictionaryRules.first),
        isTrue,
      );
      expect(
        isDefaultNicoDictionaryRule(
          const ReplaceRule(pattern: '初見', replacement: 'しょけん(変更済み)'),
        ),
        isTrue,
      );
      expect(
        isDefaultNicoDictionaryRule(
          const ReplaceRule(pattern: 'custom', replacement: 'カスタム'),
        ),
        isFalse,
      );
    });

    test('legacy built-in w→わら pattern remains protected', () {
      // Older versions shipped `[wｗ]{1,2}$` as a default rule. Even though it
      // is no longer part of the current defaults, users who upgraded from
      // those versions still have it stored in their settings and must
      // continue to see it as a built-in (protected) rule.
      expect(
        isDefaultNicoDictionaryRule(
          const ReplaceRule(pattern: r'[wｗ]{1,2}$', replacement: 'わら'),
        ),
        isTrue,
      );
    });

    test('default rules distinguish ww (→わらわら) from single w (→わら)', () {
      // Applies the default dictionary rules in order, the same way the
      // native normalizer does. Verifies that `ww` at the end of a comment
      // becomes `わらわら` (not `わら`), and a single `w` at the end still
      // becomes `わら`. This is the user-visible behavior that split the
      // original `[wｗ]{1,2}$` rule into two distinct rules.
      String apply(String input) {
        String out = input;
        for (final ReplaceRule rule in defaultNicoDictionaryRules) {
          if (!rule.enabled) continue;
          out = out.replaceAll(RegExp(rule.pattern), rule.replacement);
        }
        return out;
      }

      expect(apply('w'), 'わら');
      expect(apply('ww'), 'わらわら');
      expect(apply('www'), 'わらわら');
      expect(apply('おはようw'), 'おはようわら');
      expect(apply('おはようww'), 'おはようわらわら');
      expect(apply('おはようwww'), 'おはようわらわら');
      // 全角ｗ も同様に処理されること。
      expect(apply('おはようｗ'), 'おはようわら');
      expect(apply('おはようｗｗ'), 'おはようわらわら');
    });
  });
}
