import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/domain/utils/search_normalizer.dart';
import 'package:comerune/presentation/screens/comment_screen.dart';
import 'package:comerune/presentation/theme/app_theme.dart';

/// Issue #471: comment-body keyword highlighting.
///
/// Verifies that when a search query is active the matched substring is
/// rendered with `secondaryContainer` background, while the rest of the
/// body keeps the base style. Tests pump a single row through
/// [CommentRowHarness] so we exercise the production rendering helper
/// without spinning up the full screen.
void main() {
  final AppThemeColors themeColors = AppTheme.colorsFor(AppThemeMode.light);

  AppMessage buildMessage({
    String id = 'msg-1',
    String content = 'hello world',
  }) {
    return AppMessage(
      id: id,
      timestamp: DateTime(2026, 5, 1, 12, 0, 0),
      userId: 'user-1',
      userName: 'テスト',
      content: content,
      type: AppMessageType.chat,
    );
  }

  /// Flatten every TextSpan reachable from any RichText currently on
  /// screen, regardless of nesting depth.
  List<TextSpan> collectTextSpans(WidgetTester tester) {
    final List<TextSpan> result = <TextSpan>[];
    void walk(InlineSpan? span) {
      if (span is TextSpan) {
        result.add(span);
        final List<InlineSpan>? children = span.children;
        if (children != null) {
          for (final InlineSpan c in children) {
            walk(c);
          }
        }
      }
    }

    for (final RichText rt in tester.widgetList<RichText>(
      find.byType(RichText),
    )) {
      walk(rt.text);
    }
    return result;
  }

  /// Returns spans whose style has the highlight background color.
  List<TextSpan> highlightedSpans(List<TextSpan> spans, Color highlightColor) {
    return spans
        .where(
          (TextSpan s) =>
              s.text != null &&
              s.text!.isNotEmpty &&
              s.style?.backgroundColor == highlightColor,
        )
        .toList();
  }

  Color highlightColorFor(BuildContext context) =>
      Theme.of(context).colorScheme.secondaryContainer;

  /// Pumps the harness inside a Builder so we can read the resolved
  /// `secondaryContainer` color from the same theme that rendered the row.
  Future<Color> pumpAndCaptureHighlightColor(
    WidgetTester tester,
    Widget child,
  ) async {
    Color? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) {
              captured = highlightColorFor(context);
              return Material(child: child);
            },
          ),
        ),
      ),
    );
    return captured!;
  }

  group('Issue #471: search highlight in comment body', () {
    testWidgets('empty query renders body without highlight color', (
      WidgetTester tester,
    ) async {
      final Color highlight = await pumpAndCaptureHighlightColor(
        tester,
        CommentRowHarness(
          message: buildMessage(content: 'hello world'),
          themeColors: themeColors,
          fontSize: 14,
          // No normalizedSearchQuery: simulates the not-searching state.
        ),
      );

      final List<TextSpan> spans = collectTextSpans(tester);
      // The body text should be present somewhere in the row.
      expect(
        find.textContaining('hello world', findRichText: true),
        findsWidgets,
      );
      // No span should carry the highlight background color.
      expect(highlightedSpans(spans, highlight), isEmpty);
    });

    testWidgets(
      'case-insensitive single match yields exactly one highlighted span',
      (WidgetTester tester) async {
        final Color highlight = await pumpAndCaptureHighlightColor(
          tester,
          CommentRowHarness(
            message: buildMessage(content: 'Hello World'),
            themeColors: themeColors,
            fontSize: 14,
            normalizedSearchQuery: normalizeForSearch('hello'),
          ),
        );

        final List<TextSpan> spans = collectTextSpans(tester);
        final List<TextSpan> hits = highlightedSpans(spans, highlight);
        expect(hits, hasLength(1));
        expect(hits.first.text, 'Hello');
        // Foreground color is set so contrast survives the colored bg.
        expect(hits.first.style?.color, isNotNull);
      },
    );

    testWidgets('multiple matches in one body all get highlighted', (
      WidgetTester tester,
    ) async {
      final Color highlight = await pumpAndCaptureHighlightColor(
        tester,
        CommentRowHarness(
          message: buildMessage(content: 'ab AB ab cd ab'),
          themeColors: themeColors,
          fontSize: 14,
          normalizedSearchQuery: normalizeForSearch('ab'),
        ),
      );

      final List<TextSpan> spans = collectTextSpans(tester);
      final List<TextSpan> hits = highlightedSpans(spans, highlight);
      // Three "ab" + one "AB" = 4 matches in "ab AB ab cd ab".
      expect(hits, hasLength(4));
      // All matches are length 2 substrings of the original content,
      // preserving the original case.
      for (final TextSpan s in hits) {
        expect(s.text!.length, 2);
        expect(s.text!.toLowerCase(), 'ab');
      }
    });

    testWidgets(
      'emoji is not split mid-codepoint when the query matches inside it',
      (WidgetTester tester) async {
        // Family emoji built from a ZWJ sequence — the canonical case for
        // "naively splitting by code unit corrupts the rendered text".
        const String emoji = '\u{1F468}‍\u{1F469}‍\u{1F466}';
        final String content = 'pre${emoji}post';
        // A query that, in code-unit space, would land inside the emoji's
        // surrogate pair. We pass the high-surrogate of the man emoji as a
        // standalone string so a naive `indexOf` would split the pair.
        final String roguePiece = String.fromCharCode(emoji.codeUnitAt(0));

        final Color highlight = await pumpAndCaptureHighlightColor(
          tester,
          CommentRowHarness(
            message: buildMessage(content: content),
            themeColors: themeColors,
            fontSize: 14,
            normalizedSearchQuery: normalizeForSearch(roguePiece),
          ),
        );

        final List<TextSpan> spans = collectTextSpans(tester);
        // Reconstruct the rendered body by concatenating only the spans
        // that belong to the body text. We assert on the multiset of
        // characters: the original body string MUST appear unchanged when
        // the body spans are joined in render order.
        final String joined = spans.map((TextSpan s) => s.text ?? '').join();
        // The original content must still be a substring of the rendered
        // text (the row also renders meta like timestamps around it).
        expect(
          joined.contains(content),
          isTrue,
          reason: 'rendered text must contain the original body verbatim',
        );

        // No span should contain a lone surrogate — that would indicate a
        // split emoji.
        for (final TextSpan s in spans) {
          final String? t = s.text;
          if (t == null) continue;
          for (int i = 0; i < t.length; i++) {
            final int cu = t.codeUnitAt(i);
            final bool isHigh = cu >= 0xD800 && cu <= 0xDBFF;
            final bool isLow = cu >= 0xDC00 && cu <= 0xDFFF;
            if (isHigh) {
              // Must be followed by a low surrogate in the same span.
              expect(
                i + 1 < t.length,
                isTrue,
                reason: 'high surrogate at end of span: split emoji',
              );
              final int next = t.codeUnitAt(i + 1);
              expect(
                next >= 0xDC00 && next <= 0xDFFF,
                isTrue,
                reason: 'high surrogate not followed by low: split emoji',
              );
              i++; // skip the low surrogate
            } else if (isLow) {
              fail('lone low surrogate in span: split emoji');
            }
          }
        }

        // Whether or not the emoji ended up highlighted, the highlight (if
        // any) must cover whole graphemes, i.e. include at least the full
        // emoji cluster — never a half-codepoint slice. We check that no
        // highlighted span contains a lone surrogate (covered above) and
        // that the joined render matches the original content.
        final List<TextSpan> hits = highlightedSpans(spans, highlight);
        for (final TextSpan h in hits) {
          // Each highlighted span text must round-trip through Dart string
          // operations without producing replacement characters.
          expect(h.text!.contains('�'), isFalse);
        }
      },
    );

    testWidgets('clearing the query removes the highlight', (
      WidgetTester tester,
    ) async {
      // Render once with a query active so we know highlights exist...
      Color highlight = await pumpAndCaptureHighlightColor(
        tester,
        CommentRowHarness(
          message: buildMessage(content: 'Hello World'),
          themeColors: themeColors,
          fontSize: 14,
          normalizedSearchQuery: normalizeForSearch('hello'),
        ),
      );
      expect(
        highlightedSpans(collectTextSpans(tester), highlight),
        isNotEmpty,
        reason: 'precondition: highlight present while query is active',
      );
      // ...then re-pump the same row with the query cleared and assert
      // the highlight has been removed. This exercises the AC item
      // "クリアで装飾が消える".
      highlight = await pumpAndCaptureHighlightColor(
        tester,
        CommentRowHarness(
          message: buildMessage(content: 'Hello World'),
          themeColors: themeColors,
          fontSize: 14,
        ),
      );
      expect(highlightedSpans(collectTextSpans(tester), highlight), isEmpty);
    });
  });

  group('Issue #471: search highlight on pinned rows', () {
    testWidgets(
      'pinned row in single-line layout highlights matched substring',
      (WidgetTester tester) async {
        final Color highlight = await pumpAndCaptureHighlightColor(
          tester,
          PinnedCommentRowHarness(
            message: buildMessage(content: 'Hello pinned World'),
            themeColors: themeColors,
            fontSize: 14,
            onUnpin: () {},
            normalizedSearchQuery: normalizeForSearch('pinned'),
          ),
        );

        final List<TextSpan> spans = collectTextSpans(tester);
        final List<TextSpan> hits = highlightedSpans(spans, highlight);
        expect(hits, hasLength(1));
        expect(hits.first.text, 'pinned');
      },
    );

    testWidgets('pinned row in two-line layout highlights matched substring', (
      WidgetTester tester,
    ) async {
      final Color highlight = await pumpAndCaptureHighlightColor(
        tester,
        PinnedCommentRowHarness(
          message: buildMessage(content: 'Hello pinned World'),
          themeColors: themeColors,
          fontSize: 14,
          commentTwoLineEnabled: true,
          onUnpin: () {},
          normalizedSearchQuery: normalizeForSearch('pinned'),
        ),
      );

      final List<TextSpan> spans = collectTextSpans(tester);
      final List<TextSpan> hits = highlightedSpans(spans, highlight);
      expect(hits, hasLength(1));
      expect(hits.first.text, 'pinned');
    });

    testWidgets(
      'pinned row with no query renders body without highlight color',
      (WidgetTester tester) async {
        final Color highlight = await pumpAndCaptureHighlightColor(
          tester,
          PinnedCommentRowHarness(
            message: buildMessage(content: 'Hello pinned World'),
            themeColors: themeColors,
            fontSize: 14,
            onUnpin: () {},
          ),
        );

        final List<TextSpan> spans = collectTextSpans(tester);
        expect(highlightedSpans(spans, highlight), isEmpty);
      },
    );
  });
}
