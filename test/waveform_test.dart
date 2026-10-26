import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cone_player/player/waveform.dart';
import 'package:flutter_test/flutter_test.dart';

/// 16-bit mono WAV whose amplitude ramps from silence to full scale.
File _rampWav(String path, int samples) {
  final data = ByteData(samples * 2);
  for (var i = 0; i < samples; i++) {
    final amp = i / samples;
    data.setInt16(
      i * 2,
      (math.sin(i * 0.3) * 32767 * amp).round(),
      Endian.little,
    );
  }
  final h = ByteData(44);
  void tag(int o, String s) {
    for (var i = 0; i < 4; i++) {
      h.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  h.setUint32(4, 36 + samples * 2, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  h.setUint32(16, 16, Endian.little);
  h.setUint16(20, 1, Endian.little); // PCM
  h.setUint16(22, 1, Endian.little); // mono
  h.setUint32(24, 4000, Endian.little);
  h.setUint32(28, 8000, Endian.little);
  h.setUint16(32, 2, Endian.little);
  h.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  h.setUint32(40, samples * 2, Endian.little);
  return File(path)..writeAsBytesSync([
    ...h.buffer.asUint8List(),
    ...data.buffer.asUint8List(),
  ]);
}

void main() {
  test('peaks follow the amplitude envelope and are normalised', () async {
    final dir = await Directory.systemTemp.createTemp('wave');
    final f = _rampWav('${dir.path}/r.wav', 40000);
    final p = peaksFromWav(f.path, 100)!;
    expect(p, hasLength(100));
    expect(p.last, closeTo(1, 0.01));
    expect(p.first, lessThan(0.25));
    // Monotonic-ish rise.
    expect(p[25], lessThan(p[75]));
    await dir.delete(recursive: true);
  });

  test('non-WAV input returns null', () async {
    final dir = await Directory.systemTemp.createTemp('wave');
    final f = File('${dir.path}/x.wav')
      ..writeAsStringSync('not a wav file at all');
    expect(peaksFromWav(f.path, 10), isNull);
    await dir.delete(recursive: true);
  });

  test('Waveform.at samples by fraction', () {
    final w = Waveform(Float32List.fromList([0, 0.5, 1]));
    expect(w.at(0), 0);
    expect(w.at(0.5), 0.5);
    expect(w.at(1), 1);
  });
}
