import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/theme/app_theme.dart';

import '../../_support/wcag_contrast.dart';

/// Machine-verifies that the chat default foreground stays above the WCAG
/// 2.1 AA contrast floor (4.5:1 for normal text) on top of
/// `notificationMessageBackground` in every concrete theme.
///
/// Background: `system` and `emotion` messages reuse
/// `notificationMessageBackground` for their row background, but their body
/// text uses the theme's default chat foreground (no dedicated
/// `*TextColor` field). The 5-theme contrast was previously documented only
/// as a doc comment next to the color literal in
/// `lib/presentation/theme/app_theme.dart`; that comment can drift from
/// reality when the palette is tweaked. These tests compute the ratio from
/// the actual `Color` values so a regression fails CI instead of silently
/// shipping. (Issue #459)
///
/// The chat default foreground is approximated by `colorScheme.onSurface`,
/// matching `gift_nicoad_contrast_test.dart`. `Material 3 ThemeData` derives
/// `textTheme.bodyMedium.color` from `onSurface`, so this is the same color
/// the renderer falls back to when the per-user color is null (which is the
/// normal case for system / emotion messages).
///
/// Scope:
///   * normal-text floor (4.5:1) only; sub-meta spans (timestamp / id) are
///     not covered here.
///   * `system` resolves to `light` so we exclude it from direct checks to
///     avoid double-counting the same pair.
///
/// Acceptance criteria coverage:
///   * 5 themes verified
///   * shares WCAG calculation with `operator_contrast_test.dart` via
///     `test/_support/wcag_contrast.dart`
///   * future palette tweaks that drop below 4.5:1 fail CI
void main() {
  /// Concrete (non-system) modes used for the contrast check.
  const List<AppThemeMode> concreteModes = <AppThemeMode>[
    AppThemeMode.light,
    AppThemeMode.dark,
    AppThemeMode.protanopia,
    AppThemeMode.deuteranopia,
    AppThemeMode.tritanopia,
  ];

  group('notification background WCAG AA contrast', () {
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
}
