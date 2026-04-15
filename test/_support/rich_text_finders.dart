import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finds the top-most [RichText] whose combined plain text contains
/// [needle]. Fails the test if none is found.
///
/// Useful for widget tests that need to inspect text styling (e.g. color)
/// of a span inside a larger rendered tree, where a plain
/// `find.text(...)` would only let you assert presence/absence.
RichText findRichTextContaining(WidgetTester tester, String needle) {
  final Iterable<RichText> candidates = tester
      .widgetList<RichText>(find.byType(RichText))
      .where((RichText rt) => rt.text.toPlainText().contains(needle));
  expect(
    candidates.isNotEmpty,
    isTrue,
    reason: 'no RichText contains "$needle"',
  );
  return candidates.first;
}

/// Walks an [InlineSpan] tree and returns the color of the first
/// [TextSpan] whose own text equals [exactText]. Returns null if no match.
///
/// Matches on _exact_ span text (not substring) so callers can assert the
/// color of one particular fragment even when multiple spans share the
/// same root RichText.
Color? findSpanColor(InlineSpan root, String exactText) {
  Color? found;
  root.visitChildren((InlineSpan span) {
    if (found != null) return false;
    if (span is TextSpan && span.text == exactText) {
      found = span.style?.color;
      return false;
    }
    return true;
  });
  return found;
}
