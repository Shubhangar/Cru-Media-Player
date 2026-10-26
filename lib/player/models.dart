import 'package:flutter/material.dart';

/// Subtitle appearance. Maps 1:1 onto mpv `sub-*` properties.
@immutable
class SubtitleStyle {
  final String font; // '' = mpv default
  final bool exactSize; // false: relative scale, true: exact font size
  final double scale; // sub-scale (relative)
  final int size; // sub-font-size (exact, 720-line script units)
  final Color color;
  final double borderSize;
  final Color borderColor;
  final double shadow;
  final bool bold;
  final int position; // sub-pos: 0 = top, 100 = bottom
  final bool overrideEmbedded; // force style onto ASS/SSA subs

  const SubtitleStyle({
    this.font = '',
    this.exactSize = false,
    this.scale = 1.0,
    this.size = 55,
    this.color = const Color(0xFFFFFFFF),
    this.borderSize = 3,
    this.borderColor = const Color(0xFF000000),
    this.shadow = 0,
    this.bold = false,
    this.position = 100,
    this.overrideEmbedded = false,
  });

  SubtitleStyle copyWith({
    String? font,
    bool? exactSize,
    double? scale,
    int? size,
    Color? color,
    double? borderSize,
    Color? borderColor,
    double? shadow,
    bool? bold,
    int? position,
    bool? overrideEmbedded,
  }) => SubtitleStyle(
    font: font ?? this.font,
    exactSize: exactSize ?? this.exactSize,
    scale: scale ?? this.scale,
    size: size ?? this.size,
    color: color ?? this.color,
    borderSize: borderSize ?? this.borderSize,
    borderColor: borderColor ?? this.borderColor,
    shadow: shadow ?? this.shadow,
    bold: bold ?? this.bold,
    position: position ?? this.position,
    overrideEmbedded: overrideEmbedded ?? this.overrideEmbedded,
  );

  /// mpv property name -> value.
  Map<String, String> toMpv() => {
    'sub-font': font.isEmpty ? 'sans-serif' : font,
    'sub-scale': exactSize ? '1' : scale.toStringAsFixed(2),
    'sub-font-size': exactSize ? '$size' : '55',
    'sub-color': mpvColor(color),
    'sub-border-size': borderSize.toStringAsFixed(1),
    'sub-border-color': mpvColor(borderColor),
    'sub-shadow-offset': shadow.toStringAsFixed(1),
    'sub-bold': bold ? 'yes' : 'no',
    'sub-pos': '$position',
    'sub-ass-override': overrideEmbedded ? 'force' : 'scale',
  };

  Map<String, dynamic> toJson() => {
    'font': font,
    'exactSize': exactSize,
    'scale': scale,
    'size': size,
    'color': color.toARGB32(),
    'borderSize': borderSize,
    'borderColor': borderColor.toARGB32(),
    'shadow': shadow,
    'bold': bold,
    'position': position,
    'overrideEmbedded': overrideEmbedded,
  };

  factory SubtitleStyle.fromJson(Map<String, dynamic> j) => SubtitleStyle(
    font: j['font'] as String? ?? '',
    exactSize: j['exactSize'] as bool? ?? false,
    scale: (j['scale'] as num?)?.toDouble() ?? 1,
    size: (j['size'] as num?)?.toInt() ?? 55,
    color: Color((j['color'] as num?)?.toInt() ?? 0xFFFFFFFF),
    borderSize: (j['borderSize'] as num?)?.toDouble() ?? 3,
    borderColor: Color((j['borderColor'] as num?)?.toInt() ?? 0xFF000000),
    shadow: (j['shadow'] as num?)?.toDouble() ?? 0,
    bold: j['bold'] as bool? ?? false,
    position: (j['position'] as num?)?.toInt() ?? 100,
    overrideEmbedded: j['overrideEmbedded'] as bool? ?? false,
  );
}

