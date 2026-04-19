import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/matchers/ng_matcher.dart';
import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/domain/models/ng_display_subcategory.dart';
import 'package:comerune/domain/models/ng_policy.dart';
import 'package:comerune/domain/models/ng_preset_category.dart';
import 'package:comerune/presentation/screens/comment_screen.dart';
import 'package:comerune/presentation/theme/app_theme.dart';

/// Issue #616: visual "read-skipped" affordance for comments that are
/// displayed but still skipped by the TTS engine (preset match with
/// `matchedSubcategory != null`).
void main() {
  final AppThemeColors themeColors = AppTheme.colorsFor(AppThemeMode.light);

  AppMessage buildMessage({
    String id = 'msg-1',
    AppMessageType type = AppMessageType.chat,
    String content = '暴力シーンだね',
  }) {
    return AppMessage(
      id: id,
      timestamp: DateTime(2026, 3, 22, 12, 0, 0),
      userId: 'user-1',
      userName: 'テスト',
      content: content,
      type: type,
    );
  }

  NgMatcher buildPresetMatcher({
    NgDisplaySubcategory subcategory = NgDisplaySubcategory.violence,
    String word = '暴力',
  }) {
    final NgPresetCategory category = NgPresetCategory(
      id: 'violence',
      description: '',
      policy: NgPolicy.blockSpeechOnly,
      displaySubcategory: subcategory,
      words: <String>[word],
    );
    return NgMatcher(
      presetCategories: <NgPresetCategory>[category],
      userNgWords: const <String>[],
      normalizer: (String s) => s,
    );
  }

  NgMatcher buildUserMatcher({String word = '個人攻撃'}) {
    return NgMatcher(
      presetCategories: const <NgPresetCategory>[],
      userNgWords: <String>[word],
      normalizer: (String s) => s,
    );
  }

  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: Material(child: child)),
    );
  }

  bool rowContainsIcon(WidgetTester tester, IconData data) {
    return tester
        .widgetList<Icon>(find.byType(Icon))
        .any((Icon icon) => icon.icon == data);
  }

  // Counts Opacity widgets whose opacity is the exact read-skipped value.
  // Scoped by widget.opacity rather than ancestor type so the count is
  // stable even if Flutter internals add incidental AnimatedOpacity nodes
  // elsewhere in the tree.
  int readSkippedOpacityCount(WidgetTester tester) {
    return tester
        .widgetList<Opacity>(find.byType(Opacity))
        .where((Opacity o) => (o.opacity - 0.7).abs() < 1e-6)
        .length;
  }

  group('_CommentRow read-skipped badge', () {
    testWidgets('shows volume_off icon and Opacity body when preset matches', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          CommentRowHarness(
            message: buildMessage(content: '暴力シーンだね'),
            themeColors: themeColors,
            fontSize: 14,
            ngMatcher: buildPresetMatcher(),
          ),
        ),
      );

      expect(rowContainsIcon(tester, Icons.volume_off), isTrue);
      expect(readSkippedOpacityCount(tester), greaterThan(0));
      // Body content should still be present somewhere in the row.
      expect(find.textContaining('暴力シーン', findRichText: true), findsWidgets);
    });

    testWidgets('user-defined NG match shows no badge and no Opacity', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          CommentRowHarness(
            message: buildMessage(content: '個人攻撃のコメント'),
            themeColors: themeColors,
            fontSize: 14,
            ngMatcher: buildUserMatcher(word: '個人攻撃'),
          ),
        ),
      );

      expect(rowContainsIcon(tester, Icons.volume_off), isFalse);
      expect(readSkippedOpacityCount(tester), 0);
    });

    testWidgets('non-matching message shows no badge and no Opacity', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          CommentRowHarness(
            message: buildMessage(content: '普通のコメント'),
            themeColors: themeColors,
            fontSize: 14,
            ngMatcher: buildPresetMatcher(),
          ),
        ),
      );

      expect(rowContainsIcon(tester, Icons.volume_off), isFalse);
      expect(readSkippedOpacityCount(tester), 0);
    });

    testWidgets('two-line mode renders badge and Opacity-wrapped body', (
      WidgetTester tester,
    ) async {
      // Badge in 2-line mode must be sized by the body [fontSize], not the
      // smaller meta-line font. This is the contract the streamer depends
      // on to scan silenced rows regardless of 1-line / 2-line display —
      // if someone later swaps this back to [timestampFontSize] the badge
      // shrinks to ~60% and that regression must fail here.
      const double baselineFontSize = 14.0;
      await tester.pumpWidget(
        wrap(
          CommentRowHarness(
            message: buildMessage(content: '暴力シーンだね'),
            themeColors: themeColors,
            fontSize: baselineFontSize,
            commentTwoLineEnabled: true,
            ngMatcher: buildPresetMatcher(),
          ),
        ),
      );

      expect(rowContainsIcon(tester, Icons.volume_off), isTrue);
      expect(readSkippedOpacityCount(tester), greaterThan(0));
      final Icon badge = tester
          .widgetList<Icon>(find.byType(Icon))
          .firstWhere((Icon i) => i.icon == Icons.volume_off);
      expect(badge.size, closeTo(baselineFontSize * 0.95, 0.01));
    });

    testWidgets('semantics label mentions subcategory Japanese label', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          wrap(
            CommentRowHarness(
              message: buildMessage(content: '暴力シーンだね'),
              themeColors: themeColors,
              fontSize: 14,
              ngMatcher: buildPresetMatcher(),
            ),
          ),
        );

        // The MergeSemantics wrapper concatenates our label with all
        // descendant labels (timestamp + username + body), so match by
        // prefix regex rather than exact string.
        expect(
          find.bySemanticsLabel(RegExp('^読み上げ対象外のコメント。暴力表現を含みます')),
          findsOneWidget,
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets(
      'zebra striping is preserved when a read-skipped row is on odd index',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          wrap(
            CommentRowHarness(
              message: buildMessage(content: '暴力シーンだね'),
              themeColors: themeColors,
              fontSize: 14,
              zebraStripingEnabled: true,
              commentIndex: 1,
              ngMatcher: buildPresetMatcher(),
            ),
          ),
        );

        expect(rowContainsIcon(tester, Icons.volume_off), isTrue);
        // Zebra stripe is applied via the row Container's color; look for a
        // Container with a non-null color ancestor of the row.
        final Finder coloredContainer = find.descendant(
          of: find.byType(CommentRowHarness),
          matching: find.byWidgetPredicate(
            (Widget w) => w is Container && w.color != null,
          ),
        );
        expect(coloredContainer, findsWidgets);
      },
    );

    testWidgets(
      'gift type icon coexists with read-skipped badge and the read-skipped badge comes first',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          wrap(
            CommentRowHarness(
              message: buildMessage(
                id: 'gift-1',
                type: AppMessageType.gift,
                content: '暴力シーンだね',
              ),
              themeColors: themeColors,
              fontSize: 14,
              emphasizeGiftNicoadComment: true,
              ngMatcher: buildPresetMatcher(),
            ),
          ),
        );

        // Both icons are rendered.
        expect(rowContainsIcon(tester, Icons.volume_off), isTrue);
        expect(rowContainsIcon(tester, Icons.card_giftcard), isTrue);

        // Order check: in the outer RichText of the matched row, both icon
        // WidgetSpans live at the row head. The read-skipped badge must
        // appear before the gift icon in the inline-span traversal.
        final List<IconData> iconsInOrder = <IconData>[];
        for (final RichText rt in tester.widgetList<RichText>(
          find.byType(RichText),
        )) {
          rt.text.visitChildren((InlineSpan span) {
            if (span is WidgetSpan) {
              Widget unwrapped = span.child;
              if (unwrapped is ExcludeSemantics) {
                unwrapped = unwrapped.child!;
              }
              if (unwrapped is Icon) {
                final IconData? d = unwrapped.icon;
                if (d == Icons.volume_off || d == Icons.card_giftcard) {
                  iconsInOrder.add(d!);
                }
              }
            }
            return true;
          });
        }
        final int skipIdx = iconsInOrder.indexOf(Icons.volume_off);
        final int giftIdx = iconsInOrder.indexOf(Icons.card_giftcard);
        expect(skipIdx, greaterThanOrEqualTo(0));
        expect(giftIdx, greaterThan(skipIdx));
      },
    );

    testWidgets('operator color is preserved when row is dimmed', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          CommentRowHarness(
            message: buildMessage(
              id: 'op-1',
              type: AppMessageType.operator,
              content: '暴力シーンだね',
            ),
            themeColors: themeColors,
            fontSize: 14,
            ngMatcher: buildPresetMatcher(),
          ),
        ),
      );

      // The body text uses the operator color. Opacity wraps only the
      // content visually; the color channel itself is preserved on the
      // span style. Walk every RichText in the row (the outer meta +
      // the inner Opacity-wrapped body) and assert the operator color
      // appears unchanged somewhere in the span tree.
      final Set<Color> observedColors = <Color>{};
      for (final RichText rt in tester.widgetList<RichText>(
        find.byType(RichText),
      )) {
        rt.text.visitChildren((InlineSpan span) {
          if (span is TextSpan) {
            final Color? c = span.style?.color;
            if (c != null) {
              observedColors.add(c);
            }
          }
          return true;
        });
      }
      expect(observedColors, contains(themeColors.operatorTextColor));
    });
  });

  group('_PinnedCommentRow read-skipped badge', () {
    testWidgets('shows volume_off badge for preset match', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          PinnedCommentRowHarness(
            message: buildMessage(content: '暴力シーンだね'),
            themeColors: themeColors,
            fontSize: 14,
            onUnpin: () {},
            ngMatcher: buildPresetMatcher(),
          ),
        ),
      );

      expect(rowContainsIcon(tester, Icons.volume_off), isTrue);
      expect(readSkippedOpacityCount(tester), greaterThan(0));
    });

    testWidgets('user NG match renders no badge / no opacity', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          PinnedCommentRowHarness(
            message: buildMessage(content: '個人攻撃のコメント'),
            themeColors: themeColors,
            fontSize: 14,
            onUnpin: () {},
            ngMatcher: buildUserMatcher(word: '個人攻撃'),
          ),
        ),
      );

      expect(rowContainsIcon(tester, Icons.volume_off), isFalse);
      expect(readSkippedOpacityCount(tester), 0);
    });

    testWidgets('non-matching pinned row renders no badge / no opacity', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          PinnedCommentRowHarness(
            message: buildMessage(content: '普通のコメント'),
            themeColors: themeColors,
            fontSize: 14,
            onUnpin: () {},
            ngMatcher: buildPresetMatcher(),
          ),
        ),
      );

      expect(rowContainsIcon(tester, Icons.volume_off), isFalse);
      expect(readSkippedOpacityCount(tester), 0);
    });

    testWidgets('two-line pinned renders badge and Opacity-wrapped body', (
      WidgetTester tester,
    ) async {
      // Mirror of the inline 2-line assertion: pinned rows share the same
      // "badge is body-sized, not meta-sized" contract.
      const double baselineFontSize = 14.0;
      await tester.pumpWidget(
        wrap(
          PinnedCommentRowHarness(
            message: buildMessage(content: '暴力シーンだね'),
            themeColors: themeColors,
            fontSize: baselineFontSize,
            commentTwoLineEnabled: true,
            onUnpin: () {},
            ngMatcher: buildPresetMatcher(),
          ),
        ),
      );

      expect(rowContainsIcon(tester, Icons.volume_off), isTrue);
      expect(readSkippedOpacityCount(tester), greaterThan(0));
      final Icon badge = tester
          .widgetList<Icon>(find.byType(Icon))
          .firstWhere((Icon i) => i.icon == Icons.volume_off);
      expect(badge.size, closeTo(baselineFontSize * 0.95, 0.01));
    });

    testWidgets(
      'semantics label differs from non-pinned by mentioning 「ピン留め」',
      (WidgetTester tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            wrap(
              PinnedCommentRowHarness(
                message: buildMessage(content: '暴力シーンだね'),
                themeColors: themeColors,
                fontSize: 14,
                onUnpin: () {},
                ngMatcher: buildPresetMatcher(),
              ),
            ),
          );

          expect(
            find.bySemanticsLabel(RegExp('^読み上げ対象外のコメント（ピン留め）。暴力表現を含みます')),
            findsOneWidget,
          );
          // The inline variant must not appear: match "読み上げ対象外のコメント"
          // that is NOT followed by "（ピン留め）".
          expect(
            find.bySemanticsLabel(RegExp('^読み上げ対象外のコメント(?!（ピン留め）)')),
            findsNothing,
          );
        } finally {
          handle.dispose();
        }
      },
    );
  });

  group('_CommentRow read-skipped edge cases', () {
    testWidgets('star-prefix-hidden row suppresses badge and opacity', (
      WidgetTester tester,
    ) async {
      // A matched comment starting with "☆" is normally hidden behind a
      // spoiler placeholder. Even though the matcher would flag it, the
      // badge must stay OFF — rendering it would leak the presence of a
      // matched body before the user chose to reveal it (#616 security
      // rationale). Regression guard for that rule.
      await tester.pumpWidget(
        wrap(
          CommentRowHarness(
            message: buildMessage(content: '☆暴力シーンだね'),
            themeColors: themeColors,
            fontSize: 14,
            starPrefixHidingEnabled: true,
            ngMatcher: buildPresetMatcher(),
          ),
        ),
      );

      expect(rowContainsIcon(tester, Icons.volume_off), isFalse);
      expect(readSkippedOpacityCount(tester), 0);
    });

    testWidgets('badge scales with textScaler', (WidgetTester tester) async {
      // Below the clamp cap so the scaling math (not the clamp) drives
      // the assertion: expected = fontSize * 0.95 * scaler.
      const double baselineFontSize = 14.0;
      const double scalerFactor = 2.0;
      const double expectedSize = baselineFontSize * 0.95 * scalerFactor;
      await tester.pumpWidget(
        wrap(
          CommentRowHarness(
            message: buildMessage(content: '暴力シーンだね'),
            themeColors: themeColors,
            fontSize: baselineFontSize,
            textScaler: const TextScaler.linear(scalerFactor),
            ngMatcher: buildPresetMatcher(),
          ),
        ),
      );

      final Icon scaledIcon = tester
          .widgetList<Icon>(find.byType(Icon))
          .firstWhere((Icon i) => i.icon == Icons.volume_off);
      expect(scaledIcon.size, closeTo(expectedSize, 0.01));
    });

    testWidgets('cache invalidates when ngMatcher instance changes', (
      WidgetTester tester,
    ) async {
      final AppMessage message = buildMessage(content: '暴力シーンだね');
      final NgMatcher matcherA = buildPresetMatcher();
      // A matcher that does NOT match the same content: no preset words.
      final NgMatcher matcherB = NgMatcher(
        presetCategories: const <NgPresetCategory>[],
        userNgWords: const <String>[],
        normalizer: (String s) => s,
      );

      await tester.pumpWidget(
        wrap(
          CommentRowHarness(
            message: message,
            themeColors: themeColors,
            fontSize: 14,
            ngMatcher: matcherA,
          ),
        ),
      );
      expect(rowContainsIcon(tester, Icons.volume_off), isTrue);

      // Swap the matcher instance. The row should re-evaluate and drop
      // the badge — otherwise a stale cache would pin the old verdict.
      await tester.pumpWidget(
        wrap(
          CommentRowHarness(
            message: message,
            themeColors: themeColors,
            fontSize: 14,
            ngMatcher: matcherB,
          ),
        ),
      );
      expect(rowContainsIcon(tester, Icons.volume_off), isFalse);
      expect(readSkippedOpacityCount(tester), 0);
    });
  });
}
