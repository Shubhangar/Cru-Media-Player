import 'package:flutter/material.dart';

/// A canvas variant (General › Theme).
class CanvasPalette {
  final String id, name;
  final Color canvas, surface, surfaceHigh, border;
  const CanvasPalette(
    this.id,
    this.name,
    this.canvas,
    this.surface,
    this.surfaceHigh,
    this.border,
  );
}

const canvasPalettes = [
  CanvasPalette(
    'charcoal',
    'Charcoal',
    Color(0xFF121212),
    Color(0xFF1E1E1E),
    Color(0xFF2A2A2A),
    Color(0xFF333333),
  ),
  CanvasPalette(
    'black',
    'True black (OLED)',
    Color(0xFF000000),
    Color(0xFF111111),
    Color(0xFF1C1C1C),
    Color(0xFF2A2A2A),
  ),
  CanvasPalette(
    'graphite',
    'Graphite',
    Color(0xFF1B1D21),
    Color(0xFF25282D),
    Color(0xFF30343A),
    Color(0xFF3B4047),
  ),
];

/// Accent choices (General › Accent). Cru orange is the identity colour.
const accentChoices = <(String, Color)>[
  ('Cru orange', Color(0xFFFF6600)),
  ('Amber', Color(0xFFFFB300)),
  ('Signal red', Color(0xFFE53935)),
  ('Lime', Color(0xFF9CCC65)),
  ('Sky', Color(0xFF29B6F6)),
  ('Violet', Color(0xFFB388FF)),
];

/// Cru Media Player colour system: charcoal canvas + traffic-cone orange accent.
/// Canvas and accent can be switched at runtime via [apply].
class ConeColors {
  static Color canvas = const Color(0xFF121212);
  static Color surface = const Color(0xFF1E1E1E);
  static Color surfaceHigh = const Color(0xFF2A2A2A);
  static Color border = const Color(0xFF333333);
  static Color accent = const Color(0xFFFF6600);
  static Color accentDim = const Color(0x55FF6600);
  static const text = Color(0xFFEDEDED);
  static const textMuted = Color(0xFF9A9A9A);
  static const coneStripe = Color(0xFFF2F2F2);

  static void apply({CanvasPalette? palette, Color? accentColor}) {
    if (palette != null) {
      canvas = palette.canvas;
      surface = palette.surface;
      surfaceHigh = palette.surfaceHigh;
      border = palette.border;
    }
    if (accentColor != null) {
      accent = accentColor;
      accentDim = accentColor.withValues(alpha: 0x55 / 255);
    }
  }
}

/// Control size (Interface › Control size).
class ConeDensity {
  static double scale = 1.0;
  static double forName(String d) => switch (d) {
    'compact' => 0.85,
    'large' => 1.25,
    _ => 1.0,
  };
}

class ConeRadius {
  static const sm = 4.0;
  static const md = 6.0;
  static const lg = 8.0;
}

ThemeData buildConeTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: ConeColors.canvas,
    colorScheme: base.colorScheme.copyWith(
      primary: ConeColors.accent,
      onPrimary: ConeColors.canvas,
      secondary: ConeColors.accent,
      surface: ConeColors.surface,
      onSurface: ConeColors.text,
    ),
    iconTheme: const IconThemeData(color: ConeColors.text, size: 22),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: ConeColors.surfaceHigh,
        borderRadius: BorderRadius.circular(ConeRadius.sm),
        border: Border.all(color: ConeColors.border),
      ),
      textStyle: const TextStyle(color: ConeColors.text, fontSize: 12),
      waitDuration: const Duration(milliseconds: 500),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: ConeColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ConeRadius.md),
        side: BorderSide(color: ConeColors.border),
      ),
      textStyle: const TextStyle(color: ConeColors.text, fontSize: 13),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: ConeColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ConeRadius.lg),
        side: BorderSide(color: ConeColors.border),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: ConeColors.accent,
      inactiveTrackColor: ConeColors.border,
      thumbColor: ConeColors.accent,
      overlayColor: ConeColors.accentDim,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ConeColors.canvas,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ConeRadius.sm),
        borderSide: BorderSide(color: ConeColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ConeRadius.sm),
        borderSide: BorderSide(color: ConeColors.accent),
      ),
    ),
  );
}
