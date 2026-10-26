import 'package:flutter/material.dart';

/// Cone Player colour system: charcoal canvas + traffic-cone orange accent.
class ConeColors {
  static const canvas = Color(0xFF121212);
  static const surface = Color(0xFF1E1E1E);
  static const surfaceHigh = Color(0xFF2A2A2A);
  static const border = Color(0xFF333333);
  static const accent = Color(0xFFFF6600);
  static const accentDim = Color(0x55FF6600);
  static const text = Color(0xFFEDEDED);
  static const textMuted = Color(0xFF9A9A9A);
  static const coneStripe = Color(0xFFF2F2F2);
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
        side: const BorderSide(color: ConeColors.border),
      ),
      textStyle: const TextStyle(color: ConeColors.text, fontSize: 13),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: ConeColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ConeRadius.lg),
        side: const BorderSide(color: ConeColors.border),
      ),
    ),
    sliderTheme: const SliderThemeData(
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
        borderSide: const BorderSide(color: ConeColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ConeRadius.sm),
        borderSide: const BorderSide(color: ConeColors.accent),
      ),
    ),
  );
}
