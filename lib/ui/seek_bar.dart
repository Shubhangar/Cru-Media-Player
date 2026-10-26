import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../player/player_controller.dart';
import '../player/waveform.dart';
import '../theme.dart';

/// Returns a preview frame near a time, or null if unavailable.
typedef PreviewProvider = Future<Uint8List?> Function(Duration t);

/// Thick full-width seek bar.
/// - Hover shows the timestamp, plus a frame preview when [preview] is set.
/// - Hold Shift while dragging for 10x finer scrubbing.
/// - Scroll wheel over the bar steps frame by frame.
/// - With a [waveform] the bar becomes a waveform (played part in orange).
class SeekBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final Duration buffer;
  final List<Bookmark> bookmarks;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<bool> onFrameStep;
  final Waveform? waveform;
  final PreviewProvider? preview;

  /// Height of the waveform when shown (music view uses a taller one).
  final double waveformHeight;
  const SeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.buffer,
    required this.bookmarks,
    required this.onSeek,
    required this.onFrameStep,
    this.waveform,
    this.preview,
    this.waveformHeight = 30,
  });

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _hoverX;
  double? _dragFraction;
  double _lastDragX = 0;
  Uint8List? _frame;
  Timer? _previewDebounce;
  int _previewSeq = 0;

  double get _durMs => widget.duration.inMilliseconds.toDouble();

  double _frac(Duration d) =>
      _durMs <= 0 ? 0 : (d.inMilliseconds / _durMs).clamp(0.0, 1.0);

  @override
  void dispose() {
    _previewDebounce?.cancel();
    super.dispose();
  }

  void _requestPreview(double fraction) {
    final provider = widget.preview;
    if (provider == null || _durMs <= 0) return;
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 60), () async {
      final seq = ++_previewSeq;
      final img = await provider(
        Duration(milliseconds: (fraction * _durMs).round()),
      );
      // Keep the previous frame on failure so the box does not flicker.
      if (mounted && seq == _previewSeq && img != null) {
        setState(() => _frame = img);
      }
    });
  }

  void _hover(double x, double width) {
    setState(() => _hoverX = x);
    _requestPreview((x / width).clamp(0.0, 1.0));
  }

  void _dragStart(double x, double width) {
    _lastDragX = x;
    setState(() => _dragFraction = (x / width).clamp(0.0, 1.0));
    _requestPreview(_dragFraction!);
  }

  void _dragUpdate(double x, double width) {
    final fine = HardwareKeyboard.instance.isShiftPressed;
    final dx = (x - _lastDragX) * (fine ? 0.1 : 1.0);
    _lastDragX = x;
    setState(
      () => _dragFraction = ((_dragFraction ?? 0) + dx / width).clamp(0.0, 1.0),
    );
    _requestPreview(_dragFraction!);
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
        final wave = widget.waveform;
        final barH = wave != null
            ? widget.waveformHeight
            : (active ? 12.0 : 8.0);

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onHover: (e) => _hover(e.localPosition.dx, width),
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
                height: wave != null ? barH + 8 : 28,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.centerLeft,
                  children: [
                    if (wave != null)
                      SizedBox(
                        width: width,
                        height: barH,
                        child: CustomPaint(
                          painter: WaveformPainter(
                            wave,
                            played: played,
                            hover: _hoverX == null ? null : _hoverX! / width,
                          ),
                        ),
                      )
                    else ...[
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
                    ],
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
                    if (active || wave != null)
                      Positioned(
                        left: width * played - (wave != null ? 1 : 8),
                        child: wave != null
                            ? Container(
                                width: 2,
                                height: barH + 6,
                                color: ConeColors.text,
                              )
                            : Container(
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
                    if (active) _bubble(width, barH),
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

  /// Timestamp (and frame preview, when available) above the cursor.
  Widget _bubble(double width, double barH) {
    final x = _dragFraction != null ? _dragFraction! * width : _hoverX!;
    final t = Duration(milliseconds: ((x / width) * _durMs).round());
    final fine =
        _dragFraction != null && HardwareKeyboard.instance.isShiftPressed;
    final showFrame = widget.preview != null && _frame != null;
    final bubbleW = showFrame ? 192.0 : 92.0;
    return Positioned(
      left: (x - bubbleW / 2).clamp(0.0, (width - bubbleW).clamp(0.0, width)),
      bottom: barH / 2 + 18,
      child: Container(
        width: bubbleW,
        decoration: BoxDecoration(
          color: ConeColors.surface,
          borderRadius: BorderRadius.circular(ConeRadius.md),
          border: Border.all(
            color: fine ? ConeColors.accent : ConeColors.border,
          ),
          boxShadow: const [
            BoxShadow(color: Color(0x88000000), blurRadius: 12),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showFrame)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.memory(
                  _frame!,
                  key: const ValueKey('seek-preview'),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  cacheWidth: 384,
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
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
          ],
        ),
      ),
    );
  }
}

/// Mirrored bars; [played] fraction in accent, the rest muted.
class WaveformPainter extends CustomPainter {
  final Waveform wave;
  final double played;
  final double? hover;
  final double barWidth, gap;
  WaveformPainter(
    this.wave, {
    required this.played,
    this.hover,
    this.barWidth = 2,
    this.gap = 1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final step = barWidth + gap;
    final n = (size.width / step).floor();
    if (n <= 0) return;
    final mid = size.height / 2;
    final playedPaint = Paint()..color = ConeColors.accent;
    final hoverPaint = Paint()
      ..color = ConeColors.accent.withValues(alpha: 0.55);
    final restPaint = Paint()
      ..color = ConeColors.textMuted.withValues(alpha: 0.45);
    for (var i = 0; i < n; i++) {
      final f = i / (n - 1).clamp(1, n);
      final h = (wave.at(f) * (size.height - 2)).clamp(2.0, size.height);
      final paint = f <= played
          ? playedPaint
          : (hover != null && f <= hover! ? hoverPaint : restPaint);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * step, mid - h / 2, barWidth, h),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(WaveformPainter old) =>
      old.wave != wave || old.played != played || old.hover != hover;
}
