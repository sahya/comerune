import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/theme/app_theme.dart';

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
/// Relative-luminance formula: https://www.w3.org/TR/WCAG21/#contrast-minimum
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
        final double ratio = _contrastRatio(
          colors.operatorTextColor,
          colors.operatorMessageBackground,
        );
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
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

/// Returns the WCAG relative-luminance contrast ratio between two colors.
///
/// Formula from https://www.w3.org/TR/WCAG21/#dfn-contrast-ratio :
///   (L1 + 0.05) / (L2 + 0.05)
/// where L1 is the higher relative luminance.
double _contrastRatio(Color a, Color b) {
  final double la = _relativeLuminance(a);
  final double lb = _relativeLuminance(b);
  final double hi = math.max(la, lb);
  final double lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// WCAG 2.1 relative luminance for an sRGB color.
/// See https://www.w3.org/TR/WCAG21/#dfn-relative-luminance .
double _relativeLuminance(Color c) {
  final double r = _channelLinear(c.r);
  final double g = _channelLinear(c.g);
  final double b = _channelLinear(c.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// Converts a gamma-encoded sRGB channel (already normalised to [0, 1]
/// by Flutter's `Color.r/g/b`) to linear light per the WCAG formula.
double _channelLinear(double srgb) {
  if (srgb <= 0.03928) {
    return srgb / 12.92;
  }
  return math.pow((srgb + 0.055) / 1.055, 2.4).toDouble();
}
