import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../player/eq.dart';
import '../../player/player_controller.dart';
import '../../theme.dart';
import 'subtitle_tab.dart' show LangField;
import 'widgets.dart';

class AudioTab extends StatelessWidget {
  final PlayerController c;
  const AudioTab({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        SectionHeader(
          'Timing',
          Icons.timer,
          Icons.timer_outlined,
          info:
              'Fix lip-sync. Positive values play the sound later, '
              'negative values earlier.',
        ),
        SettingRow(
          label: 'Audio delay',
          child: DelayStepper(
            value: signed(c.audioDelay * 1000, unit: ' ms'),
            onMinus: () => c.setAudioDelay(c.audioDelay - 0.05),
            onPlus: () => c.setAudioDelay(c.audioDelay + 0.05),
          ),
        ),
        AdjustSlider(
          label: 'Fine delay',
          value: c.audioDelay,
          min: -2,
          max: 2,
          divisions: 400,
          defaultValue: 0,
          format: (v) => signed(v * 1000, unit: ' ms'),
          onChanged: c.setAudioDelay,
        ),
        panelDivider,
        SectionHeader(
          'Equalizer',
          Icons.equalizer,
          Icons.equalizer_outlined,
          info:
              'Shape the sound. Pick a preset, or drag the points on the '
              'curve: left/right changes the frequency, up/down the gain, '
              'scroll changes the width (Q).',
          trailing: ConeSwitch(
            value: c.eqEnabled,
            onChanged: (v) => c.setEq(enabled: v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 1.05,
            children: [
              for (final p in eqPresets)
                _PresetCard(
                  preset: p,
                  selected: c.eqEnabled && c.eqPresetId == p.id,
                  onTap: () =>
                      c.setEq(bands: p.bands, presetId: p.id, enabled: true),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AnimatedOpacity(
          opacity: c.eqEnabled ? 1 : 0.45,
          duration: const Duration(milliseconds: 150),
          child: ParametricEq(
            bands: c.eqBands,
            onChanged: (b) =>
                c.setEq(bands: b, presetId: 'custom', enabled: true),
          ),
        ),
        panelDivider,
        SectionHeader(
          'Default track',
          Icons.translate,
          Icons.translate_outlined,
          info:
              'Preferred audio languages, picked automatically when a file '
              'has several tracks. Use codes like "ja,jpn" in priority order.',
        ),
        LangField(
          initial: c.audioLanguages,
          hint: 'e.g. en,eng',
          onSubmit: (v) => c.setLanguages(audio: v),
        ),
      ],
    );
  }
}

class _PresetCard extends StatelessWidget {
  final EqPreset preset;
  final bool selected;
  final VoidCallback onTap;
  const _PresetCard({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? ConeColors.accentDim : ConeColors.canvas,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(ConeRadius.md),
      side: BorderSide(color: selected ? ConeColors.accent : ConeColors.border),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(ConeRadius.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
        child: Column(
          children: [
            Expanded(
              child: CustomPaint(
                size: Size.infinite,
                painter: _CurvePainter(
                  preset.bands,
                  color: selected ? ConeColors.accent : ConeColors.text,
                  mini: true,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              preset.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                color: selected ? ConeColors.accent : ConeColors.text,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

const _minF = 20.0, _maxF = 20000.0, _maxDb = 12.0;

double _xOf(double f, double w) =>
    w * (math.log(f / _minF) / math.log(_maxF / _minF));
double _fOf(double x, double w) =>
    _minF * math.pow(_maxF / _minF, (x / w).clamp(0.0, 1.0)).toDouble();
double _yOf(double db, double h) => h / 2 - db / _maxDb * (h / 2 - 6);
double _dbOf(double y, double h) =>
    ((h / 2 - y) / (h / 2 - 6) * _maxDb).clamp(-_maxDb, _maxDb).toDouble();

class _CurvePainter extends CustomPainter {
  final List<EqBand> bands;
  final Color color;
  final bool mini;
  final int? selected;
  _CurvePainter(
    this.bands, {
    required this.color,
    this.mini = false,
    this.selected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final grid = Paint()
      ..color = ConeColors.border
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), grid);
    if (!mini) {
      for (final f in [100.0, 1000.0, 10000.0]) {
        final x = _xOf(f, w);
        canvas.drawLine(Offset(x, 0), Offset(x, h), grid);
      }
      for (final db in [-6.0, 6.0]) {
        final y = _yOf(db, h);
        canvas.drawLine(
          Offset(0, y),
          Offset(w, y),
          grid..color = ConeColors.border.withValues(alpha: 0.5),
        );
      }
    }

    final path = Path();
    const steps = 80;
    for (var i = 0; i <= steps; i++) {
      final x = w * i / steps;
      final y = _yOf(eqResponseDb(bands, _fOf(x, w)), h);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final fill = Path.from(path)
      ..lineTo(w, h / 2)
      ..lineTo(0, h / 2)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.15));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = mini ? 1.5 : 2,
    );

    if (!mini) {
      for (var i = 0; i < bands.length; i++) {
        final b = bands[i];
        final o = Offset(_xOf(b.freq, w), _yOf(b.gain, h));
        final sel = i == selected;
        canvas.drawCircle(
          o,
          sel ? 7 : 5,
          Paint()..color = sel ? ConeColors.accent : ConeColors.surfaceHigh,
        );
        canvas.drawCircle(
          o,
          sel ? 7 : 5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = sel ? ConeColors.text : ConeColors.accent,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) => true;
}

/// Full parametric EQ: draggable band handles on a response graph,
/// plus precise controls for the selected band.
class ParametricEq extends StatefulWidget {
  final List<EqBand> bands;
  final ValueChanged<List<EqBand>> onChanged;
  const ParametricEq({super.key, required this.bands, required this.onChanged});

  @override
  State<ParametricEq> createState() => _ParametricEqState();
}

class _ParametricEqState extends State<ParametricEq> {
  int _sel = 5;
  static const _h = 150.0;

  void _update(int i, EqBand b) {
    final next = [...widget.bands];
    next[i] = b;
    widget.onChanged(next);
  }

  int _nearest(Offset p, double w) {
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < widget.bands.length; i++) {
      final b = widget.bands[i];
      final d = (Offset(_xOf(b.freq, w), _yOf(b.gain, _h)) - p).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final bands = widget.bands;
    final sel = bands[_sel.clamp(0, bands.length - 1)];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth;
              return Listener(
                onPointerSignal: (e) {
                  if (e is PointerScrollEvent) {
                    final i = _nearest(e.localPosition, w);
                    setState(() => _sel = i);
                    final q = (bands[i].q * (e.scrollDelta.dy > 0 ? 0.9 : 1.1))
                        .clamp(0.3, 8.0);
                    _update(i, bands[i].copyWith(q: q.toDouble()));
                  }
                },
                child: GestureDetector(
                  onPanStart: (d) =>
                      setState(() => _sel = _nearest(d.localPosition, w)),
                  onTapDown: (d) =>
                      setState(() => _sel = _nearest(d.localPosition, w)),
                  onPanUpdate: (d) => _update(
                    _sel,
                    bands[_sel].copyWith(
                      freq: _fOf(d.localPosition.dx, w).roundToDouble(),
                      gain: (_dbOf(d.localPosition.dy, _h) * 2).round() / 2,
                    ),
                  ),
                  child: Container(
                    height: _h,
                    decoration: BoxDecoration(
                      color: ConeColors.canvas,
                      borderRadius: BorderRadius.circular(ConeRadius.md),
                      border: Border.all(color: ConeColors.border),
                    ),
                    child: CustomPaint(
                      size: Size(w, _h),
                      painter: _CurvePainter(
                        bands,
                        color: ConeColors.accent,
                        selected: _sel,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
          child: Row(
            children: [
              Text(
                'Band ${_sel + 1}',
                style: TextStyle(
                  fontSize: 12,
                  color: ConeColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${_fmtF(sel.freq)}  ·  ${signed(sel.gain, digits: 1, unit: ' dB')}'
                '  ·  Q ${sel.q.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: ConeColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        AdjustSlider(
          label: 'Gain',
          value: sel.gain,
          min: -_maxDb,
          max: _maxDb,
          divisions: 48,
          defaultValue: 0,
          format: (v) => signed(v, digits: 1, unit: ' dB'),
          onChanged: (v) => _update(_sel, sel.copyWith(gain: v)),
        ),
        AdjustSlider(
          label: 'Frequency',
          value: math.log(sel.freq / _minF) / math.log(_maxF / _minF),
          min: 0,
          max: 1,
          format: (v) => _fmtF(_fOf(v, 1)),
          onChanged: (v) =>
              _update(_sel, sel.copyWith(freq: _fOf(v, 1).roundToDouble())),
        ),
        AdjustSlider(
          label: 'Width (Q)',
          info:
              'Low Q affects a wide range of frequencies; high Q a narrow one.',
          value: sel.q,
          min: 0.3,
          max: 8,
          defaultValue: 1,
          format: (v) => v.toStringAsFixed(2),
          onChanged: (v) => _update(_sel, sel.copyWith(q: v)),
        ),
      ],
    );
  }

  static String _fmtF(double f) => f >= 1000
      ? '${(f / 1000).toStringAsFixed(f >= 10000 ? 0 : 1)} kHz'
      : '${f.round()} Hz';
}
