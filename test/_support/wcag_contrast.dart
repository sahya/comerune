import 'dart:math' as math;
import 'dart:ui';

/// Minimum WCAG 2.1 contrast ratio for normal body text (AA).
///
/// See https://www.w3.org/TR/WCAG21/#contrast-minimum.
const double kWcagAaNormalText = 4.5;

/// Returns the WCAG 2.1 contrast ratio between [foreground] and [background].
///
/// The ratio is symmetric: the lighter of the two relative luminances always
/// goes on top, so callers do not need to pre-sort the inputs.
///
/// Formula: `(L1 + 0.05) / (L2 + 0.05)` where `L1 >= L2`. See
/// https://www.w3.org/TR/WCAG21/#dfn-contrast-ratio.
double wcagContrastRatio(Color foreground, Color background) {
  final double fg = _relativeLuminance(foreground);
  final double bg = _relativeLuminance(background);
  final double lighter = math.max(fg, bg);
  final double darker = math.min(fg, bg);
  return (lighter + 0.05) / (darker + 0.05);
}

/// Computes the WCAG 2.1 relative luminance for [color].
///
/// Uses the sRGB linearization described in
/// https://www.w3.org/TR/WCAG21/#dfn-relative-luminance.
///
/// Note on color space: `toARGB32()` quantizes wide-gamut colors down to
/// 8-bit sRGB. All app theme colors are declared as `Color(0xFF...)`
/// literals (sRGB), so this is lossless for the current palette. If a
/// future theme adds DisplayP3 colors, switch to the `Color.r/g/b` double
/// API and feed those values directly into the linearization.
double _relativeLuminance(Color color) {
  final int argb = color.toARGB32();
  final int r = (argb >> 16) & 0xFF;
  final int g = (argb >> 8) & 0xFF;
  final int b = argb & 0xFF;
  return 0.2126 * _channelLinear(r) +
      0.7152 * _channelLinear(g) +
      0.0722 * _channelLinear(b);
}

/// Converts a gamma-encoded sRGB channel (0-255) to linear light per WCAG.
double _channelLinear(int component) {
  final double srgb = component / 255.0;
  if (srgb <= 0.03928) {
    return srgb / 12.92;
  }
  return math.pow((srgb + 0.055) / 1.055, 2.4).toDouble();
}
