import 'package:flutter/material.dart';

import '../../domain/models/app_settings.dart';

/// Semantic colors that vary by theme, used across all screens.
class AppThemeColors {
  const AppThemeColors({
    required this.programTitleBarBackground,
    required this.broadcasterNameColor,
    required this.statusBarBackground,
    required this.statusConnected,
    required this.statusDisconnected,
    required this.operatorMessageBackground,
    required this.notificationMessageBackground,
    required this.subtleTextColor,
    required this.ngUserActiveColor,
    required this.sheetHandleColor,
  });

  final Color programTitleBarBackground;
  final Color broadcasterNameColor;
  final Color statusBarBackground;
  final Color statusConnected;
  final Color statusDisconnected;
  final Color operatorMessageBackground;
  final Color notificationMessageBackground;
  final Color subtleTextColor;
  final Color ngUserActiveColor;
  final Color sheetHandleColor;
}

class AppTheme {
  const AppTheme._();

  static const AppThemeColors _lightColors = AppThemeColors(
    programTitleBarBackground: Color(0xFFE8EAF6),
    broadcasterNameColor: Color(0xFF616161),
    statusBarBackground: Color(0xFFEEEEEE),
    statusConnected: Color(0xFF4CAF50),
    statusDisconnected: Color(0xFFF44336),
    operatorMessageBackground: Color(0xFFFFF9C4),
    notificationMessageBackground: Color(0xFFE1F5FE),
    subtleTextColor: Color(0xFF757575),
    ngUserActiveColor: Color(0xFFF44336),
    sheetHandleColor: Color(0xFFBDBDBD),
  );

  static const AppThemeColors _darkColors = AppThemeColors(
    programTitleBarBackground: Color(0xFF1A237E),
    broadcasterNameColor: Color(0xFFB0BEC5),
    statusBarBackground: Color(0xFF263238),
    statusConnected: Color(0xFF66BB6A),
    statusDisconnected: Color(0xFFEF5350),
    operatorMessageBackground: Color(0xFF5D4037),
    notificationMessageBackground: Color(0xFF1565C0),
    subtleTextColor: Color(0xFF90A4AE),
    ngUserActiveColor: Color(0xFFEF5350),
    sheetHandleColor: Color(0xFF546E7A),
  );

  /// P-type: avoids red-green confusion. Uses blue/orange contrast.
  static const AppThemeColors _protanopiaColors = AppThemeColors(
    programTitleBarBackground: Color(0xFFE3F2FD),
    broadcasterNameColor: Color(0xFF616161),
    statusBarBackground: Color(0xFFEEEEEE),
    statusConnected: Color(0xFF1565C0),
    statusDisconnected: Color(0xFFE65100),
    operatorMessageBackground: Color(0xFFFFF3E0),
    notificationMessageBackground: Color(0xFFE3F2FD),
    subtleTextColor: Color(0xFF757575),
    ngUserActiveColor: Color(0xFFE65100),
    sheetHandleColor: Color(0xFFBDBDBD),
  );

  /// D-type: avoids red-green confusion. Uses purple/amber contrast
  /// (shifted from P-type's blue/orange to aid users who lose green sensitivity).
  static const AppThemeColors _deuteranopiaColors = AppThemeColors(
    programTitleBarBackground: Color(0xFFEDE7F6),
    broadcasterNameColor: Color(0xFF616161),
    statusBarBackground: Color(0xFFEEEEEE),
    statusConnected: Color(0xFF4527A0),
    statusDisconnected: Color(0xFFBF360C),
    operatorMessageBackground: Color(0xFFFFF8E1),
    notificationMessageBackground: Color(0xFFEDE7F6),
    subtleTextColor: Color(0xFF757575),
    ngUserActiveColor: Color(0xFFBF360C),
    sheetHandleColor: Color(0xFFBDBDBD),
  );

  /// T-type: avoids blue-yellow confusion. Uses red/cyan contrast.
  static const AppThemeColors _tritanopiaColors = AppThemeColors(
    programTitleBarBackground: Color(0xFFE0F2F1),
    broadcasterNameColor: Color(0xFF616161),
    statusBarBackground: Color(0xFFEEEEEE),
    statusConnected: Color(0xFF00695C),
    statusDisconnected: Color(0xFFC62828),
    operatorMessageBackground: Color(0xFFFFEBEE),
    notificationMessageBackground: Color(0xFFE0F2F1),
    subtleTextColor: Color(0xFF757575),
    ngUserActiveColor: Color(0xFFC62828),
    sheetHandleColor: Color(0xFFBDBDBD),
  );

  static AppThemeColors colorsFor(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return _lightColors;
      case AppThemeMode.dark:
        return _darkColors;
      case AppThemeMode.protanopia:
        return _protanopiaColors;
      case AppThemeMode.deuteranopia:
        return _deuteranopiaColors;
      case AppThemeMode.tritanopia:
        return _tritanopiaColors;
    }
  }

  static ThemeData themeDataFor(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return _lightTheme;
      case AppThemeMode.dark:
        return _darkTheme;
      case AppThemeMode.protanopia:
        return _protanopiaTheme;
      case AppThemeMode.deuteranopia:
        return _deuteranopiaTheme;
      case AppThemeMode.tritanopia:
        return _tritanopiaTheme;
    }
  }

  static final ThemeData _lightTheme = ThemeData(
    brightness: Brightness.light,
    colorSchemeSeed: Colors.indigo,
    useMaterial3: true,
  );

  static final ThemeData _darkTheme = ThemeData(
    brightness: Brightness.dark,
    colorSchemeSeed: Colors.indigo,
    useMaterial3: true,
  );

  static final ThemeData _protanopiaTheme = ThemeData(
    brightness: Brightness.light,
    colorSchemeSeed: Colors.blue,
    useMaterial3: true,
  );

  static final ThemeData _deuteranopiaTheme = ThemeData(
    brightness: Brightness.light,
    colorSchemeSeed: Colors.deepPurple,
    useMaterial3: true,
  );

  static final ThemeData _tritanopiaTheme = ThemeData(
    brightness: Brightness.light,
    colorSchemeSeed: Colors.teal,
    useMaterial3: true,
  );
}
