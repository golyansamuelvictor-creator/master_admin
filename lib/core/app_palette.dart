import 'package:flutter/material.dart';

/// Dark mode for screens that were drawn with fixed colours.
///
/// Most screens paint white cards, pale tints and black/grey text directly.
/// In Light mode these helpers return the colour unchanged, so Light mode
/// looks exactly as designed. In Dark mode:
///   * bg()   turns white / pale backgrounds into dark surfaces of the same hue
///   * fg()   turns black / dark text and icons into light text of the same hue
///   * line() does the same as bg() for borders and dividers
/// Saturated brand colours (purple buttons, green badges ...) are left alone,
/// as are see-through tints, which already sit well on a dark surface.
class AppPalette {
  AppPalette._();

  /// Set from the app's theme mode in main.dart.
  static bool isDark = false;

  static final Map<int, Color> _bgCache = {};
  static final Map<int, Color> _fgCache = {};

  static Color? bg(Color? c) => (c == null || !isDark) ? c : _darkSurface(c);
  static Color? fg(Color? c) => (c == null || !isDark) ? c : _lightText(c);
  static Color line(Color c) => isDark ? _darkLine(c) : c;

  /// Non-null bg(), for gradient stops.
  static Color solid(Color c) => isDark ? _darkSurface(c) : c;

  static final Map<int, Color> _lineCache = {};

  // Pale borders become dark grey; dark borders (black table grid lines,
  // purple outlines) become light so they still show on a dark surface.
  static Color _darkLine(Color c) {
    return _lineCache.putIfAbsent(c.toARGB32(), () {
      final hsl = HSLColor.fromColor(c);
      if (hsl.lightness > 0.6) {
        return hsl.withLightness(0.12 + (1 - hsl.lightness) * 0.9).withSaturation(hsl.saturation * 0.55).toColor();
      }
      if (hsl.lightness < 0.4) {
        return hsl.withLightness(0.8).toColor().withValues(alpha: (c.a * 0.7).clamp(0.12, 0.7).toDouble());
      }
      return c;
    });
  }

  static Color _darkSurface(Color c) {
    if (c.a < 0.5) return c;
    return _bgCache.putIfAbsent(c.toARGB32(), () {
      final hsl = HSLColor.fromColor(c);
      if (hsl.lightness <= 0.6) return c;
      // 1.0 (white) -> 0.12, 0.9 -> 0.17, 0.7 -> 0.27
      final l = 0.12 + (1 - hsl.lightness) * 0.5;
      return hsl.withLightness(l).withSaturation(hsl.saturation * 0.55).toColor();
    });
  }

  static Color _lightText(Color c) {
    return _fgCache.putIfAbsent(c.toARGB32(), () {
      final hsl = HSLColor.fromColor(c);
      if (hsl.lightness >= 0.5) return c;
      // 0 (black) -> 0.93, 0.3 (deep purple) -> 0.78, 0.45 -> 0.70
      final l = 0.93 - hsl.lightness * 0.5;
      return hsl.withLightness(l).toColor();
    });
  }

  /// Redraw every screen after the theme flips, keeping their state.
  static void rebuildAll(BuildContext context) {
    void visit(Element e) {
      e.markNeedsBuild();
      e.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
  }
}
