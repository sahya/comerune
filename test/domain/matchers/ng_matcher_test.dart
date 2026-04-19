import 'package:comerune/domain/matchers/ng_matcher.dart';
import 'package:comerune/domain/models/ng_display_subcategory.dart';
import 'package:comerune/domain/models/ng_policy.dart';
import 'package:comerune/domain/models/ng_preset_category.dart';
import 'package:flutter_test/flutter_test.dart';

/// Simple case-folding normalizer used by these tests. The real matcher on
/// `CommentScreen` injects a much richer normalizer (NFKC + katakana
/// folding + look-alike table + symbol stripping) but that normalizer is
/// screen-local today. Using a small pure-Dart normalizer here keeps the
/// unit tests deterministic and free of any screen dependency.
String _normalizer(String s) => s.toLowerCase().replaceAll(' ', '');

NgPresetCategory _category({
  required String id,
  required NgPolicy policy,
  required NgDisplaySubcategory? sub,
  required List<String> words,
}) => NgPresetCategory(
  id: id,
  description: '',
  policy: policy,
  displaySubcategory: sub,
  words: List<String>.unmodifiable(words),
);

void main() {
  group('NgMatcher.match', () {
    test('returns null when there are no configured entries', () {
      final NgMatcher matcher = NgMatcher(
        presetCategories: const <NgPresetCategory>[],
        userNgWords: const <String>[],
        normalizer: _normalizer,
      );
      expect(matcher.isEmpty, isTrue);
      expect(matcher.match('anything'), isNull);
    });

    test('returns null when no entry is contained in the text', () {
      final NgMatcher matcher = NgMatcher.fromFlatWords(
        words: const <String>['spam'],
        normalizer: _normalizer,
      );
      expect(matcher.match('hello world'), isNull);
    });

    test('returns the first matching preset entry', () {
      final NgMatcher matcher = NgMatcher(
        presetCategories: <NgPresetCategory>[
          _category(
            id: 'violence',
            policy: NgPolicy.blockSpeechOnly,
            sub: NgDisplaySubcategory.violence,
            words: const <String>['kill'],
          ),
          _category(
            id: 'sexual',
            policy: NgPolicy.blockSpeechOnly,
            sub: NgDisplaySubcategory.sexual,
            words: const <String>['xxx'],
          ),
        ],
        userNgWords: const <String>[],
        normalizer: _normalizer,
      );

      final NgMatchResult? result = matcher.match('Please do not kill me');
      expect(result, isNotNull);
      expect(result!.matchedSubcategory, NgDisplaySubcategory.violence);
      expect(result.matchedPolicy, NgPolicy.blockSpeechOnly);
      expect(result.matchedPattern, 'kill');
    });

    test(
      'user-configured words are matched as blockAll with null subcategory',
      () {
        final NgMatcher matcher = NgMatcher(
          presetCategories: const <NgPresetCategory>[],
          userNgWords: const <String>['forbidden'],
          normalizer: _normalizer,
        );
        final NgMatchResult? result = matcher.match('contains FORBIDDEN text');
        expect(result, isNotNull);
        expect(result!.matchedPolicy, NgPolicy.blockAll);
        expect(result.matchedSubcategory, isNull);
      },
    );

    test('duplicate normalized forms are collapsed (first-seen wins)', () {
      final NgMatcher matcher = NgMatcher(
        presetCategories: <NgPresetCategory>[
          _category(
            id: 'a',
            policy: NgPolicy.blockSpeechOnly,
            sub: NgDisplaySubcategory.violence,
            words: const <String>['kill'],
          ),
        ],
        userNgWords: const <String>['KILL'],
        normalizer: _normalizer,
      );
      // Both entries normalize to "kill"; the preset entry wins because it
      // was inserted first. That means the result carries the preset's
      // policy (blockSpeechOnly) and subcategory (violence), not the user
      // list's blockAll/null.
      final NgMatchResult? result = matcher.match('kill');
      expect(result, isNotNull);
      expect(result!.matchedPolicy, NgPolicy.blockSpeechOnly);
      expect(result.matchedSubcategory, NgDisplaySubcategory.violence);
    });

    test('blank / whitespace-only words are ignored', () {
      final NgMatcher matcher = NgMatcher(
        presetCategories: const <NgPresetCategory>[],
        userNgWords: const <String>['', '   '],
        normalizer: _normalizer,
      );
      expect(matcher.isEmpty, isTrue);
      expect(matcher.match('anything'), isNull);
    });

    test('empty input text returns null (no match)', () {
      final NgMatcher matcher = NgMatcher.fromFlatWords(
        words: const <String>['ng'],
        normalizer: _normalizer,
      );
      expect(matcher.match(''), isNull);
    });

    test(
      'whitespace-only input text that normalizes to empty returns null',
      () {
        final NgMatcher matcher = NgMatcher.fromFlatWords(
          words: const <String>['x'],
          normalizer: (String s) => s.replaceAll(RegExp(r'\s+'), ''),
        );
        // After normalization the input becomes empty — matcher must not
        // return spurious hits (e.g. by matching a zero-length substring).
        expect(matcher.match('   '), isNull);
      },
    );

    test('handles large entry list without correctness degradation', () {
      // Regression guard: ensure no off-by-one / map overwrite issues appear
      // when many entries are loaded (simulates future preset expansion).
      // Uses zero-padded fixed-width ids so no entry is a substring of any
      // other (matching is contains-based).
      final List<String> words = List<String>.generate(
        1000,
        (int i) => 'ngword${i.toString().padLeft(4, "0")}',
      );
      final NgMatcher matcher = NgMatcher.fromFlatWords(
        words: words,
        normalizer: _normalizer,
      );
      expect(matcher.isEmpty, isFalse);
      // First, middle, last entries must all be findable.
      expect(matcher.match('ngword0000')?.matchedPattern, 'ngword0000');
      expect(matcher.match('ngword0500')?.matchedPattern, 'ngword0500');
      expect(matcher.match('ngword0999')?.matchedPattern, 'ngword0999');
      expect(matcher.match('ngword1000'), isNull);
    });
  });

  group('NgMatcher.shouldBlockDisplay', () {
    NgMatcher buildViolenceBlockSpeechOnly() {
      return NgMatcher(
        presetCategories: <NgPresetCategory>[
          _category(
            id: 'violence',
            policy: NgPolicy.blockSpeechOnly,
            sub: NgDisplaySubcategory.violence,
            words: const <String>['kill'],
          ),
        ],
        userNgWords: const <String>[],
        normalizer: _normalizer,
      );
    }

    test('returns false when there is no match', () {
      final NgMatcher matcher = buildViolenceBlockSpeechOnly();
      expect(matcher.shouldBlockDisplay('hello'), isFalse);
    });

    test('blockSpeechOnly + pref allows the matched subcategory -> false '
        '(displayed)', () {
      final NgMatcher matcher = buildViolenceBlockSpeechOnly();
      expect(
        matcher.shouldBlockDisplay(
          'do not kill',
          const NgDisplayPreferences(allowViolence: true),
        ),
        isFalse,
      );
    });

    test(
      'blockSpeechOnly + pref does not allow the matched subcategory -> true',
      () {
        final NgMatcher matcher = buildViolenceBlockSpeechOnly();
        expect(
          matcher.shouldBlockDisplay(
            'do not kill',
            const NgDisplayPreferences(allowViolence: false),
          ),
          isTrue,
        );
        // Other categories enabled must not "leak" into violence.
        expect(
          matcher.shouldBlockDisplay(
            'do not kill',
            const NgDisplayPreferences(
              allowSexual: true,
              allowDiscrimination: true,
              allowMinors: true,
            ),
          ),
          isTrue,
        );
      },
    );

    test('blockAll preset always blocks display regardless of prefs', () {
      final NgMatcher matcher = NgMatcher(
        presetCategories: <NgPresetCategory>[
          _category(
            id: 'any',
            policy: NgPolicy.blockAll,
            sub: NgDisplaySubcategory.violence,
            words: const <String>['kill'],
          ),
        ],
        userNgWords: const <String>[],
        normalizer: _normalizer,
      );
      expect(
        matcher.shouldBlockDisplay(
          'kill',
          const NgDisplayPreferences(
            allowViolence: true,
            allowSexual: true,
            allowDiscrimination: true,
            allowMinors: true,
          ),
        ),
        isTrue,
      );
    });

    test('blockSpeechOnly preset with null subcategory is hidden even when all '
        'prefs are true (conservative default)', () {
      final NgMatcher matcher = NgMatcher(
        presetCategories: <NgPresetCategory>[
          _category(
            id: 'unclassified',
            policy: NgPolicy.blockSpeechOnly,
            sub: null,
            words: const <String>['kill'],
          ),
        ],
        userNgWords: const <String>[],
        normalizer: _normalizer,
      );
      expect(
        matcher.shouldBlockDisplay(
          'kill',
          const NgDisplayPreferences(
            allowViolence: true,
            allowSexual: true,
            allowDiscrimination: true,
            allowMinors: true,
          ),
        ),
        isTrue,
      );
    });

    test('user words always block display (treated as blockAll)', () {
      final NgMatcher matcher = NgMatcher(
        presetCategories: const <NgPresetCategory>[],
        userNgWords: const <String>['spam'],
        normalizer: _normalizer,
      );
      expect(
        matcher.shouldBlockDisplay(
          'spam message',
          const NgDisplayPreferences(
            allowViolence: true,
            allowSexual: true,
            allowDiscrimination: true,
            allowMinors: true,
          ),
        ),
        isTrue,
      );
    });

    test('default preferences (all false) reproduce pre-#613 behavior', () {
      // Build a matcher that mixes every subcategory + a blockAll entry +
      // a user word, then verify that every hit is blocked with the
      // default preferences. This is the regression guarantee for the
      // display axis.
      final NgMatcher matcher = NgMatcher(
        presetCategories: <NgPresetCategory>[
          _category(
            id: 'violence',
            policy: NgPolicy.blockSpeechOnly,
            sub: NgDisplaySubcategory.violence,
            words: const <String>['kill'],
          ),
          _category(
            id: 'sexual',
            policy: NgPolicy.blockSpeechOnly,
            sub: NgDisplaySubcategory.sexual,
            words: const <String>['xxx'],
          ),
          _category(
            id: 'discrimination',
            policy: NgPolicy.blockSpeechOnly,
            sub: NgDisplaySubcategory.discrimination,
            words: const <String>['slur'],
          ),
          _category(
            id: 'minors',
            policy: NgPolicy.blockSpeechOnly,
            sub: NgDisplaySubcategory.minors,
            words: const <String>['child'],
          ),
          _category(
            id: 'hard_block',
            policy: NgPolicy.blockAll,
            sub: NgDisplaySubcategory.violence,
            words: const <String>['bomb'],
          ),
        ],
        userNgWords: const <String>['spam'],
        normalizer: _normalizer,
      );
      for (final String body in <String>[
        'kill',
        'xxx',
        'slur',
        'child',
        'bomb',
        'spam',
      ]) {
        expect(
          matcher.shouldBlockDisplay(body),
          isTrue,
          reason: 'default prefs must still hide: "$body"',
        );
      }
    });
  });

  group('NgMatcher.shouldBlockSpeech', () {
    test('match -> true regardless of preferences (v1 safety)', () {
      final NgMatcher matcher = NgMatcher(
        presetCategories: <NgPresetCategory>[
          _category(
            id: 'violence',
            policy: NgPolicy.blockSpeechOnly,
            sub: NgDisplaySubcategory.violence,
            words: const <String>['kill'],
          ),
        ],
        userNgWords: const <String>[],
        normalizer: _normalizer,
      );
      expect(matcher.shouldBlockSpeech('kill'), isTrue);
    });

    test('no match -> false', () {
      final NgMatcher matcher = NgMatcher.fromFlatWords(
        words: const <String>['kill'],
        normalizer: _normalizer,
      );
      expect(matcher.shouldBlockSpeech('hello world'), isFalse);
    });

    test('speech decision is independent from NgDisplayPreferences '
        '(shouldBlockSpeech has no prefs argument in v1)', () {
      // This test documents the intentional API shape: even when every
      // display toggle is "allow", speech is still blocked. The future
      // engine-aware overload (see NgMatcher.shouldBlockSpeech docs) is
      // explicitly out of scope for #613.
      final NgMatcher matcher = NgMatcher(
        presetCategories: <NgPresetCategory>[
          _category(
            id: 'violence',
            policy: NgPolicy.blockSpeechOnly,
            sub: NgDisplaySubcategory.violence,
            words: const <String>['kill'],
          ),
        ],
        userNgWords: const <String>[],
        normalizer: _normalizer,
      );
      // Build a preferences object that allows everything on the display
      // side and confirm speech is still blocked.
      const NgDisplayPreferences allAllowed = NgDisplayPreferences(
        allowViolence: true,
        allowSexual: true,
        allowDiscrimination: true,
        allowMinors: true,
      );
      expect(matcher.shouldBlockDisplay('kill', allAllowed), isFalse);
      expect(matcher.shouldBlockSpeech('kill'), isTrue);
    });
  });

  group('NgDisplayPreferences.allows', () {
    test('null subcategory is never allowed', () {
      const NgDisplayPreferences prefs = NgDisplayPreferences(
        allowViolence: true,
        allowSexual: true,
        allowDiscrimination: true,
        allowMinors: true,
      );
      expect(prefs.allows(null), isFalse);
    });

    test('each axis is independently respected', () {
      const NgDisplayPreferences prefs = NgDisplayPreferences(
        allowViolence: true,
      );
      expect(prefs.allows(NgDisplaySubcategory.violence), isTrue);
      expect(prefs.allows(NgDisplaySubcategory.sexual), isFalse);
      expect(prefs.allows(NgDisplaySubcategory.discrimination), isFalse);
      expect(prefs.allows(NgDisplaySubcategory.minors), isFalse);
    });
  });
}
