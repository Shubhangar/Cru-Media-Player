import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cone_player/library/cover_art.dart';
import 'package:flutter_test/flutter_test.dart';

const _png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3];

List<int> _be32(int v) => [v >> 24 & 255, v >> 16 & 255, v >> 8 & 255, v & 255];
List<int> _syncsafe(int v) => [
  v >> 21 & 127,
  v >> 14 & 127,
  v >> 7 & 127,
  v & 127,
];

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('cover'));
  tearDown(() async => tmp.delete(recursive: true));

  test('m4a covr atom (fixture)', () async {
    final art = await findCoverArt('integration_test/fixtures/test-song.m4a');
    expect(art, isNotNull);
    expect(art!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]); // PNG
  });

  test('mp3 ID3v2.3 APIC frame', () async {
    final body = [
      0, // ISO-8859-1
      ...ascii.encode('image/png'), 0,
      3, // front cover
      ...ascii.encode('desc'), 0,
      ..._png,
    ];
    final frame = [
      ...ascii.encode('APIC'),
      ..._be32(body.length),
      0,
      0,
      ...body,
    ];
    final f = File('${tmp.path}/a.mp3')
      ..writeAsBytesSync([
        ...ascii.encode('ID3'), 3, 0, 0, ..._syncsafe(frame.length),
        ...frame,
        0xFF, 0xFB, // fake mpeg frame
      ]);
    expect(await findCoverArt(f.path), _png);
  });

  test('flac PICTURE block', () async {
    final mime = ascii.encode('image/png');
    final pic = [
      ..._be32(3),
      ..._be32(mime.length),
      ...mime,
      ..._be32(0),
      ...List.filled(16, 0),
      ..._be32(_png.length),
      ..._png,
    ];
    final f = File('${tmp.path}/a.flac')
      ..writeAsBytesSync([
        ...ascii.encode('fLaC'),
        0x00, 0, 0, 4, 1, 2, 3, 4, // STREAMINFO (truncated, not last)
        0x86, ..._be32(pic.length).sublist(1), ...pic, // PICTURE, last
      ]);
    expect(await findCoverArt(f.path), _png);
  });

  test('falls back to cover.jpg in the folder', () async {
    File('${tmp.path}/song.ogg').writeAsBytesSync(Uint8List(16));
    File('${tmp.path}/Cover.JPG').writeAsBytesSync([1, 2, 3]);
    expect(await findCoverArt('${tmp.path}/song.ogg'), [1, 2, 3]);
  });

  test('missing file returns null', () async {
    expect(await findCoverArt('${tmp.path}/nope.mp3'), isNull);
  });
}
