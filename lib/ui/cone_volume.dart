import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Volume control drawn as a traffic cone that fills with orange from the
/// base up. Click or drag vertically to set, scroll to nudge.
class ConeVolume extends StatefulWidget {
  final double volume; // 0..100
  final ValueChanged<double> onChanged;
  final VoidCallback onToggleMute;
  const ConeVolume({
    super.key,
    required this.volume,
    required this.onChanged,
    required this.onToggleMute,
  });

  @override
  State<ConeVolume> createState() => _ConeVolumeState();
}

class _ConeVolumeState extends State<ConeVolume> {
  static const _size = Size(30, 34);
  bool _hover = false;

  void _setFromLocal(Offset local) {
    final v = (1 - (local.dy / _size.height)).clamp(0.0, 1.0) * 100;
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Volume ${widget.volume.round()}%  ·  double-click to mute',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              widget.onChanged(
                  (widget.volume - e.scrollDelta.dy.sign * 5).clamp(0, 100));
            }
          },
          child: GestureDetector(
            onTapDown: (d) => _setFromLocal(d.localPosition),
            onVerticalDragUpdate: (d) => _setFromLocal(d.localPosition),
            onDoubleTap: widget.onToggleMute,
            child: CustomPaint(
              size: _size,
              painter: _ConePainter(widget.volume / 100, _hover),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConePainter extends CustomPainter {
  final double level;
  final bool hover;
  _ConePainter(this.level, this.hover);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final baseH = h * 0.14;
    final bodyBottom = h - baseH;
    const tipW = 5.0;

    final body = Path()
      ..moveTo(w / 2 - tipW / 2, 0)
      ..lineTo(w / 2 + tipW / 2, 0)
      ..lineTo(w * 0.86, bodyBottom)
      ..lineTo(w * 0.14, bodyBottom)
      ..close();
    final base = RRect.fromLTRBR(0, bodyBottom, w, h, const Radius.circular(2));
    final cone = Path()
      ..addPath(body, Offset.zero)
      ..addRRect(base);

    // Empty cone.
    canvas.drawPath(cone, Paint()..color = ConeColors.surfaceHigh);

    // Orange fill from the bottom up.
    canvas.save();
    canvas.clipPath(cone);
    final fillTop = h * (1 - level);
    canvas.drawRect(Rect.fromLTRB(0, fillTop, w, h),
        Paint()..color = ConeColors.accent);

    // Reflective stripes, dimmed above the fill line.
    for (final band in const [(0.30, 0.40), (0.56, 0.66)]) {
      final top = bodyBottom * band.$1, bottom = bodyBottom * band.$2;
      final stripe = Rect.fromLTRB(0, top, w, bottom);
      canvas.drawRect(
          stripe,
          Paint()
            ..color = bottom <= fillTop
                ? ConeColors.textMuted.withValues(alpha: 0.35)
                : ConeColors.coneStripe);
    }
    canvas.restore();

    canvas.drawPath(
        cone,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = hover ? ConeColors.accent : ConeColors.border);
  }

  @override
  bool shouldRepaint(_ConePainter old) =>
      old.level != level || old.hover != hover;
}
