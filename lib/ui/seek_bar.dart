import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../player/player_controller.dart';
import '../theme.dart';

/// Thick full-width seek bar.
/// - Hover shows the timestamp under the cursor.
/// - Hold Shift while dragging for 10x finer scrubbing.
/// - Scroll wheel over the bar steps frame by frame.
class SeekBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final Duration buffer;
  final List<Bookmark> bookmarks;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<bool> onFrameStep;
  const SeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.buffer,
    required this.bookmarks,
    required this.onSeek,
    required this.onFrameStep,
  });

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _hoverX;
  double? _dragFraction;
  double _lastDragX = 0;

  double get _durMs => widget.duration.inMilliseconds.toDouble();

  double _frac(Duration d) =>
      _durMs <= 0 ? 0 : (d.inMilliseconds / _durMs).clamp(0.0, 1.0);

  void _dragStart(double x, double width) {
    _lastDragX = x;
    setState(() => _dragFraction = (x / width).clamp(0.0, 1.0));
  }

  void _dragUpdate(double x, double width) {
    final fine = HardwareKeyboard.instance.isShiftPressed;
    final dx = (x - _lastDragX) * (fine ? 0.1 : 1.0);
    _lastDragX = x;
    setState(
      () => _dragFraction = ((_dragFraction ?? 0) + dx / width).clamp(0.0, 1.0),
    );
  }

  void _dragEnd() {
    if (_dragFraction != null) {
      widget.onSeek(Duration(milliseconds: (_dragFraction! * _durMs).round()));
    }
    setState(() => _dragFraction = null);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        final active = _hoverX != null || _dragFraction != null;
        final played = _dragFraction ?? _frac(widget.position);
        final barH = active ? 12.0 : 8.0;

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onHover: (e) => setState(() => _hoverX = e.localPosition.dx),
          onExit: (_) => setState(() => _hoverX = null),
          child: Listener(
            onPointerSignal: (e) {
              if (e is PointerScrollEvent && e.scrollDelta.dy != 0) {
                widget.onFrameStep(e.scrollDelta.dy > 0);
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => widget.onSeek(
                Duration(
                  milliseconds:
                      ((d.localPosition.dx / width).clamp(0.0, 1.0) * _durMs)
                          .round(),
                ),
              ),
              onHorizontalDragStart: (d) =>
                  _dragStart(d.localPosition.dx, width),
              onHorizontalDragUpdate: (d) =>
                  _dragUpdate(d.localPosition.dx, width),
              onHorizontalDragEnd: (_) => _dragEnd(),
              child: SizedBox(
                height: 28,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.centerLeft,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      height: barH,
                      decoration: BoxDecoration(
                        color: ConeColors.border,
                        borderRadius: BorderRadius.circular(ConeRadius.sm),
                      ),
                    ),
                    _bar(
                      width * _frac(widget.buffer),
                      barH,
                      ConeColors.textMuted.withValues(alpha: 0.35),
                    ),
                    _bar(width * played, barH, ConeColors.accent),
                    for (final b in widget.bookmarks)
                      Positioned(
                        left: width * _frac(b.position) - 1.5,
                        child: Container(
                          width: 3,
                          height: barH + 8,
                          decoration: BoxDecoration(
                            color: ConeColors.text,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    if (active)
                      Positioned(
                        left: width * played - 8,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: ConeColors.accent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: ConeColors.canvas,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    if (_hoverX != null || _dragFraction != null)
                      _timeBubble(width),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _bar(double w, double h, Color color) => AnimatedContainer(
    duration: const Duration(milliseconds: 120),
    width: w.clamp(0, double.infinity),
    height: h,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(ConeRadius.sm),
    ),
  );

  Widget _timeBubble(double width) {
    final x = _dragFraction != null ? _dragFraction! * width : _hoverX!;
    final t = Duration(milliseconds: ((x / width) * _durMs).round());
    final fine =
        _dragFraction != null && HardwareKeyboard.instance.isShiftPressed;
    const bubbleW = 92.0;
    return Positioned(
      left: (x - bubbleW / 2).clamp(0.0, width - bubbleW),
      bottom: 30,
      child: Container(
        width: bubbleW,
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: ConeColors.surface,
          borderRadius: BorderRadius.circular(ConeRadius.sm),
          border: Border.all(
            color: fine ? ConeColors.accent : ConeColors.border,
          ),
        ),
        child: Text(
          fine ? '${formatDuration(t)} · fine' : formatDuration(t),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            color: ConeColors.text,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
