import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/theme/app_theme.dart';

void main() {
  group('AppTheme.themeDataFor', () {
    test('dark mode returns Brightness.dark', () {
      final ThemeData dark = AppTheme.themeDataFor(AppThemeMode.dark);
      expect(dark.brightness, Brightness.dark);
    });

    test('all non-dark modes return Brightness.light', () {
      const List<AppThemeMode> lightModes = <AppThemeMode>[
        AppThemeMode.light,
        AppThemeMode.protanopia,
        AppThemeMode.deuteranopia,
        AppThemeMode.tritanopia,
      ];
      for (final AppThemeMode mode in lightModes) {
        expect(
          AppTheme.themeDataFor(mode).brightness,
          Brightness.light,
          reason: '${mode.name} should have Brightness.light',
        );
      }
    });

    test('returns non-null ThemeData for every mode', () {
      for (final AppThemeMode mode in AppThemeMode.values) {
        expect(AppTheme.themeDataFor(mode), isNotNull);
      }
    });
  });

  group('AppTheme.colorsFor', () {
    test('returns distinct statusConnected color for every mode', () {
      final Map<Color, AppThemeMode> seen = <Color, AppThemeMode>{};
      for (final AppThemeMode mode in AppThemeMode.values) {
        final Color color = AppTheme.colorsFor(mode).statusConnected;
        expect(
          seen.containsKey(color),
          isFalse,
          reason:
              '${mode.name} has same statusConnected as ${seen[color]?.name}',
        );
        seen[color] = mode;
      }
    });

    test('returns distinct statusDisconnected color for every mode', () {
      final Map<Color, AppThemeMode> seen = <Color, AppThemeMode>{};
      for (final AppThemeMode mode in AppThemeMode.values) {
        final Color color = AppTheme.colorsFor(mode).statusDisconnected;
        expect(
          seen.containsKey(color),
          isFalse,
          reason:
              '${mode.name} has same statusDisconnected as ${seen[color]?.name}',
        );
        seen[color] = mode;
      }
    });

    test('returns non-null AppThemeColors for every mode', () {
      for (final AppThemeMode mode in AppThemeMode.values) {
        expect(AppTheme.colorsFor(mode), isNotNull);
      }
    });
  });
}
