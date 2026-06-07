import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/theme/app_theme.dart';

import '../../_support/wcag_contrast.dart';

/// Machine-verifies that every theme pairs message backgrounds with their
/// rendered foreground color above the WCAG 2.1 AA floor for normal text
/// (4.5:1). Each `group` covers one message category. The shared list of
/// concrete (non-`system`) themes prevents drift between subsections.
///
/// Background: each theme historically documented its measured contrast
/// ratio in a comment next to the color literal; that comment can drift
/// from reality when the palette is tweaked. These tests compute the ratio
/// from the actual `Color` values so a regression fails CI instead of
/// silently shipping. (Issue #459)
///
/// Scope: normal-text floor (4.5:1) only; sub-meta spans (timestamp / id)
/// are not covered here. The WCAG calculation lives in
/// `test/_support/wcag_contrast.dart`.
void main() {
  /// Concrete (non-`system`) modes. `system` resolves to `light` so we
  /// exclude it from direct checks to avoid double-counting the same pair.
  const List<AppThemeMode> concreteModes = <AppThemeMode>[
    AppThemeMode.light,
    AppThemeMode.dark,
    AppThemeMode.protanopia,
    AppThemeMode.deuteranopia,
    AppThemeMode.tritanopia,
  ];

  group('gift / nicoad background contrast', () {
    test(
      'chat text color meets WCAG AA (4.5:1) on gift background for every theme',
      () {
        for (final AppThemeMode mode in concreteModes) {
          final ThemeData theme = AppTheme.themeDataFor(mode);
          final Color chatTextColor = theme.colorScheme.onSurface;
          final Color bg = AppTheme.colorsFor(mode).giftMessageBackground;
          final double ratio = wcagContrastRatio(chatTextColor, bg);
          expect(
            ratio,
            greaterThanOrEqualTo(kWcagAaNormalText),
            reason:
                '${mode.name} gift background has contrast $ratio '
                '(< $kWcagAaNormalText) against onSurface $chatTextColor',
          );
        }
      },
    );

    test(
      'chat text color meets WCAG AA (4.5:1) on nicoad background for every theme',
      () {
        for (final AppThemeMode mode in concreteModes) {
          final ThemeData theme = AppTheme.themeDataFor(mode);
          final Color chatTextColor = theme.colorScheme.onSurface;
          final Color bg = AppTheme.colorsFor(mode).nicoadMessageBackground;
          final double ratio = wcagContrastRatio(chatTextColor, bg);
          expect(
            ratio,
            greaterThanOrEqualTo(kWcagAaNormalText),
            reason:
                '${mode.name} nicoad background has contrast $ratio '
                '(< $kWcagAaNormalText) against onSurface $chatTextColor',
          );
        }
      },
    );

    test('gift and nicoad backgrounds are distinct within each theme', () {
      for (final AppThemeMode mode in concreteModes) {
        final AppThemeColors colors = AppTheme.colorsFor(mode);
        expect(
          colors.giftMessageBackground,
          isNot(equals(colors.nicoadMessageBackground)),
          reason:
              '${mode.name} uses identical colors for gift and nicoad, '
              'which defeats the visual distinction.',
        );
      }
    });
  });

  group('notification background WCAG AA contrast', () {
    // `system` and `emotion` messages reuse `notificationMessageBackground`
    // for their row background, but their body text uses the theme's
    // default chat foreground (no dedicated `*TextColor` field). We
    // approximate that foreground by `colorScheme.onSurface` — Material 3
    // `ThemeData` derives `textTheme.bodyMedium.color` from `onSurface`,
    // so this is the same color the renderer falls back to when the
    // per-user color is null.
    for (final AppThemeMode mode in concreteModes) {
      test(
        '${mode.name}: chat default foreground on notificationMessageBackground '
        'meets WCAG AA (>= 4.5:1)',
        () {
          final ThemeData theme = AppTheme.themeDataFor(mode);
          final Color chatTextColor = theme.colorScheme.onSurface;
          final Color bg = AppTheme.colorsFor(
            mode,
          ).notificationMessageBackground;
          final double ratio = wcagContrastRatio(chatTextColor, bg);
          expect(
            ratio,
            greaterThanOrEqualTo(kWcagAaNormalText),
            reason:
                'theme ${mode.name}: chat default foreground $chatTextColor '
                'vs notificationMessageBackground $bg contrast is '
                '${ratio.toStringAsFixed(3)}:1 (must be >= 4.5:1 for WCAG AA '
                'normal text). system / emotion messages render their body '
                'with this pairing — pick a slightly darker / lighter '
                'background, or introduce a dedicated text color.',
          );
        },
      );
    }
  });

  group('auto-extend background WCAG AA contrast (Issue #876)', () {
    // Auto-extend success / failure messages render the body text with
    // the chat default foreground (no dedicated *TextColor) on
    // dedicated theme backgrounds. Same WCAG AA story as the
    // notification background group above — body font is "normal text"
    // by WCAG, so the 4.5:1 floor applies.
    for (final AppThemeMode mode in concreteModes) {
      test(
        '${mode.name}: chat default foreground on autoExtendSuccessBackground '
        'meets WCAG AA (>= 4.5:1)',
        () {
          final ThemeData theme = AppTheme.themeDataFor(mode);
          final Color chatTextColor = theme.colorScheme.onSurface;
          final Color bg = AppTheme.colorsFor(mode).autoExtendSuccessBackground;
          final double ratio = wcagContrastRatio(chatTextColor, bg);
          expect(
            ratio,
            greaterThanOrEqualTo(kWcagAaNormalText),
            reason:
                'theme ${mode.name}: chat default foreground $chatTextColor '
                'vs autoExtendSuccessBackground $bg contrast is '
                '${ratio.toStringAsFixed(3)}:1 (must be >= 4.5:1 for WCAG AA '
                'normal text). Pick a slightly darker / lighter background.',
          );
        },
      );

      test(
        '${mode.name}: chat default foreground on autoExtendFailureBackground '
        'meets WCAG AA (>= 4.5:1)',
        () {
          final ThemeData theme = AppTheme.themeDataFor(mode);
          final Color chatTextColor = theme.colorScheme.onSurface;
          final Color bg = AppTheme.colorsFor(mode).autoExtendFailureBackground;
          final double ratio = wcagContrastRatio(chatTextColor, bg);
          expect(
            ratio,
            greaterThanOrEqualTo(kWcagAaNormalText),
            reason:
                'theme ${mode.name}: chat default foreground $chatTextColor '
                'vs autoExtendFailureBackground $bg contrast is '
                '${ratio.toStringAsFixed(3)}:1 (must be >= 4.5:1 for WCAG AA '
                'normal text). Pick a slightly darker / lighter background.',
          );
        },
      );
    }
  });

  group('operator message WCAG AA contrast', () {
    // Operator (運営) messages render the body and displayName label using
    // `operatorTextColor` on top of `operatorMessageBackground`. Body font
    // is configurable via `commentFontSize` (typically 14-24px) which
    // qualifies as "normal text" per WCAG and therefore uses the 4.5:1
    // floor. Sub-meta spans (timestamp / id at ~9-12px) are not covered
    // here.
    for (final AppThemeMode mode in concreteModes) {
      test('${mode.name}: operatorTextColor on operatorMessageBackground '
          'meets WCAG AA (>= 4.5:1)', () {
        final AppThemeColors colors = AppTheme.colorsFor(mode);
        final double ratio = wcagContrastRatio(
          colors.operatorTextColor,
          colors.operatorMessageBackground,
        );
        expect(
          ratio,
          greaterThanOrEqualTo(kWcagAaNormalText),
          reason:
              'theme ${mode.name}: operatorTextColor vs '
              'operatorMessageBackground contrast is '
              '${ratio.toStringAsFixed(3)}:1 (must be >= 4.5:1 for WCAG AA '
              'normal text). If you just tweaked the palette, pick a '
              'slightly darker / lighter foreground.',
        );
      });
    }
  });
}
