import 'package:comerune/application/filter/legacy_ng_parser.dart';
import 'package:comerune/domain/models/ng_word_rule.dart';
import 'package:flutter_test/flutter_test.dart';

/// Issue #727: direct unit tests for [LegacyNgParser.mergeLegacyNgWordRules].
///
/// The merge helper is exercised indirectly via the import legacy-fallback
/// path, but it deserves dedicated tests since the importer relies on its
/// dedup / precedence rules to match the in-place migrator's behaviour.
void main() {
  group('LegacyNgParser.mergeLegacyNgWordRules', () {
    test('empty inputs produce an empty list', () {
      final List<NgWordRule> result = LegacyNgParser.mergeLegacyNgWordRules(
        structuredRules: const <NgWordRule>[],
        legacyNgWords: '',
      );
      expect(result, isEmpty);
    });

    test('structured rules only — returned as-is, dedup applied', () {
      final List<NgWordRule> result = LegacyNgParser.mergeLegacyNgWordRules(
        structuredRules: const <NgWordRule>[
          NgWordRule(pattern: 'a'),
          NgWordRule(pattern: 'b'),
          // Duplicate pattern should be dropped.
          NgWordRule(pattern: 'a'),
        ],
        legacyNgWords: '',
      );
      expect(result.map((NgWordRule r) => r.pattern).toList(), <String>[
        'a',
        'b',
      ]);
    });

    test('legacy ngWords only — each line becomes an enabled rule', () {
      final List<NgWordRule> result = LegacyNgParser.mergeLegacyNgWordRules(
        structuredRules: const <NgWordRule>[],
        legacyNgWords: 'foo\nbar\nbaz',
      );
      expect(result.length, 3);
      expect(
        result.every((NgWordRule r) => r.enabled),
        isTrue,
        reason: 'legacy lines must default to enabled = true',
      );
      expect(result.map((NgWordRule r) => r.pattern).toList(), <String>[
        'foo',
        'bar',
        'baz',
      ]);
    });

    test('both sources — structured wins on duplicate patterns; legacy lines '
        'not in structured are appended', () {
      final List<NgWordRule> result = LegacyNgParser.mergeLegacyNgWordRules(
        structuredRules: const <NgWordRule>[
          NgWordRule(pattern: 'shared', enabled: false),
          NgWordRule(pattern: 'only-structured'),
        ],
        legacyNgWords: 'shared\nonly-legacy',
      );
      expect(result.map((NgWordRule r) => r.pattern).toList(), <String>[
        'shared',
        'only-structured',
        'only-legacy',
      ]);
      // Structured "shared" wins, keeping enabled = false.
      final NgWordRule shared = result.firstWhere(
        (NgWordRule r) => r.pattern == 'shared',
      );
      expect(shared.enabled, isFalse);
    });

    test('empty / whitespace-only patterns are dropped from both sources', () {
      final List<NgWordRule> result = LegacyNgParser.mergeLegacyNgWordRules(
        structuredRules: const <NgWordRule>[
          NgWordRule(pattern: ''),
          NgWordRule(pattern: 'kept'),
        ],
        legacyNgWords: '\n   \n\nalso-kept\n',
      );
      expect(result.map((NgWordRule r) => r.pattern).toList(), <String>[
        'kept',
        'also-kept',
      ]);
    });

    test(
      'structured rule with enabled=false is preserved with the flag intact',
      () {
        final List<NgWordRule> result = LegacyNgParser.mergeLegacyNgWordRules(
          structuredRules: const <NgWordRule>[
            NgWordRule(pattern: 'disabled-rule', enabled: false),
          ],
          legacyNgWords: '',
        );
        expect(result.length, 1);
        expect(result.first.pattern, 'disabled-rule');
        expect(result.first.enabled, isFalse);
      },
    );
  });
}