/// `#AARRGGBB`, the colour format mpv accepts.
String mpvColor(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

class NamedSubtitleStyle {
  final String name;
  final SubtitleStyle style;
  final bool builtIn;
  const NamedSubtitleStyle(this.name, this.style, {this.builtIn = false});
}

const builtInSubtitleStyles = [
  NamedSubtitleStyle('Classic', SubtitleStyle(), builtIn: true),
  NamedSubtitleStyle(
    'Cinema yellow',
    SubtitleStyle(color: Color(0xFFFFE14D), borderSize: 2.5, bold: true),
    builtIn: true,
  ),
  NamedSubtitleStyle(
    'Large',
    SubtitleStyle(scale: 1.4, borderSize: 3.5),
    builtIn: true,
  ),
  NamedSubtitleStyle(
    'Minimal',
    SubtitleStyle(
      scale: 0.9,
      borderSize: 1.2,
      shadow: 1.5,
      borderColor: Color(0xCC000000),
    ),
    builtIn: true,
  ),
];

/// Picture adjustments, mapped onto mpv `brightness`/`contrast`/... options.
@immutable
class VideoAdjust {
  final int brightness, contrast, saturation, gamma; // -100..100
  final bool hflip, vflip;
  final int rotation; // 0/90/180/270
  final double zoom; // mpv video-zoom (log2)
  final String aspect; // 'auto' or 'w:h'
  /// GPU upscaler: 'bilinear' (media_kit's default, fastest), 'spline36',
  /// 'ewa_lanczossharp' (sharpest).
  /// Flips are drawn by Flutter (see PlayerScreen): this libmpv build ships
  /// without ffmpeg video filters.
  final String scaler;
  final bool toneMapHdr;

  const VideoAdjust({
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.gamma = 0,
    this.hflip = false,
    this.vflip = false,
    this.rotation = 0,
    this.zoom = 0,
    this.aspect = 'auto',
    this.scaler = 'bilinear',
    this.toneMapHdr = true,
  });

  VideoAdjust copyWith({
    int? brightness,
    int? contrast,
    int? saturation,
    int? gamma,
    bool? hflip,
    bool? vflip,
    int? rotation,
    double? zoom,
    String? aspect,
    String? scaler,
    bool? toneMapHdr,
  }) => VideoAdjust(
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    saturation: saturation ?? this.saturation,
    gamma: gamma ?? this.gamma,
    hflip: hflip ?? this.hflip,
    vflip: vflip ?? this.vflip,
    rotation: rotation ?? this.rotation,
    zoom: zoom ?? this.zoom,
    aspect: aspect ?? this.aspect,
    scaler: scaler ?? this.scaler,
    toneMapHdr: toneMapHdr ?? this.toneMapHdr,
  );

  Map<String, String> toMpv() => {
    'brightness': '$brightness',
    'contrast': '$contrast',
    'saturation': '$saturation',
    'gamma': '$gamma',
    'video-rotate': '$rotation',
    'video-zoom': zoom.toStringAsFixed(3),
    'video-aspect-override': aspect == 'auto' ? 'no' : aspect,
    'scale': scaler,
    'tone-mapping': toneMapHdr ? 'bt.2390' : 'clip',
  };

  /// Approximates mpv's colour equaliser for on-screen previews
  /// (Flutter 4x5 colour matrix, offsets in 0..255).
  List<double> get previewMatrix {
    final s = (saturation + 100) / 100;
    final c = (contrast + 100) / 100;
    final b = brightness / 100 * 255;
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final sr = (1 - s) * lr, sg = (1 - s) * lg, sb = (1 - s) * lb;
    final off = 128 * (1 - c) + b;
    return [
      c * (sr + s), c * sg, c * sb, 0, off, //
      c * sr, c * (sg + s), c * sb, 0, off,
      c * sr, c * sg, c * (sb + s), 0, off,
      0, 0, 0, 1, 0,
    ];
  }
}
