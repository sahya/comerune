import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/data/comment_log/comment_log_tag.dart';
import 'package:comerune/domain/models/ng_display_subcategory.dart';

void main() {
  group('CommentLogTag.filtered', () {
    test('returns the bracketed reason:subcategory string', () {
      expect(
        CommentLogTag.filtered(NgDisplaySubcategory.violence),
        '[filtered:violence]',
      );
      expect(
        CommentLogTag.filtered(NgDisplaySubcategory.sexual),
        '[filtered:sexual]',
      );
      expect(
        CommentLogTag.filtered(NgDisplaySubcategory.discrimination),
        '[filtered:discrimination]',
      );
      expect(
        CommentLogTag.filtered(NgDisplaySubcategory.minors),
        '[filtered:minors]',
      );
    });
  });

  group('CommentLogTag.speechBlocked', () {
    test('returns the bracketed reason:subcategory string', () {
      // Reserved for #615 wiring; the format is fixed here so it does
      // not drift between issues.
      for (final NgDisplaySubcategory sub in NgDisplaySubcategory.values) {
        expect(
          CommentLogTag.speechBlocked(sub),
          '[speech_blocked:${sub.wireName}]',
        );
      }
    });
  });

  group('CommentLogTag.applyTag', () {
    test('returns content unchanged when tag is null', () {
      expect(CommentLogTag.applyTag(content: 'こんにちは', tag: null), 'こんにちは');
    });

    test('returns content unchanged when tag is empty', () {
      expect(CommentLogTag.applyTag(content: 'こんにちは', tag: ''), 'こんにちは');
    });

    test('prepends the tag with a single space separator', () {
      expect(
        CommentLogTag.applyTag(
          content: '客がストリートファイトしたのか',
          tag: CommentLogTag.filtered(NgDisplaySubcategory.violence),
        ),
        '[filtered:violence] 客がストリートファイトしたのか',
      );
    });
  });

  group('CommentLogTag.logTagPattern', () {
    test('matches all four filtered subcategories at the start', () {
      for (final NgDisplaySubcategory sub in NgDisplaySubcategory.values) {
        final String line = '${CommentLogTag.filtered(sub)} hello world';
        final Match? match = CommentLogTag.logTagPattern.firstMatch(line);
        expect(match, isNotNull, reason: 'should match for ${sub.wireName}');
        expect(match!.group(1), 'filtered');
        expect(match.group(2), sub.wireName);
      }
    });

    test('matches all four speech_blocked subcategories at the start', () {
      for (final NgDisplaySubcategory sub in NgDisplaySubcategory.values) {
        final String line = '${CommentLogTag.speechBlocked(sub)} hello world';
        final Match? match = CommentLogTag.logTagPattern.firstMatch(line);
        expect(match, isNotNull, reason: 'should match for ${sub.wireName}');
        expect(match!.group(1), 'speech_blocked');
        expect(match.group(2), sub.wireName);
      }
    });

    test('does not match an unknown reason', () {
      expect(
        CommentLogTag.logTagPattern.hasMatch('[hidden:violence] body'),
        isFalse,
      );
    });

    test('does not match an unknown subcategory', () {
      expect(
        CommentLogTag.logTagPattern.hasMatch('[filtered:other] body'),
        isFalse,
      );
    });

    test('does not match a tag in the middle of the content', () {
      expect(
        CommentLogTag.logTagPattern.hasMatch(
          'preamble [filtered:violence] body',
        ),
        isFalse,
      );
    });

    test('requires a whitespace separator after the tag', () {
      expect(
        CommentLogTag.logTagPattern.hasMatch('[filtered:violence]body'),
        isFalse,
      );
    });

    test(
      'matches every NgDisplaySubcategory wire name (enum / regex sync)',
      () {
        // Regression guard: logTagPattern is generated from
        // NgDisplaySubcategory.values, so the two must stay in sync.
        // Adding a new enum value must not require a manual regex update.
        for (final NgDisplaySubcategory sub in NgDisplaySubcategory.values) {
          final String filteredLine = '${CommentLogTag.filtered(sub)} body';
          final String speechBlockedLine =
              '${CommentLogTag.speechBlocked(sub)} body';
          expect(
            CommentLogTag.logTagPattern.hasMatch(filteredLine),
            isTrue,
            reason: 'filtered tag for $sub must match',
          );
          expect(
            CommentLogTag.logTagPattern.hasMatch(speechBlockedLine),
            isTrue,
            reason: 'speech_blocked tag for $sub must match',
          );
        }
      },
    );

    test('rejects unknown subcategory values (regex fidelity)', () {
      // The subcategory alternation must be exhaustive, i.e. it must not
      // accidentally widen to accept unknown labels (which would mask
      // future spec drift).
      expect(
        CommentLogTag.logTagPattern.hasMatch('[filtered:unknown] body'),
        isFalse,
      );
      expect(CommentLogTag.logTagPattern.hasMatch('[filtered:] body'), isFalse);
    });
  });
}
