import 'package:cone_player/player/subtitles.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('srt with tags and multi-line text', () {
    final c = parseSrtOrVtt('''1
00:00:01,000 --> 00:00:04,500
<i>Hello</i> there

2
00:01:02,250 --> 00:01:05,000
Line one
Line two
''');
    expect(c, hasLength(2));
    expect(c[0].start, const Duration(seconds: 1));
    expect(c[0].end, const Duration(seconds: 4, milliseconds: 500));
    expect(c[0].text, 'Hello there');
    expect(
      c[1].start,
      const Duration(minutes: 1, seconds: 2, milliseconds: 250),
    );
    expect(c[1].text, 'Line one\nLine two');
  });

  test('webvtt with short timestamps and settings', () {
    final c = parseSrtOrVtt('''WEBVTT

00:05.000 --> 00:07.500 align:start
<c.yellow>Short</c> form

01:00:00.000 --> 01:00:02.000
Long form
''');
    expect(c.map((e) => e.text), ['Short form', 'Long form']);
    expect(c[0].start, const Duration(seconds: 5));
    expect(c[1].start, const Duration(hours: 1));
  });

  test('ass dialogue with commas and override tags', () {
    final c = parseAss(r'''[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:03.50,0:00:05.00,Default,,0,0,0,,{\an8}Wait, what?\NNo way
''');
    expect(c.single.start, const Duration(seconds: 3, milliseconds: 500));
    expect(c.single.end, const Duration(seconds: 5));
    expect(c.single.text, 'Wait, what?\nNo way');
  });

  test('loads the sidecar fixture', () async {
    final c = await loadCues('integration_test/fixtures/test-clip.srt');
    expect(c!.map((e) => e.text), [
      'Hello from Cone Player',
      'Second subtitle line',
    ]);
  });
}
