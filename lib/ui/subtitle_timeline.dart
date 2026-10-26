import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../player/player_controller.dart';
import '../player/subtitles.dart';
import '../player/waveform.dart';
import '../theme.dart';

/// Window of the file around the playhead with subtitle blocks drawn over
/// the audio waveform. Drag blocks sideways to re-sync (changes the
/// subtitle delay); click to seek; Ctrl/⌘ + scroll to zoom.
class SubtitleTimeline extends StatefulWidget {
  final List<Cue> cues;
  final Duration position, duration;
  final double delay; // seconds
  final Waveform? waveform;
  final ValueChanged<double> onDelay;
  final ValueChanged<Duration> onSeek;
  const SubtitleTimeline({
    super.key,
    required this.cues,
    required this.position,
    required this.duration,
    required this.delay,
    required this.onDelay,
    required this.onSeek,
    this.waveform,
  });

  static const height = 76.0;

  @override
  State<SubtitleTimeline> createState() => _SubtitleTimelineState();
}

class _SubtitleTimelineState extends State<SubtitleTimeline> {
  double _window = 30; // seconds visible
  double? _dragStartDelay;
  double _dragDx = 0;

  double get _pos => widget.position.inMilliseconds / 1000;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final pxPerSec = w / _window;
        final t0 = _pos - _window / 2;
        double timeAt(double x) => t0 + x / pxPerSec;

