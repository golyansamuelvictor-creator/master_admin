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

  /// A soft shadow under cards (raised look); deeper and darker in Dark mode
  /// so it still shows on the dark background.
  static List<BoxShadow> get cardShadow => isDark
      ? const [BoxShadow(color: Color(0x73000000), blurRadius: 10, offset: Offset(0, 3))]
      : const [
          BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 3)),
          BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1)),
        ];

  /// Elevation and shadow colour for Card / Material cards.
  static const double cardElevation = 2.5;
  static Color get cardShadowColor => isDark ? const Color(0xCC000000) : const Color(0x40000000);

  static final Map<int, Color> _bgCache = {};
  static final Map<int, Color> _fgCache = {};

  static Color? bg(Color? c) => c == null ? null : (isDark ? _darkSurface(brand(c)) : brand(c));
  static Color? fg(Color? c) => c == null ? null : (isDark ? _lightText(brand(c)) : brand(c));
  static Color line(Color c) => isDark ? _darkLine(brand(c)) : brand(c);

  /// Non-null bg(), for gradient stops.
  static Color solid(Color c) => isDark ? _darkSurface(brand(c)) : brand(c);

  // ------------------------------------------------------------------
  // The church colours: Purple, Dark Blue and Red (+ black, white, greys).
  // When on (Settings › Appearance › "Church colours only"), every other
  // colour drawn through these helpers is moved to the nearest of the three,
  // keeping its lightness, so pale tints stay pale and dark text stays dark:
  //   purples / magentas      → Purple   (#4A148C)
  //   greens, teals, blues     → Dark Blue (#1E3A8A)
  //   reds, oranges, pinks     → Red      (#B91C1C)
  //   yellow / amber highlights stay (they mark corrections and warnings).
  // ------------------------------------------------------------------
  static bool brandOnly = true;
  static const Color purple = Color(0xFF4A148C);
  static const Color blue = Color(0xFF1E3A8A);
  static const Color red = Color(0xFFB91C1C);
  static final Map<int, Color> _brandCache = {};

  static Color brand(Color c) {
    if (!brandOnly) return c;
    return _brandCache.putIfAbsent(c.toARGB32(), () {
      final hsl = HSLColor.fromColor(c);
      if (hsl.saturation < 0.18 || hsl.lightness < 0.06 || hsl.lightness > 0.97) return c; // greys, black, white
      final h = hsl.hue;
      double target;
      double sat;
      if (h >= 45 && h < 70) return c; // amber / yellow highlights
      if (h >= 255 && h < 330) {
        target = 276; // purple
        sat = 0.75;
      } else if (h >= 70 && h < 255) {
        target = 226; // dark blue
        sat = 0.64;
      } else {
        target = 0; // red
        sat = 0.74;
      }
      return hsl.withHue(target).withSaturation(hsl.saturation < sat ? hsl.saturation : sat).toColor();
    });
  }

  static void setBrandOnly(bool v) {
    if (brandOnly == v) return;
    brandOnly = v;
    _brandCache.clear();
    _bgCache.clear();
    _fgCache.clear();
    _lineCache.clear();
  }

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
