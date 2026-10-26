import 'dart:io';

import 'package:cone_player/player/subtitle_matching.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matches exact name, then language suffix, then episode', () {
    final subs = [
      '/s/Movie.srt',
      '/s/Other.en.srt',
      '/s/show.s01e03.en.srt',
      '/s/notes.txt',
    ];
    expect(matchOne('/v/Movie.mkv', subs), '/s/Movie.srt');
    expect(matchOne('/v/Other.mp4', subs), '/s/Other.en.srt');
    expect(
      matchOne('/v/Show - 1x03 - Pilot.mkv', subs),
      '/s/show.s01e03.en.srt',
    );
    expect(matchOne('/v/Unknown.mkv', subs), isNull);
  });

  test('batch match covers the queue', () {
    final m = matchSubtitles(
      ['/v/A.S02E01.mkv', '/v/A.S02E02.mkv', '/v/B.mkv'],
      ['/s/a_s02e02.srt', '/s/a_s02e01.srt'],
    );
    expect(m, {
      '/v/A.S02E01.mkv': '/s/a_s02e01.srt',
      '/v/A.S02E02.mkv': '/s/a_s02e02.srt',
    });
  });

  test('sidecar candidates include language variants and Subs/', () async {
    final d = await Directory.systemTemp.createTemp('side');
    File('${d.path}/Film.mkv').writeAsStringSync('');
    File('${d.path}/Film.en.srt').writeAsStringSync('');
    File('${d.path}/Film.de.ass').writeAsStringSync('');
    File('${d.path}/Other.srt').writeAsStringSync('');
    Directory('${d.path}/Subs').createSync();
    File('${d.path}/Subs/2_English.srt').writeAsStringSync('');
    final c = sidecarCandidates('${d.path}/Film.mkv')
        .map((p) => p.split('/').last)
        .toList();
    expect(c, unorderedEquals(['Film.en.srt', 'Film.de.ass', '2_English.srt']));
    await d.delete(recursive: true);
  });

  test('search query strips release noise', () {
    expect(
      queryFromFileName('/v/The.Big.Movie.2019.1080p.BluRay.x264.mkv'),
      'The Big Movie 2019',
    );
    expect(queryFromFileName('/v/home_video.mp4'), 'home video');
  });
}