        return Listener(
          onPointerSignal: (e) {
            final hk = HardwareKeyboard.instance;
            if (e is PointerScrollEvent &&
                (hk.isMetaPressed || hk.isControlPressed)) {
              setState(
                () => _window = (_window * (e.scrollDelta.dy > 0 ? 1.15 : 0.87))
                    .clamp(6.0, 180.0),
              );
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Count the movement from pointer-down, including drag slop, so
            // a drag of N seconds' worth shifts by exactly N seconds.
            dragStartBehavior: DragStartBehavior.down,
            onTapUp: (d) => widget.onSeek(
              Duration(
                milliseconds: (timeAt(d.localPosition.dx) * 1000)
                    .clamp(0, widget.duration.inMilliseconds.toDouble())
                    .round(),
              ),
            ),
            onHorizontalDragStart: (_) => setState(() {
              _dragStartDelay = widget.delay;
              _dragDx = 0;
            }),
            onHorizontalDragUpdate: (d) {
              _dragDx += d.delta.dx;
              final fine = HardwareKeyboard.instance.isShiftPressed;
              final next =
                  _dragStartDelay! + _dragDx / pxPerSec * (fine ? 0.1 : 1);
              // Snap to 10 ms steps.
              widget.onDelay((next * 100).round() / 100);
            },
            onHorizontalDragEnd: (_) => setState(() => _dragStartDelay = null),
            child: MouseRegion(
              cursor: _dragStartDelay != null
                  ? SystemMouseCursors.grabbing
                  : SystemMouseCursors.grab,
              child: Container(
                height: SubtitleTimeline.height,
                decoration: BoxDecoration(
                  color: const Color(0xCC121212),
                  borderRadius: BorderRadius.circular(ConeRadius.md),
                  border: Border.all(color: ConeColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _TimelinePainter(
                          cues: widget.cues,
                          t0: t0,
                          pxPerSec: pxPerSec,
                          delay: widget.delay,
                          position: _pos,
                          duration: widget.duration.inMilliseconds / 1000,
                          waveform: widget.waveform,
                          dragging: _dragStartDelay != null,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 6,
                      top: 4,
                      child: _DelayChip(
                        delay: widget.delay,
                        onReset: widget.delay == 0
                            ? null
                            : () => widget.onDelay(0),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DelayChip extends StatelessWidget {
  final double delay;
  final VoidCallback? onReset;
  const _DelayChip({required this.delay, this.onReset});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.only(left: 8),
    decoration: BoxDecoration(
      color: ConeColors.surface,
      borderRadius: BorderRadius.circular(ConeRadius.sm),
      border: Border.all(
        color: delay == 0 ? ConeColors.border : ConeColors.accent,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Subtitle delay ${delay > 0 ? '+' : ''}${delay.toStringAsFixed(2)} s',
          style: TextStyle(
            fontSize: 11,
            color: delay == 0 ? ConeColors.textMuted : ConeColors.accent,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        SizedBox(
          width: 24,
          height: 22,
          child: onReset == null
              ? null
              : IconButton(
                  tooltip: 'Reset delay',
                  padding: EdgeInsets.zero,
                  iconSize: 13,
                  color: ConeColors.textMuted,
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt),
                ),
        ),
      ],
    ),
  );
}

class _TimelinePainter extends CustomPainter {
  final List<Cue> cues;
  final double t0, pxPerSec, delay, position, duration;
  final Waveform? waveform;
  final bool dragging;
  _TimelinePainter({
    required this.cues,
    required this.t0,
    required this.pxPerSec,
    required this.delay,
    required this.position,
    required this.duration,
    required this.waveform,
    required this.dragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    double x(double t) => (t - t0) * pxPerSec;
    final t1 = t0 + w / pxPerSec;

    // Waveform of the visible window.
    final wave = waveform;
    if (wave != null && duration > 0) {
      final paint = Paint()
        ..color = ConeColors.textMuted.withValues(alpha: 0.28);
      final mid = h * 0.62;
      for (var px = 0.0; px < w; px += 3) {
        final t = t0 + px / pxPerSec;
        if (t < 0 || t > duration) continue;
        final a = wave.at(t / duration) * h * 0.55;
        canvas.drawRect(Rect.fromLTWH(px, mid - a / 2, 2, a), paint);
      }
    }

    // Ruler: ticks every 1/5/10 s depending on zoom.
    final step = pxPerSec > 60 ? 1.0 : (pxPerSec > 15 ? 5.0 : 10.0);
    final tick = Paint()..color = ConeColors.border;
    final first = (t0 / step).ceil() * step;
    for (var t = first; t <= t1; t += step) {
      if (t < 0) continue;
      final px = x(t);
      final major = (t % (step * 2)).abs() < 1e-6;
      canvas.drawLine(Offset(px, 0), Offset(px, major ? 10 : 5), tick);
      if (major) {
        _text(
          canvas,
          formatDuration(Duration(seconds: t.round())),
          Offset(px + 3, 1),
          const TextStyle(fontSize: 9, color: ConeColors.textMuted),
          maxWidth: 60,
        );
      }
    }

    // Cue blocks, shifted by the current delay.
    final lane = Rect.fromLTWH(0, 18, w, h - 26);
    for (final c in cues) {
      final s = c.start.inMilliseconds / 1000 + delay;
      final e = c.end.inMilliseconds / 1000 + delay;
      if (e < t0 || s > t1) continue;
      final r = RRect.fromRectAndRadius(
        Rect.fromLTRB(x(s), lane.top, x(e), lane.bottom),
        const Radius.circular(4),
      );
      final active = position >= s && position <= e;
      canvas.drawRRect(
        r,
        Paint()
          ..color = active
              ? ConeColors.accent.withValues(alpha: 0.55)
              : ConeColors.accent.withValues(alpha: dragging ? 0.35 : 0.22),
      );
      canvas.drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = ConeColors.accent,
      );
      _text(
        canvas,
        c.text.replaceAll('\n', ' '),
        Offset(r.left + 5, r.top + 4),
        const TextStyle(fontSize: 11, color: ConeColors.text, height: 1.2),
        maxWidth: (r.width - 8).clamp(0, 600),
        maxLines: 2,
      );
    }

    // Playhead (centre).
    canvas.drawLine(
      Offset(x(position), 0),
      Offset(x(position), h),
      Paint()
        ..color = ConeColors.text
        ..strokeWidth = 1.5,
    );
  }

  void _text(
    Canvas canvas,
    String s,
    Offset at,
    TextStyle style, {
    required double maxWidth,
    int maxLines = 1,
  }) {
    if (maxWidth < 12) return;
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_TimelinePainter o) =>
      o.t0 != t0 ||
      o.pxPerSec != pxPerSec ||
      o.delay != delay ||
      o.position != position ||
      o.cues != cues ||
      o.waveform != waveform ||
      o.dragging != dragging;
}

/// Placeholder when the timeline is on but there is nothing to show.
class SubtitleTimelineHint extends StatelessWidget {
  final VoidCallback onLoad;
  const SubtitleTimelineHint({super.key, required this.onLoad});

  @override
  Widget build(BuildContext context) => Container(
    height: 40,
    decoration: BoxDecoration(
      color: const Color(0xCC121212),
      borderRadius: BorderRadius.circular(ConeRadius.md),
      border: Border.all(color: ConeColors.border),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      children: [
        const Icon(
          Icons.subtitles_outlined,
          size: 16,
          color: ConeColors.textMuted,
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'The subtitle timeline works with subtitle files (.srt, .vtt, .ass).',
            style: TextStyle(fontSize: 12, color: ConeColors.textMuted),
          ),
        ),
        TextButton(onPressed: onLoad, child: const Text('Load subtitle…')),
      ],
    ),
  );
}
