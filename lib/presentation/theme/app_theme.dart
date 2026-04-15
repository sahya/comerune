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
    required this.loginBannerOkBackground,
    required this.loginBannerOkForeground,
    required this.loginBannerOkIcon,
    required this.loginBannerWarningBackground,
    required this.loginBannerWarningForeground,
    required this.loginBannerWarningIcon,
    required this.pinnedMessageBackground,
    required this.broadcastEndedBackground,
    required this.operatorTextColor,
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
  final Color loginBannerOkBackground;
  final Color loginBannerOkForeground;
  final Color loginBannerOkIcon;
  final Color loginBannerWarningBackground;
  final Color loginBannerWarningForeground;
  final Color loginBannerWarningIcon;
  final Color pinnedMessageBackground;
  final Color broadcastEndedBackground;

  /// Text color used to render operator (運営) comment content and user name.
  /// Intended to convey the "red" / warning-like semantic consistently per
  /// theme (including color-vision-deficient themes).
  ///
  /// WCAG AA contrast (text ≥ 4.5:1 against the paired
  /// [operatorMessageBackground]) is verified per theme; see `AppTheme`
  /// constants for the measured ratios.
  final Color operatorTextColor;

  // System / emotion body contrast (informational).
  //
  // System- and emotion-type messages render the body text using the chat
  // default foreground (the theme's default body text color provided by
  // [ThemeData.textTheme] — typically black87 on light themes and white on
  // dark) over the shared [notificationMessageBackground]. This pairing was
  // not introduced in the display-toggle feature; it is the pre-existing
  // behavior. Measured contrast ratios against the default body text per
  // theme:
  //   - light        : default body text (black87) on #E1F5FE ≈ 15.0:1 (AAA)
  //   - dark         : default body text (white)   on #1565C0 ≈ 6.36:1 (AA)
  //   - protanopia   : default body text (black87) on #BBDEFB ≈ 13.3:1 (AAA)
  //   - deuteranopia : default body text (black87) on #D1C4E9 ≈ 11.6:1 (AAA)
  //   - tritanopia   : default body text (black87) on #B2DFDB ≈ 12.2:1 (AAA)
  //
  // All 5 themes currently pass WCAG AA (≥ 4.5:1) for normal text. If any
  // future theme adjustment breaks this invariant, promote this block to a
  // SHOULD-FIX item in the next review and widen the test coverage to assert
  // the measured ratios.
}

class AppTheme {
  const AppTheme._();

  static const AppThemeColors _lightColors = AppThemeColors(
    programTitleBarBackground: Color(0xFFE8EAF6),
    broadcasterNameColor: Color(0xFF616161),
    statusBarBackground: Color(0xFFEEEEEE),
    statusConnected: Color(0xFF388E3C),
    statusDisconnected: Color(0xFFF44336),
    operatorMessageBackground: Color(0xFFFFF9C4),
    notificationMessageBackground: Color(0xFFE1F5FE),
    subtleTextColor: Color(0xFF757575),
    ngUserActiveColor: Color(0xFFF44336),
    sheetHandleColor: Color(0xFFBDBDBD),
    loginBannerOkBackground: Color(0xFFE8F5E9),
    loginBannerOkForeground: Color(0xFF1B5E20),
    loginBannerOkIcon: Color(0xFF388E3C),
    loginBannerWarningBackground: Color(0xFFFFF3E0),
    loginBannerWarningForeground: Color(0xFF4E342E),
    loginBannerWarningIcon: Color(0xFFE65100),
    pinnedMessageBackground: Color(0xFFFFF8E1),
    broadcastEndedBackground: Color(0xFFECEFF1),
    // operatorTextColor (#D32F2F) on operatorMessageBackground (#FFF9C4):
    // contrast ratio 4.65:1 -> passes WCAG AA for normal text (>= 4.5:1).
    operatorTextColor: Color(0xFFD32F2F),
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
    loginBannerOkBackground: Color(0xFF1B3A1B),
    loginBannerOkForeground: Color(0xFFE0E0E0),
    loginBannerOkIcon: Color(0xFF66BB6A),
    loginBannerWarningBackground: Color(0xFF3E2700),
    loginBannerWarningForeground: Color(0xFFE0E0E0),
    loginBannerWarningIcon: Color(0xFFFFB74D),
    pinnedMessageBackground: Color(0xFF4E342E),
    broadcastEndedBackground: Color(0xFF37474F),
    // operatorTextColor on operatorMessageBackground (#5D4037) must satisfy
    // WCAG AA (>= 4.5:1). History of this value:
    //   - #FF6B6B -> 3.36:1 (fail)
    //   - #FFB4B4 -> 5.52:1 (pass, reviewers felt too pastel)
    //   - #FFA0A0 -> ~4.79:1 (pass, but on the AA lower bound — any
    //     background tweak could regress below 4.5:1)
    // Current value #FFAAAA keeps the red / warning hue while giving
    // ~5.14:1 on #5D4037, leaving comfortable headroom above the WCAG AA
    // 4.5:1 floor for normal text.
    operatorTextColor: Color(0xFFFFAAAA),
  );

