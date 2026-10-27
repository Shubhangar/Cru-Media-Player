import 'package:cone_player/player/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('trimNumber', () {
    expect(trimNumber('30.000000'), '30');
    expect(trimNumber('23.976024'), '23.976');
    expect(trimNumber('abc'), 'abc');
  });
  test('formatBytes', () {
    expect(formatBytes('512'), '512 B');
    expect(formatBytes('1722101'), '1.6 MB');
  });
  test('formatBitrate', () {
    expect(formatBitrate('96000'), '96 kbps');
    expect(formatBitrate('4500000'), '4.5 Mbps');
  });
  test('formatSeconds', () {
    expect(formatSeconds('20.085261'), '0:20');
    expect(formatSeconds('3725'), '1:02:05');
  });
  test('formatHz', () => expect(formatHz('44100'), '44.1 kHz'));
  test('stripNull', () => expect(stripNull('h264 ((null))'), 'h264'));
  test('parseTags', () {
    expect(parseTags('{"major_brand":"mp42","title":"X"}'), {
      'Major brand': 'mp42',
      'Title': 'X',
    });
    expect(parseTags('not json'), isEmpty);
  });
  test('nativeMediaPath', () {
    expect(nativeMediaPath('C:/v/a b.mp4', windows: true), r'C:\v\a b.mp4');
    expect(
      nativeMediaPath('//nas/share/a.mp4', windows: true),
      r'\\nas\share\a.mp4',
    );
    expect(
      nativeMediaPath('https://x/a.mp4', windows: true),
      'https://x/a.mp4',
    );
    expect(nativeMediaPath('/home/a.mp4', windows: false), '/home/a.mp4');
  });
}
