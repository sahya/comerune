import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/theme/app_theme.dart';

void main() {
  /// Concrete (non-system) modes used for distinctness checks.
  const List<AppThemeMode> concreteModes = <AppThemeMode>[
    AppThemeMode.light,
    AppThemeMode.dark,
    AppThemeMode.protanopia,
    AppThemeMode.deuteranopia,
    AppThemeMode.tritanopia,
  ];

  group('AppTheme.themeDataFor', () {
    test('dark mode returns Brightness.dark', () {
      final ThemeData dark = AppTheme.themeDataFor(AppThemeMode.dark);
      expect(dark.brightness, Brightness.dark);
    });

    test('all non-dark modes return Brightness.light', () {
      const List<AppThemeMode> lightModes = <AppThemeMode>[
        AppThemeMode.system,
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
    test('returns distinct statusConnected color for every concrete mode', () {
      final Map<Color, AppThemeMode> seen = <Color, AppThemeMode>{};
      for (final AppThemeMode mode in concreteModes) {
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

    test('returns distinct statusDisconnected color for every concrete mode',
        () {
      final Map<Color, AppThemeMode> seen = <Color, AppThemeMode>{};
      for (final AppThemeMode mode in concreteModes) {
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

    test('system mode falls back to light colors', () {
      expect(
        AppTheme.colorsFor(AppThemeMode.system).statusConnected,
        AppTheme.colorsFor(AppThemeMode.light).statusConnected,
      );
    });

    test('returns non-null AppThemeColors for every mode', () {
      for (final AppThemeMode mode in AppThemeMode.values) {
        expect(AppTheme.colorsFor(mode), isNotNull);
      }
    });
  });

  group('AppTheme.resolveEffectiveMode', () {
    test('resolves system mode to light for Brightness.light', () {
      expect(
        AppTheme.resolveEffectiveMode(AppThemeMode.system, Brightness.light),
        AppThemeMode.light,
      );
    });

    test('resolves system mode to dark for Brightness.dark', () {
      expect(
        AppTheme.resolveEffectiveMode(AppThemeMode.system, Brightness.dark),
        AppThemeMode.dark,
      );
    });

    test('returns non-system modes unchanged', () {
      for (final AppThemeMode mode in concreteModes) {
        expect(
          AppTheme.resolveEffectiveMode(mode, Brightness.dark),
          mode,
        );
      }
    });
  });
}
