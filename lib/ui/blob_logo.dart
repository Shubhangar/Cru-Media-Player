import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Cru's mascot: a soft blob with big cute eyes. [animated] adds a gentle
/// bob and an occasional blink (use it for large, idle placements).
class BlobLogo extends StatefulWidget {
  final double size;
  final Color? color;
  final bool animated;
  const BlobLogo({
    super.key,
    this.size = 48,
    this.color,
    this.animated = false,
  });

  @override
  State<BlobLogo> createState() => _BlobLogoState();
}

class _BlobLogoState extends State<BlobLogo>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    if (widget.animated) {
      _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 4200),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? ConeColors.accent;
    Widget paint(double t) => CustomPaint(
      size: Size.square(widget.size),
      painter: BlobPainter(color: color, t: t),
    );
    final c = _ctrl;
    if (c == null) return paint(0);
    return AnimatedBuilder(animation: c, builder: (_, _) => paint(c.value));
  }
}

/// Paints the blob. [t] in 0..1 drives the idle bob and the blink.
class BlobPainter extends CustomPainter {
  final Color color;
  final double t;
  BlobPainter({required this.color, this.t = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);
    canvas.scale(s / 100);

    // Gentle squash-and-stretch bob.
    final bob = math.sin(t * 2 * math.pi);
    canvas.translate(50, 92);
    canvas.scale(1 + 0.025 * bob, 1 - 0.025 * bob);
    canvas.translate(-50, -92 - 1.5 * bob);

    // Body: wide rounded bottom, softer narrower top.
    final body = Path()
      ..moveTo(50, 10)
      ..cubicTo(74, 10, 90, 30, 92, 56)
      ..cubicTo(94, 78, 80, 92, 50, 92)
      ..cubicTo(20, 92, 6, 78, 8, 56)
      ..cubicTo(10, 30, 26, 10, 50, 10)
      ..close();

    // Soft shadow under the blob.
    canvas.drawOval(
      const Rect.fromLTRB(18, 88, 82, 98),
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    final hsl = HSLColor.fromColor(color);
    final light = hsl
        .withLightness((hsl.lightness + 0.16).clamp(0.0, 1.0))
        .toColor();
    final dark = hsl
        .withLightness((hsl.lightness - 0.12).clamp(0.0, 1.0))
        .toColor();
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [light, color, dark],
          stops: const [0, 0.55, 1],
        ).createShader(const Rect.fromLTRB(8, 10, 92, 92)),
    );

    // Glossy highlight.
    canvas.drawOval(
      const Rect.fromLTWH(24, 20, 22, 13),
      Paint()..color = const Color(0x59FFFFFF),
    );
    canvas.drawCircle(
      const Offset(52, 22),
      2.6,
      Paint()..color = const Color(0x66FFFFFF),
    );

    // Blink: eyes close briefly near the end of each cycle.
    final blinkPhase = (t - 0.9) / 0.06;
    final open = blinkPhase > 0 && blinkPhase < 1
        ? (1 - math.sin(blinkPhase * math.pi)).clamp(0.08, 1.0)
        : 1.0;

    for (final x in [36.0, 64.0]) {
      final eye = Rect.fromCenter(
        center: Offset(x, 54),
        width: 17,
        height: 21 * open,
      );
      canvas.drawOval(eye, Paint()..color = Colors.white);
      if (open > 0.3) {
        final pupil = Rect.fromCenter(
          center: Offset(x + 1.2, 56),
          width: 11,
          height: 14 * open,
        );
        canvas.drawOval(pupil, Paint()..color = const Color(0xFF1E1A1D));
        // Sparkles.
        canvas.drawCircle(
          Offset(x + 3.4, 52 - 2 * (1 - open)),
          2.6,
          Paint()..color = Colors.white,
        );
        canvas.drawCircle(
          Offset(x - 1.5, 59),
          1.2,
          Paint()..color = Colors.white,
        );
      }
    }

    // Blush.
    final blush = Paint()..color = const Color(0x66FF8FA3);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(24, 68), width: 11, height: 6),
      blush,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(76, 68), width: 11, height: 6),
      blush,
    );

    // Tiny smile.
    canvas.drawArc(
      Rect.fromCenter(center: const Offset(50, 68), width: 10, height: 7),
      0.15 * math.pi,
      0.7 * math.pi,
      false,
      Paint()
        ..color = const Color(0xFF1E1A1D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(BlobPainter old) => old.t != t || old.color != color;
}
