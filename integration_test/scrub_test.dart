// Phase 4: seek-bar frame previews and waveforms.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cone_player/library/library_store.dart';
import 'package:cone_player/player/frame_previewer.dart';
import 'package:cone_player/player/models.dart';
import 'package:cone_player/player/player_controller.dart';
import 'package:cone_player/player/settings_store.dart';
import 'package:cone_player/settings/prefs.dart';
import 'package:cone_player/player/waveform.dart';
import 'package:cone_player/theme.dart';
import 'package:cone_player/ui/music_view.dart';
import 'package:cone_player/ui/player_screen.dart';
import 'package:cone_player/ui/seek_bar.dart';
import 'package:cone_player/ui/subtitle_timeline.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
  setUpAll(() async => tmp = await Directory.systemTemp.createTemp('cone_s'));
  tearDownAll(() async {
    await tmp.delete(recursive: true);
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys().where((k) => k.startsWith(testPrefix))) {
      await prefs.remove(k);
    }
  });

  testWidgets('frame previews and waveforms', (tester) async {
    MediaKit.ensureInitialized();
    await windowManager.ensureInitialized();
    final lib = LibraryStore(
      Directory('${tmp.path}${Platform.pathSeparator}store'),
    );
    final c = PlayerController(
      settings: SettingsStore(prefix: testPrefix),
      library: lib,
      waveforms: WaveformService(
        Directory('${tmp.path}${Platform.pathSeparator}waves'),
      ),
    );
    Prefs.onboarded.set(c.settings, true);
    final p = c.player;
    final previewer = FramePreviewer();
    await tester.binding.setSurfaceSize(const Size(1280, 760));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildConeTheme(),
        builder: withShotBoundary,
        home: PlayerScreen(
          controller: c,
          library: lib,
          previewer: previewer,
          initialFiles: [fixture('test-clip.mp4')],
        ),
      ),
    );
    await waitFor(
      tester,
      () => p.state.duration > Duration.zero,
      what: 'loaded',
    );
    await p.pause();
    await settle(tester);

    // --- Hover preview -------------------------------------------------------
    final bar = find.byType(SeekBar);
    final box = tester.getRect(bar);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: box.centerLeft + const Offset(40, 0));
    await mouse.moveTo(box.center);
    await waitFor(
      tester,
      () => find.byKey(const ValueKey('seek-preview')).evaluate().isNotEmpty,
      what: 'preview frame',
    );
    expect(find.text('00:10'), findsWidgets); // bubble time at the middle
    // The preview is the frame at the hovered time, not the first frame.
    await waitFor(
      tester,
      () =>
          previewer.lastFrameAt != null &&
          (previewer.lastFrameAt! - const Duration(seconds: 10)).abs() <
              const Duration(seconds: 2),
      what: 'preview near 00:10 (got ${previewer.lastFrameAt})',
    );
    // The frame must be real video, not black: the clip's background is a
    // coloured fill, so average brightness is well above zero.
    final img = tester.widget<Image>(
      find.byKey(const ValueKey('seek-preview')),
    );
    final bytes = (img.image as ResizeImage).imageProvider as MemoryImage;
    final decoded = await tester.runAsync(
      () => decodeImageFromList(bytes.bytes),
    );
    final rgba = await tester.runAsync(
      () => decoded!.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    var sum = 0;
    for (var i = 0; i < rgba!.lengthInBytes; i += 4) {
      sum += rgba.getUint8(i) + rgba.getUint8(i + 1) + rgba.getUint8(i + 2);
    }
    final mean = sum / (rgba.lengthInBytes / 4 * 3);
    expect(mean, greaterThan(20), reason: 'preview frame is not black');
    await settle(tester, 500);
    await snap(tester, 'p4-1-preview');
    await mouse.moveTo(box.center + const Offset(0, -300));
    await mouse.removePointer();

    // --- Waveform overlay on the seek bar -----------------------------------
    c.setOverlay(waveform: true);
    await waitFor(
      tester,
      () => c.waveform != null,
      what: 'waveform built',
      timeout: const Duration(seconds: 20),
    );
    await settle(tester);
    expect(
      find.descendant(
        of: find.byType(SeekBar),
        matching: find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is WaveformPainter,
        ),
      ),
      findsOneWidget,
    );
    expect(c.waveform!.peaks.length, WaveformService.buckets);
    await snap(tester, 'p4-2-waveform');
    // Cached on disk for next time.
    expect(
      Directory('${tmp.path}${Platform.pathSeparator}waves')
          .listSync()
          .where((e) => e.path.endsWith('.peaks')),
      hasLength(1),
    );

    // --- Subtitle timeline: drag to re-sync ---------------------------------
    await p.seek(const Duration(seconds: 3));
    c.setOverlay(subtitleTimeline: true);
    await waitFor(tester, () => c.cues != null, what: 'cues from sidecar');
    expect(c.cues!.map((e) => e.text), [
      'Hello from Cone Player',
      'Second subtitle line',
    ]);
    await settle(tester);
    final tl = find.byType(SubtitleTimeline);
    expect(tl, findsOneWidget);
    // Subtitles move up further to clear the taller bar.
    expect(
      int.parse(await (p.platform as NativePlayer).getProperty('sub-margin-y')),
      greaterThan(180),
    );
    await snap(tester, 'p4-4-timeline');
    final r = tester.getRect(tl);
    final pxPerSec = r.width / 30; // default 30 s window
    await tester.dragFrom(r.center, Offset(pxPerSec * 2, 0));
    await settle(tester);
    final delay = double.parse(
      await (p.platform as NativePlayer).getProperty('sub-delay'),
    );
    expect(delay, closeTo(2.0, 0.3));
    expect(c.subDelay, closeTo(delay, 0.01));
    await snap(tester, 'p4-5-timeline-dragged');
    await tester.tap(find.byTooltip('Reset delay'));
    await settle(tester);
    expect(c.subDelay, 0);
    c.setOverlay(subtitleTimeline: false);

    // --- Subtitle style is what is actually drawn (mpv/libass) -------------
    bool yellow(int r, int g, int b) => r > 200 && g > 170 && b < 130;
    await p.seek(const Duration(seconds: 2)); // "Hello from Cone Player"
    await settle(tester, 700);
    final whiteBaseline = await countPixels(tester, yellow);
    await c.setSubStyle(
      builtInSubtitleStyles.firstWhere((s) => s.name == 'Cinema yellow').style,
    );
    await p.seek(const Duration(seconds: 2, milliseconds: 100));
    await settle(tester, 700);
    final yellowPixels = await countPixels(tester, yellow);
    expect(
      yellowPixels,
      greaterThan(whiteBaseline + 300),
      reason:
          'yellow subtitle text must be rendered '
          '(baseline $whiteBaseline, now $yellowPixels)',
    );
    await snap(tester, 'p4-7-yellow-subs');
    await c.setSubStyle(builtInSubtitleStyles.first.style);

    // --- Music: tall waveform scrubber -------------------------------------
    c.setOverlay(waveform: false);
    await c.openAll([fixture('test-song.m4a')]);
    await waitFor(tester, () => c.isAudioOnly, what: 'music');
    await waitFor(
      tester,
      () => find
          .descendant(
            of: find.byType(MusicView),
            matching: find.byWidgetPredicate(
              (w) => w is CustomPaint && w.painter is WaveformPainter,
            ),
          )
          .evaluate()
          .isNotEmpty,
      what: 'music waveform',
    );
    // Tapping the waveform seeks.
    final wave = tester.getRect(
      find.descendant(
        of: find.byType(MusicView),
        matching: find.byType(SeekBar),
      ),
    );
    await tester.tapAt(wave.centerLeft + Offset(wave.width * 0.75, 0));
    await waitFor(
      tester,
      () => p.state.position >= const Duration(seconds: 5),
      what: 'seek from waveform',
    );
    await settle(tester, 400);
    await snap(tester, 'p4-3-music-wave');
    // Dispose the screen and let pending library writes finish before the
    // temp folder is removed.
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(lib.save);
  });
}
