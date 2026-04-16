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
    required this.giftMessageBackground,
    required this.nicoadMessageBackground,
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

  /// Shaded background used to emphasize gift messages.
  ///
  /// This color is only applied when the user's
  /// `emphasizeGiftNicoadComment` setting is ON — opting IN to emphasis is
  /// an explicit user intent, so the tint is noticeably stronger than the
  /// always-on operator / notification backgrounds. Still kept low enough
  /// in saturation that the normal chat text color meets WCAG AA (4.5:1)
  /// against it.
  final Color giftMessageBackground;

  /// Shaded background used to emphasize ニコニ広告 (nicoad) messages.
  ///
  /// Same user-intent story as [giftMessageBackground]: rendered only when
  /// the user turns emphasis ON. Uses a different hue from
  /// [giftMessageBackground] so the two emphasized message kinds stay
  /// visually distinguishable within each theme.
  final Color nicoadMessageBackground;
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

  // System / emotion body contrast.
  //
  // System- and emotion-type messages render the body text using the chat
  // default foreground over the shared [notificationMessageBackground]. The
  // chat default foreground comes from the theme's `colorScheme.onSurface`
  // (Material 3 wires this through `textTheme.bodyMedium.color`, which is
  // what `Text` inherits when no explicit color is supplied).
  //
  // WCAG AA (>= 4.5:1) is enforced by
  // `test/presentation/theme/notification_contrast_test.dart` so that any
  // future palette tweak that drops below the floor fails CI. The earlier
  // doc-only annotation here used black87 / pure white as the assumed
  // foreground, but Material 3 derives `onSurface` from the seed and
  // produces a tinted near-white in dark mode (~#E4E1E9 for indigo). That
  // assumption mismatch silently masked a near-failure in dark mode
  // (4.445:1 against the original #1565C0); see the comment on the dark
  // [notificationMessageBackground] literal for the post-fix ratios.
}

class AppTheme {
  const AppTheme._();

  // Comment-row backgrounds are intentionally kept close to the surface color
  // so that user (chat) comments are the visual "main character" and special
  // types (operator / system / emotion / gift / nicoad) recede. Each special
  // type still carries a faint hue whisper so reviewers can tell them apart:
  //
  //   warm      -> operator (運営・注意喚起)
  //   cool      -> notification / system / emotion
  //   green     -> gift
  //   magenta   -> nicoad (ニコニ広告)
  //
  // The hue-to-meaning mapping is preserved across all 5 themes. CVD palettes
  // swap to hue axes the user can actually distinguish (P: blue/orange, D:
  // purple/amber, T: red/cyan). Contrast vs `colorScheme.onSurface` is
  // enforced by `test/presentation/theme/*_contrast_test.dart`.
  static const AppThemeColors _lightColors = AppThemeColors(
    programTitleBarBackground: Color(0xFFE8EAF6),
    broadcasterNameColor: Color(0xFF616161),
    statusBarBackground: Color(0xFFEEEEEE),
    statusConnected: Color(0xFF388E3C),
    statusDisconnected: Color(0xFFF44336),
    // Barely-warm near-white; the red operatorTextColor carries the warning.
    operatorMessageBackground: Color(0xFFFFF4E0),
    // Near-neutral cool-gray; holds the "info" hue at very low saturation.
    notificationMessageBackground: Color(0xFFEEF2F6),
    // Gift / nicoad are shown only when the user turns emphasis ON (see
    // field docs), so a stronger-than-neutral tint is appropriate.
    giftMessageBackground: Color(0xFFE8F3E9),
    // Kept distinct from giftMessageBackground by hue, not luminance.
    nicoadMessageBackground: Color(0xFFF5E6EE),
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
    // WCAG AA (>= 4.5:1) vs operatorMessageBackground is enforced by
    // `test/presentation/theme/operator_contrast_test.dart`.
    operatorTextColor: Color(0xFFC62828),
  );

