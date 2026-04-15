import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/theme/app_theme.dart';

import '../../_support/wcag_contrast.dart';

/// Machine-verifies that every app theme pairs `operatorTextColor` with
/// `operatorMessageBackground` above the WCAG 2.1 AA contrast floor for
/// normal text (4.5:1).
///
/// Scope: this test evaluates the operator **body** font (configurable via
/// `commentFontSize`, typically 14-24px) which qualifies as "normal text" per
/// WCAG and therefore uses the 4.5:1 floor. Sub-meta spans (timestamp / id at
/// ~9-12px) are not covered here; if those are ever rendered with
/// `operatorTextColor` in the future, they would fall under "small text" and
/// require AAA-level 7:1 verification separately.
///
/// Operator (運営) messages render the body and displayName label using
/// `operatorTextColor` on top of `operatorMessageBackground`. Each theme
/// currently documents its measured contrast ratio in a comment next to
/// the color literal; that comment can drift from reality when the
/// palette is tweaked. These tests compute the ratio from the actual
/// `Color` values so a regression fails CI instead of silently shipping.
///
/// The WCAG calculation is shared with `notification_contrast_test.dart` and
/// `gift_nicoad_contrast_test.dart` via `test/_support/wcag_contrast.dart`
/// to avoid drift between three independent implementations.
void main() {
  group('operator message WCAG AA contrast', () {
    // Every defined theme mode must be covered; `system` resolves to
    // `light` so we exclude it from direct checks to avoid double-counting
    // the same pair.
    const List<AppThemeMode> themes = <AppThemeMode>[
      AppThemeMode.light,
      AppThemeMode.dark,
      AppThemeMode.protanopia,
      AppThemeMode.deuteranopia,
      AppThemeMode.tritanopia,
    ];

    for (final AppThemeMode mode in themes) {
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
