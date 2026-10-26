import 'package:cone_player/player/eq.dart';
import 'package:cone_player/player/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('equalizer', () {
    test('flat bands produce no filter', () {
      expect(buildEqFilter(eqPresets.first.bands), '');
    });

    test('boosts add a matching pre-gain to avoid clipping', () {
      final f = buildEqFilter(const [EqBand(1000, 6)]);
      expect(f, startsWith('lavfi=[volume=-6.0dB,'));
      expect(f, contains('equalizer=f=1000:t=q:w=1.00:g=6.0'));
    });

    test('response peaks at the band centre with the band gain', () {
      const bands = [EqBand(1000, 6, 1)];
      expect(eqResponseDb(bands, 1000), closeTo(6, 0.05));
      expect(eqResponseDb(bands, 50).abs(), lessThan(0.5));
    });

    test('band json round-trips', () {
      const b = EqBand(250, -3.5, 2);
      final r = EqBand.fromJson(b.toJson());
      expect([r.freq, r.gain, r.q], [250, -3.5, 2]);
    });
  });

  group('subtitle style', () {
    test('relative vs exact size map to different mpv props', () {
      const rel = SubtitleStyle(scale: 1.5);
      expect(rel.toMpv()['sub-scale'], '1.50');
      expect(rel.toMpv()['sub-font-size'], '55');
      const exact = SubtitleStyle(exactSize: true, size: 72, scale: 2);
      expect(exact.toMpv()['sub-scale'], '1');
      expect(exact.toMpv()['sub-font-size'], '72');
    });

    test('colours use mpv #AARRGGBB', () {
      expect(mpvColor(const Color(0xFFFF6600)), '#FFFF6600');
    });

    test('json round-trips', () {
      const s = SubtitleStyle(font: 'Georgia', bold: true, position: 80);
      expect(SubtitleStyle.fromJson(s.toJson()).toMpv(), s.toMpv());
    });
  });

  group('video adjust', () {
    test('maps to mpv properties; flips stay in Flutter', () {
      final m = const VideoAdjust(hflip: true, scaler: 'bilinear').toMpv();
      expect(m['scale'], 'bilinear');
      expect(m.keys, isNot(contains('vf')));
    });

    test('neutral preview matrix is identity', () {
      final m = const VideoAdjust().previewMatrix;
      expect(m.sublist(0, 5), [1, 0, 0, 0, 0]);
      expect(m.sublist(6, 7), [1]);
    });
  });
}
