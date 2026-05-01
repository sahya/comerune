// Issue #784: comment number rendering on the meta row.
//
// Pins the [_buildMetaSpans] policy that the comment number is prepended
// to the timestamp only when the toggle is on AND the message carries a
// non-null commentNo. Uses the test-only [buildMetaSpansForTesting]
// re-export so we can verify span structure without rendering a full
// CommentRow tree (which would also pull NG matchers / theme bindings).
//
// Sage review (#784, 品質仙人 SHOULD) requested:
//   - explicit indexOf-based ordering pin (T10),
//   - a hidden-state case so the grey + italic policy stays in sync with
//     the timestamp / displayName branches,
//   - a pinned-row pass through PinnedCommentRowHarness to lock the same
//     policy applied to the pinned panel.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/comment_screen.dart';
import 'package:comerune/presentation/theme/app_theme.dart';

/// Concatenates every TextSpan in [spans] (and their descendants) into a
/// single string so the test can pin the rendered order without depending
/// on per-span style minutiae.
String _flatten(List<InlineSpan> spans) {
  final StringBuffer buffer = StringBuffer();
  for (final InlineSpan span in spans) {
    span.visitChildren((InlineSpan child) {
      if (child is TextSpan && child.text != null) {
        buffer.write(child.text);
      }
      return true;
    });
  }
  return buffer.toString();
}

/// Walks the span tree and returns every TextSpan whose `text` matches
/// [needle], so we can pin styling (color / italic) on a specific token.
List<TextSpan> _spansContaining(List<InlineSpan> spans, String needle) {
  final List<TextSpan> hits = <TextSpan>[];
  for (final InlineSpan span in spans) {
    span.visitChildren((InlineSpan child) {
      if (child is TextSpan &&
          child.text != null &&
          child.text!.contains(needle)) {
        hits.add(child);
      }
      return true;
    });
  }
  return hits;
}

