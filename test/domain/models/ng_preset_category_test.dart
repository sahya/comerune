import 'dart:convert';
import 'dart:io';

import 'package:comerune/data/filter/ng_dict_cipher.dart';
import 'package:comerune/domain/models/ng_display_subcategory.dart';
import 'package:comerune/domain/models/ng_policy.dart';
import 'package:comerune/domain/models/ng_preset_category.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads and decrypts the shipped preset asset (committed as the encrypted
/// `preset_ng_words.enc`). Mirrors the runtime decrypt path so these
/// regression tests still exercise the real bundled dictionary while staying
/// independent of Flutter's rootBundle.
Object _loadShippedPresetDoc() {
  final File file = File('android/app/src/main/assets/preset_ng_words.enc');
  return jsonDecode(utf8.decode(decryptNgDict(file.readAsBytesSync())))
      as Object;
}

/// SHA-256 hex of [word]'s UTF-8 bytes. The shipped-dictionary regression
/// tests below assert against these digests instead of plaintext so the real
/// dictionary words do not live in the test source (the encrypted `.enc` is
/// the only committed copy).
///
/// To regenerate an expected digest for a word (e.g. when the historical
/// v2-era set is audited), compute the SHA-256 of its UTF-8 bytes — this
/// matches `printf '%s' '<word>' | sha256sum` and equals `_h('<word>')`.
String _h(String word) => sha256.convert(utf8.encode(word)).toString();

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
            'words': <String>['ngword', 'ngwordb'],
          },
          'child_safety': <String, dynamic>{
            'description': 'child',
            'policy': 'blockSpeechOnly',
            'displaySubcategory': 'minors',
            'words': <String>['ngwordc'],
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
      expect(crime.words, <String>['ngword', 'ngwordb']);
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
      // The shipped asset is committed in encrypted form; decrypt it the
      // same way the runtime loader does. Read from disk directly so we are
      // independent of Flutter's rootBundle (which would require a widget
      // test binding).
      final File file = File('android/app/src/main/assets/preset_ng_words.enc');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'preset_ng_words.enc must exist',
      );
      final Object decoded = _loadShippedPresetDoc();
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
      final Object decoded = _loadShippedPresetDoc();
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

      // Sampling: a fixed set of v2-era words must still be reachable after
      // the v3 split. Asserted by SHA-256 digest (not plaintext) so the real
      // dictionary words stay out of the test source.
      final Set<String> flatHashes = flat.map(_h).toSet();
      const List<String> v2EraWordHashes = <String>[
        '17ab6be094215b5f005ee2a3919020107a1848472beafaf672b3eb54e299e486',
        'dfdb6153dcfd20400d3aff0948dbbcb5de3456db62784a19b7b509661e8ae530',
        'ff45489f2434e0ad488203f3cbf6adabbb9f833a9574b06278203a93b73ddd9d',
        'efa2b643d4606882e19d6a98d93a1956884d09cfb3fa70590afa027c5e169890',
        '5abee33174d01effaab1fd2f167c9616365e7932d0ce83ca2df5c39272aebb27',
      ];
      for (final String digest in v2EraWordHashes) {
        expect(
          flatHashes,
          contains(digest),
          reason: 'v2-era word (sha256 $digest) must remain reachable',
        );
      }
    });

    test(
      'regression: severe_public_morals split preserves all original words',
      () {
        // Historical context: v2 had a single `severe_public_morals` category
        // containing 5 words. v3 splits that into violence/sexual subcategories.
        // This test guards against accidental word loss during the split.
        final Object decoded = _loadShippedPresetDoc();
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

        // The 5 original v2 words must be preserved entirely across the
        // split. Compared by SHA-256 digest so the plaintext words are not
        // embedded in the test source.
        const Set<String> originalV2WordHashes = <String>{
          'fb7ff9fdeb0eed19d550221588c915d8f0a1098c6bac5d4bdeaef7ca7f5be1fc',
          'fdb671bc3b17e05f8aa6fbbb01e4ca9434770a7bb3344e627a5961bf1e08044e',
          'dfdb6153dcfd20400d3aff0948dbbcb5de3456db62784a19b7b509661e8ae530',
          'ff45489f2434e0ad488203f3cbf6adabbb9f833a9574b06278203a93b73ddd9d',
          'dbf84b8ed512e0bb61732d645ab67b8ee0ffa14c4029271ab052caad8714b745',
        };
        expect(
          combined.map(_h).toSet(),
          containsAll(originalV2WordHashes),
          reason: 'all 5 original v2 words must survive the v3 split',
        );

        // Each side must be classified correctly.
        expect(violenceCat.displaySubcategory, NgDisplaySubcategory.violence);
        expect(sexualCat.displaySubcategory, NgDisplaySubcategory.sexual);
      },
    );
  });
}