  static const AppThemeColors _darkColors = AppThemeColors(
    programTitleBarBackground: Color(0xFF1A237E),
    broadcasterNameColor: Color(0xFFB0BEC5),
    statusBarBackground: Color(0xFF263238),
    statusConnected: Color(0xFF66BB6A),
    statusDisconnected: Color(0xFFEF5350),
    // Dark warm-gray; the red operatorTextColor carries the warning semantic.
    operatorMessageBackground: Color(0xFF332B26),
    // Near-neutral dark gray with only a small cool nudge, so the system /
    // emotion row reads as "muted info" rather than a saturated blue label.
    // Contrast vs Material 3's tinted `onSurface` (~#E4E1E9 for the indigo
    // dark scheme) is enforced by
    // `test/presentation/theme/notification_contrast_test.dart`.
    notificationMessageBackground: Color(0xFF282A2E),
    // Gift / nicoad are shown only when the user turns emphasis ON (see
    // field docs), so the green / magenta tints run slightly stronger than
    // the always-on notification background.
    giftMessageBackground: Color(0xFF2A322A),
    nicoadMessageBackground: Color(0xFF332831),
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
    // WCAG AA (>= 4.5:1) vs operatorMessageBackground is enforced by
    // `test/presentation/theme/operator_contrast_test.dart`.
    operatorTextColor: Color(0xFFFF8A80),
  );

  /// P-type: avoids red-green confusion. Uses blue/orange contrast.
  static const AppThemeColors _protanopiaColors = AppThemeColors(
    programTitleBarBackground: Color(0xFFE3F2FD),
    broadcasterNameColor: Color(0xFF616161),
    statusBarBackground: Color(0xFFEEEEEE),
    statusConnected: Color(0xFF1565C0),
    statusDisconnected: Color(0xFFE65100),
    // Low-saturation palette on a cool/warm/neutral axis that protanopes can
    // distinguish. Contrast enforced by the theme contrast tests.
    operatorMessageBackground: Color(0xFFF5EEE4),
    notificationMessageBackground: Color(0xFFECEFF3),
    // Gift / nicoad use slightly stronger tints than notification because
    // they are only rendered when the user opts IN to emphasis.
    giftMessageBackground: Color(0xFFEDEFE8),
    nicoadMessageBackground: Color(0xFFEEEAF3),
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
    // P-type: the "red / warning" semantic uses the deep-orange family so
    // protanopia users still perceive it (red confuses with green; orange
    // does not). WCAG AA vs operatorMessageBackground is enforced by
    // `test/presentation/theme/operator_contrast_test.dart`.
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
    // Low-saturation palette. Warm cream for operator, lavender for
    // notification so the purple semantic survives for deuteranope users.
    operatorMessageBackground: Color(0xFFF6F0E2),
    notificationMessageBackground: Color(0xFFEDE9F1),
    // Gift / nicoad use slightly stronger tints than notification because
    // they are only rendered when the user opts IN to emphasis.
    giftMessageBackground: Color(0xFFECEFE8),
    nicoadMessageBackground: Color(0xFFEFEAF2),
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
    // D-type: deep red-orange that remains visible for deuteranopia users,
    // differentiated from the P-type palette so theme switching yields a
    // visually distinct tone. WCAG AA vs operatorMessageBackground is
    // enforced by `test/presentation/theme/operator_contrast_test.dart`.
    operatorTextColor: Color(0xFFB23A0A),
  );

  /// T-type: avoids blue-yellow confusion. Uses red/cyan contrast.
  static const AppThemeColors _tritanopiaColors = AppThemeColors(
    programTitleBarBackground: Color(0xFFE0F2F1),
    broadcasterNameColor: Color(0xFF616161),
    statusBarBackground: Color(0xFFEEEEEE),
    statusConnected: Color(0xFF00695C),
    statusDisconnected: Color(0xFFC62828),
    // Low-saturation palette on the red/cyan hue axis that tritanopes
    // distinguish well: warm-pink operator, teal-tinted notification.
    operatorMessageBackground: Color(0xFFF8ECEC),
    notificationMessageBackground: Color(0xFFE8EFEF),
    // Gift / nicoad use slightly stronger tints than notification because
    // they are only rendered when the user opts IN to emphasis.
    // For tritanopia specifically, gift picks a slightly cooler teal (away
    // from the green–yellow band tritanopes confuse) and nicoad picks a
    // warm pink, so gift ≠ nicoad remains readable on the red/cyan axis.
    giftMessageBackground: Color(0xFFE8F1EE),
    nicoadMessageBackground: Color(0xFFF3E8E8),
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
    // T-type: red/cyan contrast is preserved using the standard red. WCAG
    // AA vs operatorMessageBackground is enforced by
    // `test/presentation/theme/operator_contrast_test.dart`.
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