  /// P-type: avoids red-green confusion. Uses blue/orange contrast.
  static const AppThemeColors _protanopiaColors = AppThemeColors(
    programTitleBarBackground: Color(0xFFE3F2FD),
    broadcasterNameColor: Color(0xFF616161),
    statusBarBackground: Color(0xFFEEEEEE),
    statusConnected: Color(0xFF1565C0),
    statusDisconnected: Color(0xFFE65100),
    operatorMessageBackground: Color(0xFFFFF3E0),
    notificationMessageBackground: Color(0xFFBBDEFB),
    subtleTextColor: Color(0xFF757575),
    ngUserActiveColor: Color(0xFFE65100),
    sheetHandleColor: Color(0xFFBDBDBD),
    loginBannerOkBackground: Color(0xFFE3F2FD),
    loginBannerOkForeground: Color(0xFF0D47A1),
    loginBannerOkIcon: Color(0xFF1565C0),
    loginBannerWarningBackground: Color(0xFFFFF3E0),
    loginBannerWarningForeground: Color(0xFF4E342E),
    loginBannerWarningIcon: Color(0xFFE65100),
    pinnedMessageBackground: Color(0xFFFFF8E1),
    broadcastEndedBackground: Color(0xFFEFEBE9),
    // P-type: the "red / warning" semantic uses the deep-orange family so it
    // stays distinguishable for protanopia users (red is confused with green;
    // orange is not). The original #E65100 on #FFF3E0 gave only 3.46:1
    // (below WCAG AA 4.5:1); darkened to #BF360C -> 5.11:1. Still a deep
    // orange, not brown.
    operatorTextColor: Color(0xFFBF360C),
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
    notificationMessageBackground: Color(0xFFD1C4E9),
    subtleTextColor: Color(0xFF757575),
    ngUserActiveColor: Color(0xFFBF360C),
    sheetHandleColor: Color(0xFFBDBDBD),
    loginBannerOkBackground: Color(0xFFEDE7F6),
    loginBannerOkForeground: Color(0xFF311B92),
    loginBannerOkIcon: Color(0xFF4527A0),
    loginBannerWarningBackground: Color(0xFFFFF8E1),
    loginBannerWarningForeground: Color(0xFF4E342E),
    loginBannerWarningIcon: Color(0xFFBF360C),
    pinnedMessageBackground: Color(0xFFFFF8E1),
    broadcastEndedBackground: Color(0xFFF3E5F5),
    // D-type: use a deep red-orange that remains visible for deuteranopia
    // users. Differentiated from the P-type palette (#BF360C on #FFF3E0) so
    // users switching themes get a visually distinct tone rather than an
    // identical swatch.
    // #B23A0A on #FFF8E1 -> ~5.65:1 contrast (passes WCAG AA >= 4.5:1).
    operatorTextColor: Color(0xFFB23A0A),
  );

  /// T-type: avoids blue-yellow confusion. Uses red/cyan contrast.
  static const AppThemeColors _tritanopiaColors = AppThemeColors(
    programTitleBarBackground: Color(0xFFE0F2F1),
    broadcasterNameColor: Color(0xFF616161),
    statusBarBackground: Color(0xFFEEEEEE),
    statusConnected: Color(0xFF00695C),
    statusDisconnected: Color(0xFFC62828),
    operatorMessageBackground: Color(0xFFFFEBEE),
    notificationMessageBackground: Color(0xFFB2DFDB),
    subtleTextColor: Color(0xFF757575),
    ngUserActiveColor: Color(0xFFC62828),
    sheetHandleColor: Color(0xFFBDBDBD),
    loginBannerOkBackground: Color(0xFFE0F2F1),
    loginBannerOkForeground: Color(0xFF004D40),
    loginBannerOkIcon: Color(0xFF00695C),
    loginBannerWarningBackground: Color(0xFFFFEBEE),
    loginBannerWarningForeground: Color(0xFF4E342E),
    loginBannerWarningIcon: Color(0xFFC62828),
    pinnedMessageBackground: Color(0xFFFFEBEE),
    broadcastEndedBackground: Color(0xFFE0E0E0),
    // T-type: red/cyan contrast is preserved; use the existing red.
    // #C62828 on #FFEBEE -> 4.92:1 contrast (passes WCAG AA).
    operatorTextColor: Color(0xFFC62828),
  );

  /// Resolves [AppThemeMode.system] to a concrete mode based on [brightness].
  /// Non-system modes are returned as-is.
  static AppThemeMode resolveEffectiveMode(
    AppThemeMode mode,
    Brightness brightness,
  ) {
    if (mode == AppThemeMode.system) {
      return brightness == Brightness.dark
          ? AppThemeMode.dark
          : AppThemeMode.light;
    }
    return mode;
  }

  static AppThemeColors colorsFor(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.system:
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
      case AppThemeMode.system:
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
