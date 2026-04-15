import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/theme/app_theme.dart';

/// Minimum WCAG 2.1 contrast ratio for normal body text (AA).
const double _kWcagAaNormalText = 4.5;

/// Computes the WCAG 2.1 relative luminance for [color].
///
/// Uses the sRGB linearization described in
/// https://www.w3.org/TR/WCAG21/#dfn-relative-luminance.
double _relativeLuminance(Color color) {
  double channel(int component) {
    final double srgb = component / 255.0;
    if (srgb <= 0.03928) {
      return srgb / 12.92;
    }
    return math.pow((srgb + 0.055) / 1.055, 2.4).toDouble();
  }

  // `Color.red/green/blue` are deprecated; use the ARGB32 representation and
  // extract channels by bit shift for forward compatibility with wide-gamut
  // colors.
  final int argb = color.toARGB32();
  final int r = (argb >> 16) & 0xFF;
  final int g = (argb >> 8) & 0xFF;
  final int b = argb & 0xFF;
  final double rLin = channel(r);
  final double gLin = channel(g);
  final double bLin = channel(b);
  return 0.2126 * rLin + 0.7152 * gLin + 0.0722 * bLin;
}

/// Computes the WCAG 2.1 contrast ratio between [foreground] and [background].
double _contrastRatio(Color foreground, Color background) {
  final double fg = _relativeLuminance(foreground);
  final double bg = _relativeLuminance(background);
  final double lighter = math.max(fg, bg);
  final double darker = math.min(fg, bg);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  /// Concrete (non-system) modes used for the contrast check.
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
          final double ratio = _contrastRatio(chatTextColor, bg);
          expect(
            ratio,
            greaterThanOrEqualTo(_kWcagAaNormalText),
            reason:
                '${mode.name} gift background has contrast $ratio '
                '(< $_kWcagAaNormalText) against onSurface $chatTextColor',
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
          final double ratio = _contrastRatio(chatTextColor, bg);
          expect(
            ratio,
            greaterThanOrEqualTo(_kWcagAaNormalText),
            reason:
                '${mode.name} nicoad background has contrast $ratio '
                '(< $_kWcagAaNormalText) against onSurface $chatTextColor',
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
}
