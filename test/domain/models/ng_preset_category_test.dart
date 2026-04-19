import 'dart:convert';
import 'dart:io';

import 'package:comerune/domain/models/ng_display_subcategory.dart';
import 'package:comerune/domain/models/ng_policy.dart';
import 'package:comerune/domain/models/ng_preset_category.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NgPresetCategory.parseDocument', () {
    test('returns empty list for an empty map', () {
      expect(NgPresetCategory.parseDocument(<String, dynamic>{}), isEmpty);
    });

    test('returns empty list for null input', () {
      expect(NgPresetCategory.parseDocument(null), isEmpty);
    });

    test('returns empty list when input is not a map', () {
      expect(NgPresetCategory.parseDocument(<String>['a', 'b']), isEmpty);
      expect(NgPresetCategory.parseDocument(42), isEmpty);
      expect(NgPresetCategory.parseDocument('{"categories":{}}'), isEmpty);
    });

    test('parses a well-formed v3 document', () {
      final Map<String, dynamic> doc = <String, dynamic>{
        'version': 3,
        'categories': <String, dynamic>{
          'criminal_incitement': <String, dynamic>{
            'description': 'crime',
            'policy': 'blockSpeechOnly',
            'displaySubcategory': 'violence',
            'words': <String>['殺す', '爆弾'],
          },
          'child_safety': <String, dynamic>{
            'description': 'child',
            'policy': 'blockSpeechOnly',
            'displaySubcategory': 'minors',
            'words': <String>['児童ポルノ'],
          },
        },
      };
      final List<NgPresetCategory> parsed = NgPresetCategory.parseDocument(doc);
      expect(parsed.length, 2);
      final NgPresetCategory crime = parsed.firstWhere(
        (NgPresetCategory c) => c.id == 'criminal_incitement',
      );
      expect(crime.policy, NgPolicy.blockSpeechOnly);
      expect(crime.displaySubcategory, NgDisplaySubcategory.violence);
      expect(crime.words, <String>['殺す', '爆弾']);
      expect(crime.description, 'crime');

      final NgPresetCategory child = parsed.firstWhere(
        (NgPresetCategory c) => c.id == 'child_safety',
      );
      expect(child.displaySubcategory, NgDisplaySubcategory.minors);
    });

    test(
      'falls back to v2 behaviour when policy/displaySubcategory missing',
      () {
        final Map<String, dynamic> doc = <String, dynamic>{
          'version': 2,
          'categories': <String, dynamic>{
            'legacy': <String, dynamic>{
              'words': <String>['foo'],
            },
          },
        };
        final NgPresetCategory parsed = NgPresetCategory.parseDocument(
          doc,
        ).single;
        expect(parsed.policy, NgPolicy.defaultPolicy);
        expect(parsed.policy, NgPolicy.blockSpeechOnly);
        expect(parsed.displaySubcategory, isNull);
        expect(parsed.words, <String>['foo']);
      },
    );

    test('parses a v2 document with no version field (legacy)', () {
      final Map<String, dynamic> doc = <String, dynamic>{
        'categories': <String, dynamic>{
          'legacy': <String, dynamic>{
            'words': <String>['foo', 'bar'],
          },
        },
      };
      final NgPresetCategory parsed = NgPresetCategory.parseDocument(
        doc,
      ).single;
      expect(parsed.policy, NgPolicy.defaultPolicy);
      expect(parsed.displaySubcategory, isNull);
      expect(parsed.words, <String>['foo', 'bar']);
    });

    test('returns empty list when "categories" field is missing', () {
      final Map<String, dynamic> doc = <String, dynamic>{'version': 3};
      expect(NgPresetCategory.parseDocument(doc), isEmpty);
    });

    test('returns empty list when "categories" is not a map', () {
      final Map<String, dynamic> doc = <String, dynamic>{
        'version': 3,
        'categories': <String>['not a map'],
      };
      expect(NgPresetCategory.parseDocument(doc), isEmpty);
    });

    test('unknown policy value falls back to defaultPolicy', () {
      final Map<String, dynamic> doc = <String, dynamic>{
        'version': 3,
        'categories': <String, dynamic>{
          'x': <String, dynamic>{
            'policy': 'blockNone',
            'displaySubcategory': 'violence',
            'words': <String>['a'],
          },
        },
      };
      final NgPresetCategory parsed = NgPresetCategory.parseDocument(
        doc,
      ).single;
      expect(parsed.policy, NgPolicy.defaultPolicy);
      expect(parsed.displaySubcategory, NgDisplaySubcategory.violence);
    });

    test('unknown displaySubcategory becomes null (category still loaded)', () {
      final Map<String, dynamic> doc = <String, dynamic>{
        'version': 3,
        'categories': <String, dynamic>{
          'x': <String, dynamic>{
            'policy': 'blockSpeechOnly',
            'displaySubcategory': 'violent', // typo
            'words': <String>['a'],
          },
        },
      };
      final NgPresetCategory parsed = NgPresetCategory.parseDocument(
        doc,
      ).single;
      expect(parsed.displaySubcategory, isNull);
      expect(parsed.words, <String>['a']);
    });

    test('explicit null displaySubcategory becomes null', () {
      final Map<String, dynamic> doc = <String, dynamic>{
        'version': 3,
        'categories': <String, dynamic>{
          'x': <String, dynamic>{
            'policy': 'blockSpeechOnly',
            'displaySubcategory': null,
            'words': <String>['a'],
          },
        },
      };
      final NgPresetCategory parsed = NgPresetCategory.parseDocument(
        doc,
      ).single;
      expect(parsed.displaySubcategory, isNull);
    });

    test('skips category when "words" is not a list', () {
      final Map<String, dynamic> doc = <String, dynamic>{
        'version': 3,
        'categories': <String, dynamic>{
          'bad': <String, dynamic>{
            'policy': 'blockSpeechOnly',
            'displaySubcategory': 'violence',
            'words': 'not-a-list',
          },
          'good': <String, dynamic>{
            'policy': 'blockSpeechOnly',
            'displaySubcategory': 'violence',
            'words': <String>['ok'],
          },
        },
      };
      final List<NgPresetCategory> parsed = NgPresetCategory.parseDocument(doc);
      expect(parsed.length, 1);
      expect(parsed.single.id, 'good');
    });

    test('non-string policy falls back to defaultPolicy (no exception)', () {
      final Map<String, dynamic> doc = <String, dynamic>{
        'version': 3,
        'categories': <String, dynamic>{
          'x': <String, dynamic>{
            'policy': 42, // wrong type
            'displaySubcategory': 'violence',
            'words': <String>['a'],
          },
        },
      };
      final NgPresetCategory parsed = NgPresetCategory.parseDocument(
        doc,
      ).single;
      expect(parsed.policy, NgPolicy.defaultPolicy);
      expect(parsed.displaySubcategory, NgDisplaySubcategory.violence);
    });

    test('non-string displaySubcategory falls back to null (no exception)', () {
      final Map<String, dynamic> doc = <String, dynamic>{
        'version': 3,
        'categories': <String, dynamic>{
          'x': <String, dynamic>{
            'policy': 'blockSpeechOnly',
            'displaySubcategory': 42, // wrong type
            'words': <String>['a'],
          },
        },
      };
      final NgPresetCategory parsed = NgPresetCategory.parseDocument(
        doc,
      ).single;
      expect(parsed.displaySubcategory, isNull);
    });

    test(
      'non-string description falls back to empty string (no exception)',
      () {
        final Map<String, dynamic> doc = <String, dynamic>{
          'version': 3,
          'categories': <String, dynamic>{
            'x': <String, dynamic>{
              'description': 42, // wrong type
              'policy': 'blockSpeechOnly',
              'displaySubcategory': 'violence',
              'words': <String>['a'],
            },
          },
        };
        final NgPresetCategory parsed = NgPresetCategory.parseDocument(
          doc,
        ).single;
        expect(parsed.description, '');
      },
    );

    test('skips non-string and empty/whitespace word entries', () {
      final Map<String, dynamic> doc = <String, dynamic>{
        'version': 3,
        'categories': <String, dynamic>{
          'x': <String, dynamic>{
            'policy': 'blockSpeechOnly',
            'displaySubcategory': 'violence',
            'words': <dynamic>['ok', '', '   ', null, 42, 'ok2'],
          },
        },
      };
      final NgPresetCategory parsed = NgPresetCategory.parseDocument(
        doc,
      ).single;
      expect(parsed.words, <String>['ok', 'ok2']);
    });

    test('trims whitespace around words', () {
      final Map<String, dynamic> doc = <String, dynamic>{
        'version': 3,
        'categories': <String, dynamic>{
          'x': <String, dynamic>{
            'policy': 'blockSpeechOnly',
            'displaySubcategory': 'violence',
            'words': <String>['  hello  ', '\tworld\n'],
          },
        },
      };
      final NgPresetCategory parsed = NgPresetCategory.parseDocument(
        doc,
      ).single;
      expect(parsed.words, <String>['hello', 'world']);
    });

    test('deduplicates words within a single category (order preserved)', () {
      final Map<String, dynamic> doc = <String, dynamic>{
        'version': 3,
        'categories': <String, dynamic>{
          'x': <String, dynamic>{
            'policy': 'blockSpeechOnly',
            'displaySubcategory': 'violence',
            'words': <String>['a', 'b', 'a', 'c', 'b', 'a'],
          },
        },
      };
      final NgPresetCategory parsed = NgPresetCategory.parseDocument(
        doc,
      ).single;
      expect(parsed.words, <String>['a', 'b', 'c']);
    });

    test('handles empty word list (category kept)', () {
      final Map<String, dynamic> doc = <String, dynamic>{
        'version': 3,
        'categories': <String, dynamic>{
          'x': <String, dynamic>{
            'policy': 'blockSpeechOnly',
            'displaySubcategory': 'violence',
            'words': <String>[],
          },
        },
      };
      final NgPresetCategory parsed = NgPresetCategory.parseDocument(
        doc,
      ).single;
      expect(parsed.words, isEmpty);
    });

    test('accepts large word lists without loss', () {
      final List<String> huge = List<String>.generate(5000, (int i) => 'w$i');
      final Map<String, dynamic> doc = <String, dynamic>{
        'version': 3,
        'categories': <String, dynamic>{
          'x': <String, dynamic>{
            'policy': 'blockSpeechOnly',
            'displaySubcategory': 'violence',
            'words': huge,
          },
        },
      };
      final NgPresetCategory parsed = NgPresetCategory.parseDocument(
        doc,
      ).single;
      expect(parsed.words.length, 5000);
      expect(parsed.words.first, 'w0');
      expect(parsed.words.last, 'w4999');
    });

    test(
      'preserves hiragana / katakana / kanji / mixed-width words verbatim',
      () {
        final Map<String, dynamic> doc = <String, dynamic>{
          'version': 3,
          'categories': <String, dynamic>{
            'x': <String, dynamic>{
              'policy': 'blockSpeechOnly',
              'displaySubcategory': 'sexual',
              'words': <String>[
                'ひらがな',
                'カタカナ',
                '漢字',
                'ＡＢＣ', // full-width ASCII
                'ｶﾅ', // half-width katakana
                'mixed英字とかな',
              ],
            },
          },
        };
        final NgPresetCategory parsed = NgPresetCategory.parseDocument(
          doc,
        ).single;
        expect(parsed.words, <String>[
          'ひらがな',
          'カタカナ',
          '漢字',
          'ＡＢＣ',
          'ｶﾅ',
          'mixed英字とかな',
        ]);
      },
    );

    test('skips category entries whose keys are not strings', () {
      // Emulate a JSON-like Map with a non-string key (unusual but possible if
      // callers forge the input).
      final Map<Object, dynamic> doc = <Object, dynamic>{
        'categories': <Object, dynamic>{
          42: <String, dynamic>{
            'words': <String>['x'],
          },
          '': <String, dynamic>{
            'words': <String>['y'],
          },
          'good': <String, dynamic>{
            'words': <String>['z'],
          },
        },
      };
      final List<NgPresetCategory> parsed = NgPresetCategory.parseDocument(doc);
      expect(parsed.length, 1);
      expect(parsed.single.id, 'good');
    });
  });

  group('NgPresetCategory.flattenWords', () {
    test('flattens categories and deduplicates across them', () {
      final List<NgPresetCategory> categories = <NgPresetCategory>[
        const NgPresetCategory(
          id: 'a',
          description: '',
          policy: NgPolicy.blockSpeechOnly,
          displaySubcategory: null,
          words: <String>['x', 'y'],
        ),
        const NgPresetCategory(
          id: 'b',
          description: '',
          policy: NgPolicy.blockSpeechOnly,
          displaySubcategory: null,
          words: <String>['y', 'z'],
        ),
      ];
      expect(NgPresetCategory.flattenWords(categories), <String>[
        'x',
        'y',
        'z',
      ]);
    });

    test('returns empty list when every category is empty', () {
      expect(
        NgPresetCategory.flattenWords(const <NgPresetCategory>[]),
        isEmpty,
      );
    });
  });

  group('Equality and toString', () {
    test('equal categories compare equal', () {
      const NgPresetCategory a = NgPresetCategory(
        id: 'a',
        description: 'd',
        policy: NgPolicy.blockSpeechOnly,
        displaySubcategory: NgDisplaySubcategory.violence,
        words: <String>['w'],
      );
      const NgPresetCategory b = NgPresetCategory(
        id: 'a',
        description: 'd',
        policy: NgPolicy.blockSpeechOnly,
        displaySubcategory: NgDisplaySubcategory.violence,
        words: <String>['w'],
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('toString includes id and word count', () {
      const NgPresetCategory a = NgPresetCategory(
        id: 'abc',
        description: '',
        policy: NgPolicy.blockAll,
        displaySubcategory: NgDisplaySubcategory.minors,
        words: <String>['a', 'b'],
      );
      final String s = a.toString();
      expect(s, contains('abc'));
      expect(s, contains('blockAll'));
      expect(s, contains('minors'));
      expect(s, contains('2'));
    });
  });

  group('Shipped preset_ng_words.json (v3)', () {
    test('the bundled asset parses cleanly and every category is valid', () {
      // Read the asset from disk directly so we are independent of Flutter's
      // rootBundle (which would require a widget test binding).
      final File file = File(
        'android/app/src/main/assets/preset_ng_words.json',
      );
      expect(
        file.existsSync(),
        isTrue,
        reason: 'preset_ng_words.json must exist',
      );
      final Object decoded = jsonDecode(file.readAsStringSync());
      expect(decoded, isA<Map<String, dynamic>>());
      final Map<String, dynamic> doc = decoded as Map<String, dynamic>;
      expect(doc['version'], 3, reason: 'schema version must be 3');

      final List<NgPresetCategory> categories = NgPresetCategory.parseDocument(
        doc,
      );
      expect(categories, isNotEmpty);

      // Every category must declare blockSpeechOnly (v1-safe default) and
      // resolve to a non-null displaySubcategory in the shipped file.
      for (final NgPresetCategory c in categories) {
        expect(
          c.policy,
          NgPolicy.blockSpeechOnly,
          reason: 'category ${c.id} must use blockSpeechOnly',
        );
        expect(
          c.displaySubcategory,
          isNotNull,
          reason: 'category ${c.id} must have a displaySubcategory',
        );
        expect(
          c.words,
          isNotEmpty,
          reason: 'category ${c.id} must have at least one word',
        );
      }

      // severe_public_morals must have been split into violence+sexual.
      expect(
        categories.map((NgPresetCategory c) => c.id),
        containsAll(<String>[
          'severe_public_morals_violence',
          'severe_public_morals_sexual',
        ]),
      );
      // The pre-split name must no longer be present.
      expect(
        categories.map((NgPresetCategory c) => c.id),
        isNot(contains('severe_public_morals')),
      );
    });

    test('regression: flattened NG words from v3 match the union of words', () {
      final File file = File(
        'android/app/src/main/assets/preset_ng_words.json',
      );
      final Object decoded = jsonDecode(file.readAsStringSync());
      final List<NgPresetCategory> categories = NgPresetCategory.parseDocument(
        decoded,
      );
      final List<String> flat = NgPresetCategory.flattenWords(categories);

      // Every word should appear exactly once.
      final Set<String> set = flat.toSet();
      expect(
        set.length,
        flat.length,
        reason: 'flattenWords must deduplicate across categories',
      );

      // Sampling: words that existed in the v2 file should still be reachable.
      expect(flat, contains('殺す'));
      expect(flat, contains('凌辱')); // moved into severe_public_morals_sexual
      expect(
        flat,
        contains('拷問配信'),
      ); // moved into severe_public_morals_violence
      expect(flat, contains('児童ポルノ'));
      expect(flat, contains('まんこ'));
    });

    test(
      'regression: severe_public_morals split preserves all original words',
      () {
        // Historical context: v2 had a single `severe_public_morals` category
        // containing 5 words. v3 splits that into violence/sexual subcategories.
        // This test guards against accidental word loss during the split.
        final File file = File(
          'android/app/src/main/assets/preset_ng_words.json',
        );
        final Object decoded = jsonDecode(file.readAsStringSync());
        final List<NgPresetCategory> categories =
            NgPresetCategory.parseDocument(decoded);

        final NgPresetCategory violenceCat = categories.firstWhere(
          (NgPresetCategory c) => c.id == 'severe_public_morals_violence',
        );
        final NgPresetCategory sexualCat = categories.firstWhere(
          (NgPresetCategory c) => c.id == 'severe_public_morals_sexual',
        );
        final Set<String> combined = <String>{
          ...violenceCat.words,
          ...sexualCat.words,
        };

        // Original v2 word set. Must be preserved entirely across the split.
        const Set<String> originalV2Words = <String>{
          'グロ画像',
          '死体画像',
          '凌辱',
          '拷問配信',
          'リベンジポルノ',
        };
        expect(
          combined,
          containsAll(originalV2Words),
          reason: 'all 5 original v2 words must survive the v3 split',
        );

        // Each side must be classified correctly.
        expect(violenceCat.displaySubcategory, NgDisplaySubcategory.violence);
        expect(sexualCat.displaySubcategory, NgDisplaySubcategory.sexual);
      },
    );
  });
}
