import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Speaker icon plus a slim horizontal slider. Click the icon to mute,
/// click or drag the track to set, scroll anywhere on it to nudge.
class VolumeSlider extends StatefulWidget {
  final double volume; // 0..100
  final ValueChanged<double> onChanged;
  final VoidCallback onToggleMute;
  const VolumeSlider({
    super.key,
    required this.volume,
    required this.onChanged,
    required this.onToggleMute,
  });

  static const trackWidth = 96.0;

  @override
  State<VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends State<VolumeSlider> {
  bool _hover = false, _dragging = false;

  IconData get _icon {
    final v = widget.volume;
    if (v <= 0) return Icons.volume_off_rounded;
    if (v < 34) return Icons.volume_mute_rounded;
    if (v < 67) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  void _setFromLocal(double dx) =>
      widget.onChanged((dx / VolumeSlider.trackWidth).clamp(0.0, 1.0) * 100);

  @override
  Widget build(BuildContext context) {
    final active = _hover || _dragging;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) {
            widget.onChanged(
              (widget.volume - e.scrollDelta.dy.sign * 5).clamp(0, 100),
            );
          }
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: widget.volume <= 0 ? 'Unmute (M)' : 'Mute (M)',
              child: InkResponse(
                radius: 18,
                onTap: widget.onToggleMute,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(_icon, size: 22, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 2),
            Tooltip(
              message: 'Volume ${widget.volume.round()}%',
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  dragStartBehavior: DragStartBehavior.down,
                  onTapDown: (d) => _setFromLocal(d.localPosition.dx),
                  onHorizontalDragStart: (d) {
                    setState(() => _dragging = true);
                    _setFromLocal(d.localPosition.dx);
                  },
                  onHorizontalDragUpdate: (d) =>
                      _setFromLocal(d.localPosition.dx),
                  onHorizontalDragEnd: (_) => setState(() => _dragging = false),
                  child: SizedBox(
                    width: VolumeSlider.trackWidth,
                    height: 30,
                    child: CustomPaint(
                      painter: _TrackPainter(widget.volume / 100, active),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  final double level;
  final bool active;
  _TrackPainter(this.level, this.active);

  @override
  void paint(Canvas canvas, Size size) {
    const thumbR = 7.0;
    final y = size.height / 2;
    final h = active ? 5.0 : 4.0;
    final left = thumbR, right = size.width - thumbR;
    final x = left + (right - left) * level.clamp(0.0, 1.0);
    final track = RRect.fromLTRBR(
      left,
      y - h / 2,
      right,
      y + h / 2,
      Radius.circular(h),
    );
    canvas.drawRRect(track, Paint()..color = const Color(0x40FFFFFF));
    canvas.drawRRect(
      RRect.fromLTRBR(left, y - h / 2, x, y + h / 2, Radius.circular(h)),
      Paint()..color = active ? ConeColors.accent : Colors.white,
    );
    canvas.drawCircle(
      Offset(x, y + 0.5),
      thumbR + 0.5,
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawCircle(Offset(x, y), thumbR, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.level != level || old.active != active;
}
