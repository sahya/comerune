import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/theme/app_theme.dart';

import '../../_support/wcag_contrast.dart';

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
}
