import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cone_player/player/opensubtitles.dart';
import 'package:flutter_test/flutter_test.dart';

/// Independent reference: straightforward BigInt over the whole chunks.
String _referenceHash(Uint8List bytes) {
  BigInt sum(Uint8List b) {
    var s = BigInt.zero;
    for (var i = 0; i + 8 <= b.length; i += 8) {
      var w = BigInt.zero;
      for (var k = 7; k >= 0; k--) {
        w = (w << 8) | BigInt.from(b[i + k]);
      }
      s += w;
    }
    return s;
  }

  const chunk = 65536;
  final head = bytes.sublist(0, chunk);
  final tail = bytes.sublist(bytes.length - chunk);
  final h =
      (BigInt.from(bytes.length) + sum(head) + sum(tail)) &
      ((BigInt.one << 64) - BigInt.one);
  return h.toRadixString(16).padLeft(16, '0');
}

void main() {
  test('movie hash matches the reference algorithm', () async {
    final dir = await Directory.systemTemp.createTemp('oshash');
    final bytes = Uint8List(300000);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = (i * 2654435761) & 0xFF; // overflow-heavy pattern
    }
    final f = File('${dir.path}/m.bin')..writeAsBytesSync(bytes);
    expect(openSubtitlesHash(f.path), _referenceHash(bytes));
    expect(openSubtitlesHash(f.path), hasLength(16));
    await dir.delete(recursive: true);
  });

  test('search parses results and ranks hash matches first', () async {
    late Uri seen;
    late Map<String, String> headers;
    final client = OpenSubtitlesClient(
      'KEY',
      fetch: (m, url, h, [b]) async {
        seen = url;
        headers = h;
        return (
          200,
          jsonEncode({
            'data': [
              {
                'attributes': {
                  'language': 'en',
                  'release': 'Popular.Release',
                  'download_count': 900,
                  'moviehash_match': false,
                  'files': [
                    {'file_id': 1, 'file_name': 'a.srt'},
                  ],
                },
              },
              {
                'attributes': {
                  'language': 'en',
                  'release': 'Exact.Match',
                  'download_count': 10,
                  'moviehash_match': true,
                  'hearing_impaired': true,
                  'files': [
                    {'file_id': 2, 'file_name': 'b.srt'},
                  ],
                },
              },
            ],
          }),
        );
      },
    );
    final r = await client.search(
      hash: 'abc',
      query: 'Movie',
      languages: 'en, de',
    );
    expect(seen.queryParameters, {
      'moviehash': 'abc',
      'query': 'Movie',
      'languages': 'en,de',
    });
    expect(headers['Api-Key'], 'KEY');
    expect(r.map((e) => e.release), ['Exact.Match', 'Popular.Release']);
    expect(r.first.hearingImpaired, isTrue);
  });

  test('download follows the link and saves the file', () async {
    final dir = await Directory.systemTemp.createTemp('osdl');
    final client = OpenSubtitlesClient(
      'KEY',
      fetch: (m, url, h, [b]) async {
        if (m == 'POST') {
          expect(jsonDecode(b!), {'file_id': 7});
          return (200, jsonEncode({'link': 'https://dl.example/x.srt'}));
        }
        return (200, '1\n00:00:01,000 --> 00:00:02,000\nHi\n');
      },
    );
    const r = SubtitleResult(
      fileId: 7,
      fileName: 'x.srt',
      language: 'en',
      release: 'r',
      downloads: 1,
      hearingImpaired: false,
      hashMatch: true,
    );
    final path = await client.download(r, '${dir.path}/movie.en.srt');
    expect(File(path).readAsStringSync(), contains('Hi'));
    await dir.delete(recursive: true);
  });

  test('rejected key gives a readable error', () async {
    final client = OpenSubtitlesClient(
      'BAD',
      fetch: (m, url, h, [b]) async => (401, '{"message":"Invalid API key"}'),
    );
    expect(
      () => client.search(query: 'x'),
      throwsA(
        isA<OpenSubtitlesException>().having(
          (e) => e.message,
          'message',
          contains('rejected the API key'),
        ),
      ),
    );
  });
}
