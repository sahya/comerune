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
    test('returns default count500 for unknown value', () {
      expect(
        PastCommentFetchCountValue.fromStorageValue('unexpected'),
        PastCommentFetchCount.count500,
      );
    });

    test('returns default count500 for null (unset storage)', () {
      expect(
        PastCommentFetchCountValue.fromStorageValue(null),
        PastCommentFetchCount.count500,
      );
    });

    test('preserves explicit count100 setting for backward compatibility', () {
      // 明示的に 100 を選択していた既存ユーザーの設定は新デフォルト
      // (500) で上書きしてはいけない。
      expect(
        PastCommentFetchCountValue.fromStorageValue('100'),
        PastCommentFetchCount.count100,
      );
    });

    test('round-trips all enum values via storageValue', () {
      for (final PastCommentFetchCount value in PastCommentFetchCount.values) {
        expect(
          PastCommentFetchCountValue.fromStorageValue(value.storageValue),
          value,
        );
      }
    });
  });

  group('AppSettings.defaults.pastCommentFetchCount', () {
    test('defaults to count500 (initial fetch target)', () {
      expect(
        AppSettings.defaults.pastCommentFetchCount,
        PastCommentFetchCount.count500,
      );
    });
  });

  group('PastCommentFetchCountValue.label', () {
    test('uses spec label for all option', () {
      expect(PastCommentFetchCount.all.label, '全部（上限あり）');
    });
  });

  group('PastCommentFetchCountValue.displayCapacity', () {
    test(
      'adds timelineLiveCommentBufferSize to historyCount so freshly fetched '
      'history is not trimmed by incoming live comments',
      () {
        for (final PastCommentFetchCount value
            in PastCommentFetchCount.values) {
          expect(
            value.displayCapacity,
            value.historyCount + timelineLiveCommentBufferSize,
          );
          expect(value.displayCapacity, greaterThan(value.historyCount));
        }
      },
    );
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

  group('preset display category toggles', () {
    test('all four toggles default to false', () {
      expect(AppSettings.defaults.showViolentComment, isFalse);
      expect(AppSettings.defaults.showSexualComment, isFalse);
      expect(AppSettings.defaults.showDiscriminationComment, isFalse);
      expect(AppSettings.defaults.showMinorsRelatedComment, isFalse);
    });

    test('copyWith updates each toggle independently', () {
      final AppSettings violent = AppSettings.defaults.copyWith(
        showViolentComment: true,
      );
      expect(violent.showViolentComment, isTrue);
      expect(violent.showSexualComment, isFalse);
      expect(violent.showDiscriminationComment, isFalse);
      expect(violent.showMinorsRelatedComment, isFalse);

      final AppSettings sexual = AppSettings.defaults.copyWith(
        showSexualComment: true,
      );
      expect(sexual.showSexualComment, isTrue);
      expect(sexual.showViolentComment, isFalse);

      final AppSettings discrimination = AppSettings.defaults.copyWith(
        showDiscriminationComment: true,
      );
      expect(discrimination.showDiscriminationComment, isTrue);

      final AppSettings minors = AppSettings.defaults.copyWith(
        showMinorsRelatedComment: true,
      );
      expect(minors.showMinorsRelatedComment, isTrue);
    });

    test('copyWith preserves other toggles when one is updated', () {
      final AppSettings initial = AppSettings.defaults.copyWith(
        showViolentComment: true,
        showMinorsRelatedComment: true,
      );
      final AppSettings updated = initial.copyWith(showSexualComment: true);
      expect(updated.showViolentComment, isTrue);
      expect(updated.showSexualComment, isTrue);
      expect(updated.showDiscriminationComment, isFalse);
      expect(updated.showMinorsRelatedComment, isTrue);
    });

    test('toJson emits all four toggle keys', () {
      final Map<String, dynamic> json = AppSettings.defaults
          .copyWith(
            showViolentComment: true,
            showSexualComment: true,
            showDiscriminationComment: true,
            showMinorsRelatedComment: true,
          )
          .toJson();
      expect(json['showViolentComment'], isTrue);
      expect(json['showSexualComment'], isTrue);
      expect(json['showDiscriminationComment'], isTrue);
      expect(json['showMinorsRelatedComment'], isTrue);
    });

    test('fromJson round-trips all four toggles', () {
      final AppSettings original = AppSettings.defaults.copyWith(
        showViolentComment: true,
        showSexualComment: false,
        showDiscriminationComment: true,
        showMinorsRelatedComment: false,
      );
      final AppSettings restored = AppSettings.fromJson(original.toJson());
      expect(restored.showViolentComment, isTrue);
      expect(restored.showSexualComment, isFalse);
      expect(restored.showDiscriminationComment, isTrue);
      expect(restored.showMinorsRelatedComment, isFalse);
    });

    test(
      'fromJson with legacy payload (no toggle keys) falls back to false',
      () {
        // Simulates an Export file written before #614, which has none of
        // the four toggle keys. The new fields must default to false so
        // existing users do not suddenly start showing previously-blocked
        // categories after upgrading.
        final AppSettings restored = AppSettings.fromJson(<String, dynamic>{
          '_version': 1,
          'themeMode': 'dark',
        });
        expect(restored.showViolentComment, isFalse);
        expect(restored.showSexualComment, isFalse);
        expect(restored.showDiscriminationComment, isFalse);
        expect(restored.showMinorsRelatedComment, isFalse);
        // Sanity: the rest of the payload still applied.
        expect(restored.themeMode, AppThemeMode.dark);
      },
    );
  });

  group('ngProtectionNotificationEnabled', () {
    test('defaults to false', () {
      expect(AppSettings.defaults.ngProtectionNotificationEnabled, isFalse);
    });

    test('copyWith updates ngProtectionNotificationEnabled', () {
      final AppSettings updated = AppSettings.defaults.copyWith(
        ngProtectionNotificationEnabled: true,
      );
      expect(updated.ngProtectionNotificationEnabled, isTrue);
    });

    test(
      'copyWith preserves ngProtectionNotificationEnabled when not specified',
      () {
        final AppSettings initial = AppSettings.defaults.copyWith(
          ngProtectionNotificationEnabled: true,
        );
        final AppSettings updated = initial.copyWith(debugMode: true);
        expect(updated.ngProtectionNotificationEnabled, isTrue);
      },
    );
  });

  group('matchedNgWord', () {
    test('returns the first matched pattern from the list', () {
      final AppSettings settings = AppSettings.defaults.copyWith(
        ngWords: 'spam\n広告',
      );
      expect(settings.matchedNgWord('hello spam world'), 'spam');
      expect(settings.matchedNgWord('この広告'), '広告');
    });

    test('returns null when content does not match', () {
      final AppSettings settings = AppSettings.defaults.copyWith(
        ngWords: 'spam',
      );
      expect(settings.matchedNgWord('clean content'), isNull);
    });

    test('returns null when no NG words are configured', () {
      expect(AppSettings.defaults.matchedNgWord('anything'), isNull);
    });
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

    // デフォルト辞書ルールを順に適用するヘルパ。native normalizer の
    // applyDictionaryRules と同じ順序で処理する（enabled が false の
    // ルールはスキップ）。
    String applyDefaultDictionary(String input) {
      String out = input;
      for (final ReplaceRule rule in defaultNicoDictionaryRules) {
        if (!rule.enabled) continue;
        out = out.replaceAll(RegExp(rule.pattern), rule.replacement);
      }
      return out;
    }

    test('default rules distinguish ww (→わらわら) from single w (→わら)', () {
      // `ww` at the end of a comment becomes `わらわら` (not `わら`), and a
      // single `w` at the end still becomes `わら`. This is the user-visible
      // behavior that split the original `[wｗ]{1,2}$` rule into two rules.
      expect(applyDefaultDictionary('w'), 'わら');
      expect(applyDefaultDictionary('ww'), 'わらわら');
      expect(applyDefaultDictionary('www'), 'わらわら');
      expect(applyDefaultDictionary('おはようw'), 'おはようわら');
      expect(applyDefaultDictionary('おはようww'), 'おはようわらわら');
      expect(applyDefaultDictionary('おはようwww'), 'おはようわらわら');
      // 全角ｗ も同様に処理されること。
      expect(applyDefaultDictionary('おはようｗ'), 'おはようわら');
      expect(applyDefaultDictionary('おはようｗｗ'), 'おはようわらわら');
    });

    test('standalone w/ｗ not at end of string reads as わら', () {
      // 行末以外で単独の `w`/`ｗ` が出た場合も「わら」と読めるよう、
      // 先読み/後読みで英数字に隣接しないケースを広く捕捉する。
      expect(applyDefaultDictionary('w おはよう'), 'わら おはよう');
      expect(applyDefaultDictionary('ｗ おはよう'), 'わら おはよう');
      expect(applyDefaultDictionary('おはよう w また'), 'おはよう わら また');
      expect(applyDefaultDictionary('おはよう ｗ また'), 'おはよう わら また');
      expect(applyDefaultDictionary('うれしいw さらに'), 'うれしいわら さらに');
      // 句読点・約物で区切られる場合も単独の w とみなす。
      expect(applyDefaultDictionary('そうだねw、また'), 'そうだねわら、また');
    });

    test(
      'single w inside English words is not converted (false positive guard)',
      () {
        // 英単語の途中・先頭・末尾にある `w` は半角英数字で挟まれて
        // いるので変換対象にならない。
        expect(applyDefaultDictionary('we'), 'we');
        expect(applyDefaultDictionary('watch'), 'watch');
        expect(applyDefaultDictionary('wifi'), 'wifi');
        expect(applyDefaultDictionary('howl'), 'howl');
        // `www` URL プレフィックス相当は 3+ ルールで「わらわら」に
        // なるため、URL 検出は呼び出し側（ニコニコ向け正規化）で
        // 事前に行うこと。ここでは辞書のみの動作を確認する。
        expect(applyDefaultDictionary('www.example.com'), 'わらわら.example.com');
      },
    );
  });
}
