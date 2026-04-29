import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/comment_screen.dart';
import 'package:comerune/presentation/theme/app_theme.dart';

/// Widget-level coverage for the configurable 2-line meta-row font percent.
///
/// The domain / application layers are exhaustively unit-tested elsewhere
/// (see `app_settings_test.dart`, `settings_store_test.dart`). This file
/// pins the rendering contract: that the percent value flows from the
/// public widget prop down to the actual `TextSpan.style.fontSize` of the
/// timestamp + display-name spans, that 100% sets the meta size equal to
/// the body, and that small percentages are floored to 9px so the row
/// never collapses to sub-pixel text.
void main() {
  final AppThemeColors themeColors = AppTheme.colorsFor(AppThemeMode.light);

  AppMessage buildChatMessage() {
    return AppMessage(
      id: 'msg-1',
      timestamp: DateTime(2026, 3, 22, 12, 0, 0),
      userId: 'user-1',
      userName: 'tester',
      content: 'hello',
      type: AppMessageType.chat,
    );
  }

  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: Material(child: child)),
    );
  }

  /// Returns the `fontSize` of the very first non-empty `TextSpan` leaf
  /// rendered by `_CommentRow` in two-line mode — that is the timestamp
  /// span produced by `_buildMetaSpans`.
  ///
  /// The harness is configured with no NG matcher, no leading icon, and
  /// `showUserName: true`, so the first leaf is unambiguously the
  /// timestamp. A dedicated walker keeps the assertion robust against
  /// future tweaks to the badge / icon path that prepend `WidgetSpan`s.
  double? readMetaFontSize(WidgetTester tester) {
    // The two-line layout uses a Column with the meta `Text.rich` first.
    final RichText meta = tester
        .widgetList<RichText>(find.byType(RichText))
        .first;
    double? found;
    void walk(InlineSpan span) {
      if (found != null) {
        return;
      }
      if (span is TextSpan) {
        if (span.text != null && span.text!.isNotEmpty) {
          found = span.style?.fontSize;
          return;
        }
        for (final InlineSpan child in span.children ?? const <InlineSpan>[]) {
          walk(child);
          if (found != null) {
            return;
          }
        }
      }
    }

    walk(meta.text);
    return found;
  }

  Future<double?> pumpAndReadMetaFontSize(
    WidgetTester tester, {
    required double bodyFontSize,
    required int percent,
  }) async {
    await tester.pumpWidget(
      wrap(
        CommentRowHarness(
          message: buildChatMessage(),
          themeColors: themeColors,
          fontSize: bodyFontSize,
          showUserName: true,
          commentTwoLineEnabled: true,
          commentTwoLineMetaFontPercent: percent,
        ),
      ),
    );
    return readMetaFontSize(tester);
  }

  group('two-line meta font percent', () {
    testWidgets(
      '40% (default) of body 20px renders timestamp at 8px floored to 9px',
      (WidgetTester tester) async {
        // 40% of 20 = 8.0, but the 9px absolute floor wins. The floor is
        // intentional: keeping meta text legible at small body sizes is
        // more important than honoring the exact percent.
        final double? size = await pumpAndReadMetaFontSize(
          tester,
          bodyFontSize: 20,
          percent: commentTwoLineMetaFontPercentDefault,
        );
        expect(size, closeTo(9.0, 0.01));
      },
    );

    testWidgets('50% of body 20px renders timestamp at 10px', (
      WidgetTester tester,
    ) async {
      final double? size = await pumpAndReadMetaFontSize(
        tester,
        bodyFontSize: 20,
        percent: 50,
      );
      expect(size, closeTo(10.0, 0.01));
    });

    testWidgets('100% renders timestamp at body font size', (
      WidgetTester tester,
    ) async {
      final double? size = await pumpAndReadMetaFontSize(
        tester,
        bodyFontSize: 24,
        percent: commentTwoLineMetaFontPercentMax,
      );
      expect(size, closeTo(24.0, 0.01));
    });

    testWidgets(
      '20% (min) is clamped up to 9px floor regardless of body size',
      (WidgetTester tester) async {
        // 20% of 14 = 2.8 → clamp floor 9px applies.
        final double? size = await pumpAndReadMetaFontSize(
          tester,
          bodyFontSize: 14,
          percent: commentTwoLineMetaFontPercentMin,
        );
        expect(size, closeTo(9.0, 0.01));
      },
    );

    testWidgets(
      'meta size never exceeds body size even at 100% with small body',
      (WidgetTester tester) async {
        // Body 10px, percent 100% → meta = 10. The clamp upper bound is
        // body fontSize, so meta must equal body, not overflow.
        final double? size = await pumpAndReadMetaFontSize(
          tester,
          bodyFontSize: 10,
          percent: 100,
        );
        expect(size, closeTo(10.0, 0.01));
      },
    );

    testWidgets(
      'different percent values produce monotonically larger meta size',
      (WidgetTester tester) async {
        // Use a body large enough that the 9px floor does not interfere.
        const double body = 30;
        final double? at40 = await pumpAndReadMetaFontSize(
          tester,
          bodyFontSize: body,
          percent: 40,
        );
        final double? at60 = await pumpAndReadMetaFontSize(
          tester,
          bodyFontSize: body,
          percent: 60,
        );
        final double? at90 = await pumpAndReadMetaFontSize(
          tester,
          bodyFontSize: body,
          percent: 90,
        );
        expect(at40, closeTo(12.0, 0.01));
        expect(at60, closeTo(18.0, 0.01));
        expect(at90, closeTo(27.0, 0.01));
        // Sanity: the percent is actually doing something.
        expect(at40! < at60!, isTrue);
        expect(at60 < at90!, isTrue);
      },
    );
  });
}
