// Phase 3 flows: home hub, library, history/resume, IPTV, playlists, music.
import 'dart:io';

import 'package:cone_player/library/library_store.dart';
import 'package:cone_player/player/player_controller.dart';
import 'package:cone_player/player/settings_store.dart';
import 'package:cone_player/settings/prefs.dart';
import 'package:cone_player/theme.dart';
import 'package:cone_player/ui/home/home_view.dart';
import 'package:cone_player/ui/library/library_screen.dart';
import 'package:cone_player/ui/music_view.dart';
import 'package:cone_player/ui/player_screen.dart';
import 'package:cone_player/ui/resume_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'helpers.dart';

final testPrefix = 'test${DateTime.now().microsecondsSinceEpoch}.';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('cone_lib');
  });
  tearDownAll(() async {
    await tmp.delete(recursive: true);
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys().where((k) => k.startsWith(testPrefix))) {
      await prefs.remove(k);
    }
  });

  testWidgets('home, library, history, resume, streams, music', (tester) async {
    MediaKit.ensureInitialized();
    await windowManager.ensureInitialized();
    final lib = LibraryStore(Directory('${tmp.path}/store'));
    await lib.load();
    final c = PlayerController(
      settings: SettingsStore(prefix: testPrefix),
      library: lib,
    );
    Prefs.onboarded.set(c.settings, true);
    final p = c.player;
    final clip = fixture('test-clip.mp4');
    final song = fixture('test-song.m4a');

    await tester.binding.setSurfaceSize(const Size(1280, 760));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildConeTheme(),
        builder: withShotBoundary,
        home: PlayerScreen(controller: c, library: lib),
      ),
    );
    await settle(tester);

    // --- Empty home hub ---------------------------------------------------
    expect(find.byType(HomeView), findsOneWidget);
    expect(find.text('Drop media here to start'), findsOneWidget);
    await snap(tester, 'p3-1-home-empty');

    // --- Library: empty, then a folder, then play from it ----------------
    await pressMod(tester, LogicalKeyboardKey.keyL, shift: true);
    await settle(tester);
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.text('Your video library is empty'), findsOneWidget);

    lib.addFolder(fixtures, FolderKind.video);
    await settle(tester);
    await tester.tap(find.text('fixtures'));
    await waitFor(
      tester,
      () => find.text('test-clip').evaluate().isNotEmpty,
      what: 'scan results',
    );
    // Audio files are not listed under Videos.
    expect(find.text('test-song'), findsNothing);
    await tester.tap(find.byTooltip('Details'));
    await settle(tester);
    expect(find.text('Modified'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    await snap(tester, 'p3-2-library-detail');
    await tester.tap(find.byTooltip('Grid'));
    await settle(tester);
    await tester.tap(find.text('test-clip'));
    await waitFor(tester, () => p.state.playing, what: 'playback');
    await settle(tester);
    expect(find.byType(LibraryScreen), findsNothing);

    // --- History: progress + thumbnail are recorded -----------------------
    await p.seek(const Duration(seconds: 9));
    await waitFor(
      tester,
      () =>
          (lib.history[clip]?.positionMs ?? 0) > 9000 &&
          lib.history[clip]?.thumb != null,
      timeout: const Duration(seconds: 15),
      what: 'history entry with thumbnail',
    );
    expect(File(lib.history[clip]!.thumb!).existsSync(), isTrue);

    // --- Close media -> Continue watching on home --------------------------
    await pressMod(tester, LogicalKeyboardKey.keyW);
    await waitFor(
      tester,
      () => p.state.playlist.medias.isEmpty,
      what: 'media closed',
    );
    await settle(tester, 500);
    expect(find.text('Continue watching'), findsOneWidget);
    expect(find.text('test-clip'), findsOneWidget);
    expect(find.textContaining(' s left'), findsOneWidget);
    await snap(tester, 'p3-3-home-continue');

    // --- Reopen -> resume banner -> Enter resumes --------------------------
    final saved = lib.history[clip]!.positionMs;
    await tester.tap(find.text('test-clip'));
    await waitFor(tester, () => c.resumeOffer != null, what: 'resume offer');
    await settle(tester);
    expect(find.byType(ResumeBanner), findsOneWidget);
    expect(find.textContaining('Resume from'), findsOneWidget);
    await snap(tester, 'p3-4-resume');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await waitFor(
      tester,
      () => p.state.position.inMilliseconds >= saved - 1000,
      what: 'resumed position',
    );
    expect(find.byType(ResumeBanner), findsNothing);

    // --- IPTV: local M3U with groups; N zaps to the next channel ----------
    final m3u = File('${tmp.path}/tv.m3u')
      ..writeAsStringSync(
        '#EXTM3U\n'
        '#EXTINF:-1 group-title="Movies",Clip Channel\n$clip\n'
        '#EXTINF:-1 group-title="Radio",Song Channel\n$song\n',
      );
    await lib.addSource(m3u.path, name: 'Test TV');
    await pressMod(tester, LogicalKeyboardKey.keyL, shift: true);
    await settle(tester);
    await tester.tap(find.text('Network streams'));
    await settle(tester);
    await tester.tap(find.text('Test TV'));
    await settle(tester);
    expect(find.text('Clip Channel'), findsOneWidget);
    expect(find.text('Radio'), findsOneWidget); // group chip
    await snap(tester, 'p3-5-channels');
    await tester.tap(find.text('Clip Channel'));
    await waitFor(
      tester,
      () => c.currentUri == clip && p.state.playlist.medias.length == 2,
      what: 'channel queue',
    );
    c.dismissResume();
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await waitFor(tester, () => c.currentUri == song, what: 'next channel');

    // --- Music layout -----------------------------------------------------
    await waitFor(tester, () => c.isAudioOnly, what: 'audio-only detection');
    await waitFor(
      tester,
      () => find.text('Cone Test Tone').evaluate().isNotEmpty,
      what: 'track tags',
    );
    expect(find.text('NOW PLAYING'), findsOneWidget);
    expect(find.text('The Cones'), findsOneWidget);
    expect(find.text('Traffic Sessions'), findsOneWidget);
    expect(find.text('Track 2 of 2'), findsOneWidget);
    // Embedded cover art is read from the file and shown.
    await waitFor(
      tester,
      () => find
          .descendant(of: find.byType(MusicView), matching: find.byType(Image))
          .evaluate()
          .isNotEmpty,
      what: 'cover art',
    );
    await settle(tester, 600);
    await snap(tester, 'p3-6-music');

    // --- Save queue as playlist; it appears on home -------------------------
    lib.createPlaylist('Evening mix', c.queueUris);
    await pressMod(tester, LogicalKeyboardKey.keyW);
    await waitFor(
      tester,
      () => p.state.playlist.medias.isEmpty,
      what: 'closed',
    );
    await settle(tester, 400);
    expect(find.text('Evening mix'), findsOneWidget);
    expect(find.text('2 items'), findsOneWidget);

    // --- Drag from the queue panel's library tab into the queue -----------
    await tester.tap(find.text('Evening mix'));
    await waitFor(
      tester,
      () => p.state.playlist.medias.length == 2,
      what: 'playlist playing',
    );
    c.dismissResume();
    await pressMod(tester, LogicalKeyboardKey.keyL);
    await settle(tester, 400);
    await tester.tap(find.text('Library').last);
    await settle(tester, 600);
    final row = find.text('test-clip').last;
    await waitFor(
      tester,
      () => row.evaluate().isNotEmpty,
      what: 'library tab rows',
    );
    final drop = find.textContaining('Drag items here');
    final g = await tester.startGesture(tester.getCenter(row));
    await settle(tester, 50);
    for (var i = 1; i <= 8; i++) {
      final a = tester.getCenter(row), b = tester.getCenter(drop);
      await g.moveTo(Offset.lerp(a, b, i / 8)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await waitFor(
      tester,
      () => p.state.playlist.medias.length == 3,
      what: 'dragged item queued',
    );
    expect(
      p.state.playing || p.state.buffering,
      isTrue,
      reason: 'queueing must not interrupt playback',
    );

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(lib.save);
  });
}
