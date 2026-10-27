import 'package:cone_player/tools/converter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('avconvert progress', () {
    expect(
      parseAvconvertProgress('avconvert progress:  42.50% complete'),
      0.425,
    );
    expect(
      parseAvconvertProgress(
        'progress: 10.00% complete\rprogress: 55.00% complete',
      ),
      0.55,
    );
    expect(parseAvconvertProgress('nothing'), isNull);
  });

  test('ffmpeg progress', () {
    expect(
      parseFfmpegProgress(
        'frame=1\nout_time_us=5000000\n',
        const Duration(seconds: 10),
      ),
      0.5,
    );
    expect(parseFfmpegProgress('out_time_us=1', Duration.zero), isNull);
  });

  test('every preset has both backends', () {
    for (final p in convertPresets) {
      expect(p.avconvert, isNotEmpty);
      expect(p.ffmpeg, isNotEmpty);
    }
  });
}
