import 'dart:io';

import 'package:cone_player/library/library_store.dart';
import 'package:cone_player/library/m3u.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('m3u', () {
    test('parses extended entries with attributes', () {
      const text = '''#EXTM3U
#EXTINF:-1 tvg-id="a" tvg-logo="http://x/logo.png" group-title="News",Channel, One
http://example.com/one.m3u8
#EXTINF:-1 group-title="Sports",Two
two.ts
plain-three.mp4
''';
      final c = parseM3u(text, base: Uri.parse('http://example.com/list.m3u'));
      expect(c, hasLength(3));
      expect(c[0].name, 'Channel, One'.split(',').last.trim());
      expect(c[0].group, 'News');
      expect(c[0].logo, 'http://x/logo.png');
      expect(c[1].url, 'http://example.com/two.ts');
      expect(c[1].group, 'Sports');
      expect(c[2].name, 'plain-three.mp4');
      expect(c[2].group, '');
    });

    test('local playlists: absolute entries kept, relative ones resolved', () {
      final c = parseM3u(
        '/media/a.mp4\nsub/b.mp4\nC:\\TV\\c.mp4\n',
        base: playlistBase('/media/lists/tv.m3u'),
      );
      expect(c.map((e) => e.url), [
        '/media/a.mp4',
        '/media/lists/sub/b.mp4',
        r'C:\TV\c.mp4',
      ]);
      expect(isLocalPath(r'D:\a\tv.m3u'), isTrue);
      expect(isLocalPath('D:/a/tv.m3u'), isTrue);
      expect(isLocalPath(r'\\nas\tv.m3u'), isTrue);
      expect(isLocalPath('http://x/tv.m3u'), isFalse);
      expect(playlistBase(r'D:\a\tv.m3u')!.scheme, 'file');
    });

    test('comma inside quoted attribute is not the name separator', () {
      final c = parseM3u('#EXTINF:-1 group-title="A, B",Name\nhttp://h/x');
      expect(c.single.name, 'Name');
      expect(c.single.group, 'A, B');
    });
  });

  group('library store', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('cone'));
    tearDown(() async => tmp.delete(recursive: true));

    test('history marks finished items watched and orders by recency', () {
      final s = LibraryStore(tmp);
      s.recordProgress(
        '/a.mp4',
        title: 'A',
        position: const Duration(minutes: 5),
        duration: const Duration(minutes: 60),
        isAudio: false,
      );
      expect(s.history['/a.mp4']!.resumable, isTrue);
      s.recordProgress(
        '/b.mp4',
        title: 'B',
        position: const Duration(minutes: 58),
        duration: const Duration(minutes: 60),
        isAudio: false,
      );
      expect(s.history['/b.mp4']!.watched, isTrue);
      expect(s.recent().first.uri, '/b.mp4');
      expect(s.recent(unfinishedOnly: true).map((h) => h.uri), ['/a.mp4']);
    });

    test('short clips are not marked watched early', () {
      final s = LibraryStore(tmp);
      s.recordProgress(
        '/short.mp4',
        title: 'S',
        position: const Duration(seconds: 10),
        duration: const Duration(seconds: 20),
        isAudio: false,
      );
      final h = s.history['/short.mp4']!;
      expect(h.watched, isFalse);
      expect(h.resumable, isTrue);
    });

    test('persists and reloads everything', () async {
      final s = LibraryStore(tmp);
      s.recordProgress(
        '/a.mp4',
        title: 'A',
        position: const Duration(seconds: 30),
        duration: const Duration(minutes: 10),
        isAudio: false,
      );
      final p = s.createPlaylist('Mix', ['/a.mp4']);
      s.togglePin(Pin('Mix', p.id, PinKind.playlist));
      s.addFolder('/movies', FolderKind.video);
      await s.save();

      final r = LibraryStore(tmp);
      await r.load();
      expect(r.history['/a.mp4']!.positionMs, 30000);
      expect(r.playlists.single.items, ['/a.mp4']);
      expect(r.isPinned(p.id), isTrue);
      expect(r.folders.single.kind, FolderKind.video);
    });

    test('loads channels from a local m3u source', () async {
      final f = File('${tmp.path}/tv.m3u')
        ..writeAsStringSync('#EXTINF:-1,Local\nhttp://h/live.m3u8\n');
      final s = LibraryStore(tmp);
      final src = await s.addSource(f.path, name: 'TV');
      expect(src.channels.single.name, 'Local');
      expect(src.error, isNull);
    });

    test('scanner finds media by kind and skips hidden folders', () async {
      File('${tmp.path}/a.mp4').writeAsStringSync('x');
      File('${tmp.path}/b.mp3').writeAsStringSync('x');
      Directory('${tmp.path}/.hidden').createSync();
      File('${tmp.path}/.hidden/c.mp4').writeAsStringSync('x');
      final v = await scanFolder(tmp.path, kind: FolderKind.video);
      expect(v.map((m) => m.name), ['a']);
      final all = await scanFolder(tmp.path);
      expect(all, hasLength(2));
    });
  });

  test('displayName strips folders and extensions but not URLs', () {
    expect(displayName('/x/My%20Movie.mkv'), 'My Movie');
    expect(displayName('http://h/live/stream.m3u8'), 'stream.m3u8');
  });
}