void main() {
  final AppThemeColors themeColors = AppTheme.colorsFor(AppThemeMode.light);

  group('_buildMetaSpans commentNo (Issue #784)', () {
    // T9: toggle off → no prefix even when the message carries a number.
    test('omits commentNo span when showCommentNo == false', () {
      final List<InlineSpan> spans = buildMetaSpansForTesting(
        timestamp: '12:34:56',
        showUserName: true,
        displayName: 'user-1',
        timestampFontSize: 12,
        idFontSize: 12,
        timestampColor: themeColors.subtleTextColor,
        idColor: themeColors.subtleTextColor,
        hidden: false,
        showCommentNo: false,
        commentNo: 123,
      );
      final String rendered = _flatten(spans);
      expect(rendered.startsWith('12:34:56'), isTrue);
      expect(rendered.contains('123'), isFalse);
    });

    // T10: toggle on AND commentNo present → number first, then separator,
    // then timestamp. Order is pinned via indexOf so a future refactor
    // that moves the number to the right side cannot land silently.
    test('prepends commentNo before timestamp when toggle on', () {
      final List<InlineSpan> spans = buildMetaSpansForTesting(
        timestamp: '12:34:56',
        showUserName: true,
        displayName: 'user-1',
        timestampFontSize: 12,
        idFontSize: 12,
        timestampColor: themeColors.subtleTextColor,
        idColor: themeColors.subtleTextColor,
        hidden: false,
        showCommentNo: true,
        commentNo: 123,
      );
      final String rendered = _flatten(spans);
      expect(rendered.startsWith('123'), isTrue);
      final int timestampIndex = rendered.indexOf('12:34:56');
      final int numberIndex = rendered.indexOf('123');
      final int displayNameIndex = rendered.indexOf('user-1');
      // Strict order: commentNo < timestamp < displayName.
      expect(numberIndex, lessThan(timestampIndex));
      expect(timestampIndex, lessThan(displayNameIndex));
    });

    // T11: toggle on but commentNo == null → no prefix span (covers
    // operator / system / forwarded chats once the toggle is enabled).
    test('omits commentNo span when commentNo == null even with toggle on', () {
      final List<InlineSpan> spans = buildMetaSpansForTesting(
        timestamp: '12:34:56',
        showUserName: true,
        displayName: 'user-1',
        timestampFontSize: 12,
        idFontSize: 12,
        timestampColor: themeColors.subtleTextColor,
        idColor: themeColors.subtleTextColor,
        hidden: false,
        showCommentNo: true,
        commentNo: null,
      );
      final String rendered = _flatten(spans);
      expect(rendered.startsWith('12:34:56'), isTrue);
    });

    // 賢者2 SHOULD FIX: hidden-state coherence.
    // When the row is `hidden` (NG-masked), every meta span turns grey
    // and italic. The commentNo span must follow the same policy so the
    // comment row stays visually coherent.
    test('hidden row applies grey + italic to commentNo span', () {
      final List<InlineSpan> spans = buildMetaSpansForTesting(
        timestamp: '12:34:56',
        showUserName: true,
        displayName: 'user-1',
        timestampFontSize: 12,
        idFontSize: 12,
        timestampColor: themeColors.subtleTextColor,
        idColor: themeColors.subtleTextColor,
        hidden: true,
        showCommentNo: true,
        commentNo: 123,
      );
      final List<TextSpan> commentNoSpans = _spansContaining(spans, '123');
      expect(commentNoSpans, isNotEmpty);
      for (final TextSpan span in commentNoSpans) {
        expect(span.style?.color, Colors.grey);
        expect(span.style?.fontStyle, FontStyle.italic);
      }
    });
  });

  group('CommentRowHarness commentNo (Issue #784)', () {
    AppMessage buildChat({int? no = 4242}) {
      return AppMessage(
        id: 'm1',
        timestamp: DateTime(2026, 5, 1, 12, 34, 56),
        userId: 'u1',
        userName: 'tester',
        content: 'hello',
        type: AppMessageType.chat,
        commentNo: no,
      );
    }

    Widget wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Material(child: child)),
    );

    testWidgets(
      'CommentRowHarness with showCommentNo true renders the number',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          wrap(
            CommentRowHarness(
              message: buildChat(),
              themeColors: themeColors,
              fontSize: 14,
              showCommentNo: true,
            ),
          ),
        );
        expect(find.textContaining('4242', findRichText: true), findsWidgets);
      },
    );

    testWidgets('CommentRowHarness with showCommentNo false omits the number', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          CommentRowHarness(
            message: buildChat(),
            themeColors: themeColors,
            fontSize: 14,
            showCommentNo: false,
          ),
        ),
      );
      expect(find.textContaining('4242', findRichText: true), findsNothing);
    });
  });

  // 賢者2 SHOULD FIX: pinned-row coverage.
  // Mirrors the inline-row test through PinnedCommentRowHarness so the
  // pinned panel's _buildMetaSpans wiring is also pinned. Without this,
  // PR-1 could regress only in pinned mode and the inline-row test would
  // not catch it.
  group('PinnedCommentRowHarness commentNo (Issue #784)', () {
    AppMessage buildChat({int? no = 5555}) {
      return AppMessage(
        id: 'pinned-m1',
        timestamp: DateTime(2026, 5, 1, 12, 34, 56),
        userId: 'u1',
        userName: 'tester',
        content: 'hello',
        type: AppMessageType.chat,
        commentNo: no,
      );
    }

    Widget wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Material(child: child)),
    );

    testWidgets('pinned row renders commentNo when toggle on', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          PinnedCommentRowHarness(
            message: buildChat(),
            themeColors: themeColors,
            fontSize: 14,
            showCommentNo: true,
            onUnpin: () {},
          ),
        ),
      );
      expect(find.textContaining('5555', findRichText: true), findsWidgets);
    });

    testWidgets('pinned row omits commentNo when toggle off', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          PinnedCommentRowHarness(
            message: buildChat(),
            themeColors: themeColors,
            fontSize: 14,
            showCommentNo: false,
            onUnpin: () {},
          ),
        ),
      );
      expect(find.textContaining('5555', findRichText: true), findsNothing);
    });
  });
}
