import 'dart:math' as math;

/// One peaking band of the parametric equaliser.
class EqBand {
  final double freq; // Hz
  final double gain; // dB
  final double q;
  const EqBand(this.freq, this.gain, [this.q = 1.0]);

  EqBand copyWith({double? freq, double? gain, double? q}) =>
      EqBand(freq ?? this.freq, gain ?? this.gain, q ?? this.q);

  Map<String, dynamic> toJson() => {'f': freq, 'g': gain, 'q': q};
  factory EqBand.fromJson(Map<String, dynamic> j) => EqBand(
    (j['f'] as num).toDouble(),
    (j['g'] as num).toDouble(),
    (j['q'] as num?)?.toDouble() ?? 1.0,
  );
}

const eqFrequencies = <double>[
  31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000, //
];

class EqPreset {
  final String id;
  final String name;
  final List<double> gains; // one per [eqFrequencies]
  const EqPreset(this.id, this.name, this.gains);

  List<EqBand> get bands => [
    for (var i = 0; i < eqFrequencies.length; i++)
      EqBand(eqFrequencies[i], gains[i], 1.0),
  ];
}

const eqPresets = <EqPreset>[
  EqPreset('flat', 'Flat', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
  EqPreset('bass', 'Bass boost', [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
  EqPreset('treble', 'Treble boost', [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]),
  EqPreset('vocal', 'Vocal clarity', [-2, -2, -1, 0, 2, 4, 4, 2, 0, -1]),
  EqPreset('loud', 'Loudness', [5, 4, 2, 0, -1, -1, 0, 2, 4, 5]),
  EqPreset('speech', 'Speech', [-6, -4, -2, 0, 2, 3, 4, 3, 0, -3]),
  EqPreset('night', 'Night mode', [-5, -4, -3, -1, 0, 1, 1, 0, -1, -2]),
  EqPreset('rock', 'Rock', [4, 3, 2, 0, -1, -1, 1, 2, 3, 4]),
];

/// Builds the mpv `af` value for the bands (empty string = no filter).
/// Adds a negative pre-gain equal to the biggest boost to avoid clipping.
String buildEqFilter(List<EqBand> bands) {
  final active = bands.where((b) => b.gain.abs() >= 0.05).toList();
  if (active.isEmpty) return '';
  final peak = eqResponsePeak(bands);
  final parts = [
    if (peak > 0) 'volume=${(-peak).toStringAsFixed(1)}dB',
    for (final b in active)
      'equalizer=f=${b.freq.round()}:t=q:w=${b.q.toStringAsFixed(2)}'
          ':g=${b.gain.toStringAsFixed(1)}',
  ];
  return 'lavfi=[${parts.join(',')}]';
}

/// Combined gain in dB of all bands at [f] (RBJ peaking biquads, 48 kHz).
double eqResponseDb(List<EqBand> bands, double f, {double fs = 48000}) {
  var total = 0.0;
  final w = 2 * math.pi * f / fs;
  for (final b in bands) {
    if (b.gain.abs() < 0.05) continue;
    final a = math.pow(10, b.gain / 40).toDouble();
    final w0 = 2 * math.pi * b.freq / fs;
    final alpha = math.sin(w0) / (2 * b.q);
    final b0 = 1 + alpha * a, b1 = -2 * math.cos(w0), b2 = 1 - alpha * a;
    final a0 = 1 + alpha / a, a1 = -2 * math.cos(w0), a2 = 1 - alpha / a;
    // |H(e^jw)|
    final cw = math.cos(w),
        sw = math.sin(w),
        c2 = math.cos(2 * w),
        s2 = math.sin(2 * w);
    final nr = b0 + b1 * cw + b2 * c2, ni = -(b1 * sw + b2 * s2);
    final dr = a0 + a1 * cw + a2 * c2, di = -(a1 * sw + a2 * s2);
    final mag = math.sqrt((nr * nr + ni * ni) / (dr * dr + di * di));
    total += 20 * math.log(mag) / math.ln10;
  }
  return total;
}

/// Highest boost across the audible range, in dB (0 if none).
double eqResponsePeak(List<EqBand> bands) {
  var peak = 0.0;
  for (var i = 0; i <= 60; i++) {
    final f = 20 * math.pow(1000, i / 60).toDouble(); // 20 Hz .. 20 kHz
    peak = math.max(peak, eqResponseDb(bands, f));
  }
  return peak;
}
