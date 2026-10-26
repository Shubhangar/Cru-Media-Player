// Drives the real app (real mpv playback) with key and mouse events.
// Run:  tool/run_integration_test.sh   (or see that script for the command)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cone_player/player/player_controller.dart';
import 'package:cone_player/player/settings_store.dart';
import 'package:cone_player/ui/inspector/inspector_panel.dart';
import 'package:cone_player/theme.dart';
import 'package:cone_player/ui/player_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

const fixtures = String.fromEnvironment('FIXTURES');

/// Optional: `--dart-define=SHOTS=<dir>` saves PNGs of the Flutter UI
/// (rendered in-process, so no OS screen-recording permission is needed;
/// the video texture itself shows as black).
const shots = String.fromEnvironment('SHOTS');
final shotKey = GlobalKey();

Future<void> snap(WidgetTester tester, String name) async {
  if (shots.isEmpty) return;
  await tester.pump();
  final boundary =
      shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1.5);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  await File('$shots/$name.png').writeAsBytes(png!.buffer.asUint8List());
}

/// Tests use their own preferences namespace, removed afterwards.
final testPrefix = 'test${DateTime.now().microsecondsSinceEpoch}.';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  tearDownAll(() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys().where((k) => k.startsWith(testPrefix))) {
      await prefs.remove(k);
    }
  });

  Future<void> waitFor(
    WidgetTester tester,
    bool Function() cond, {
    Duration timeout = const Duration(seconds: 10),
    String what = 'condition',
  }) async {
    final end = DateTime.now().add(timeout);
    while (!cond()) {
      if (DateTime.now().isAfter(end)) fail('Timed out waiting for $what');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    }
  }

  /// Renders a frame (starting any animations), waits, then renders again.
  Future<void> settle(WidgetTester tester, [int ms = 300]) async {
    await tester.pump();
    await Future<void>.delayed(Duration(milliseconds: ms));
    await tester.pump();
  }

  testWidgets('core player flows', (tester) async {
    expect(fixtures, isNotEmpty, reason: 'pass --dart-define=FIXTURES=<dir>');
    MediaKit.ensureInitialized();
    await windowManager.ensureInitialized();

    final c = PlayerController(settings: SettingsStore(prefix: testPrefix));
    final p = c.player;
    await tester.binding.setSurfaceSize(const Size(1280, 760));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildConeTheme(),
        builder: (context, child) =>
            RepaintBoundary(key: shotKey, child: child),
        home: PlayerScreen(
          initialFiles: ['$fixtures/test-clip.mp4'],
          controller: c,
        ),
      ),
    );

    // --- Opens and plays ------------------------------------------------
    await waitFor(
      tester,
      () => p.state.playing && p.state.duration > Duration.zero,
      what: 'playback to start',
    );
    expect(p.state.duration.inSeconds, inInclusiveRange(19, 20));

    // --- Space pauses and the OSD shows action + key ---------------------
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await waitFor(tester, () => !p.state.playing, what: 'pause');
    await tester.pump();
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Space'), findsOneWidget);
    await snap(tester, '1-paused-osd');

    // Paused -> both bars visible, subtitles lifted clear of the bottom bar.
    expect(
      await (p.platform as NativePlayer).getProperty('sub-margin-y'),
      '100',
    );
    expect(find.byTooltip('Subtitles'), findsOneWidget);
    expect(find.byTooltip('Menu'), findsOneWidget);

    // --- Arrow seeks ------------------------------------------------------
    final before = p.state.position;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await waitFor(
      tester,
      () => p.state.position >= before + const Duration(seconds: 4),
      what: 'seek +5s',
    );

    // --- Ctrl/Cmd+B bookmarks --------------------------------------------
    final mod = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(mod);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(mod);
    await tester.pump();
    expect(c.bookmarks, hasLength(1));
    expect(find.textContaining('Bookmark at'), findsOneWidget);

    // --- Speed, volume, mute ---------------------------------------------
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await waitFor(
      tester,
      () => (p.state.rate - 1.1).abs() < 0.01,
      what: 'rate 1.1',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await waitFor(tester, () => p.state.rate == 1.0, what: 'rate reset');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await waitFor(
      tester,
      () => p.state.volume.round() == 95,
      what: 'volume 95',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await waitFor(tester, () => p.state.volume == 0, what: 'mute');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await waitFor(tester, () => p.state.volume.round() == 95, what: 'unmute');

    // --- Subtitle flyout lists tracks (sidecar .srt auto-loaded) ----------
    await tester.tap(find.byTooltip('Subtitles'));
    await settle(tester);
    expect(find.text('Load subtitle file…'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    await snap(tester, '2-subtitle-flyout');
    expect(
      p.state.tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no'),
      isNotEmpty,
      reason: 'test-clip.srt next to the video should be picked up',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.text('Load subtitle file…'), findsNothing);

    // --- Audio flyout: tracks + output devices ---------------------------
    await tester.tap(find.byTooltip('Audio tracks & output'));
    await settle(tester);
    expect(find.text('AUDIO TRACK'), findsOneWidget);
    expect(find.text('OUTPUT DEVICE'), findsOneWidget);
    expect(find.text('System default'), findsOneWidget);
    await snap(tester, '3-audio-flyout');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);

    // --- Main menu --------------------------------------------------------
    await tester.tap(find.byTooltip('Menu'));
    await settle(tester);
    expect(find.text('Open network stream…'), findsOneWidget);
    await snap(tester, '4-main-menu');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);

    // --- Right-click context menu -> Hide UI ------------------------------
    final center = tester.getCenter(find.byType(PlayerScreen));
    await tester.tapAt(center, buttons: kSecondaryButton);
    await settle(tester);
    expect(find.text('Hide UI'), findsOneWidget);
    await snap(tester, '5-context-menu');
    await tester.tap(find.text('Hide UI'));
    await settle(tester);
    expect(c.uiHidden, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pump();
    expect(c.uiHidden, isFalse);

    // --- Queue panel ------------------------------------------------------
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is Tooltip && (w.message ?? '').startsWith('Queue'),
      ),
    );
    await settle(tester, 400);
    expect(find.text('test-clip.mp4'), findsWidgets);
    await snap(tester, '6-queue');

    // --- End of file: Space replays from the start ------------------------
    await p.seek(p.state.duration - const Duration(milliseconds: 500));
    await p.play();
    await waitFor(
      tester,
      () =>
          !p.state.playing &&
          p.state.position >=
              p.state.duration - const Duration(milliseconds: 300),
      what: 'end of file',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await waitFor(
      tester,
      () => p.state.playing && p.state.position < const Duration(seconds: 3),
      what: 'replay from start',
    );

    // Playing, cursor not near an edge -> bars hidden (non-interactive).
    await settle(tester, 400);
    expect(find.byTooltip('Subtitles').hitTestable(), findsNothing);
  });

  testWidgets('inspector panels drive mpv', (tester) async {
    MediaKit.ensureInitialized();
    await windowManager.ensureInitialized();
    final c = PlayerController(settings: SettingsStore(prefix: testPrefix));
    final p = c.player;
    final mpv = p.platform as NativePlayer;
    Future<String> prop(String n) => mpv.getProperty(n);

    await tester.binding.setSurfaceSize(const Size(1280, 760));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildConeTheme(),
        builder: (context, child) =>
            RepaintBoundary(key: shotKey, child: child),
        home: PlayerScreen(
          initialFiles: ['$fixtures/test-clip.mp4'],
          controller: c,
        ),
      ),
    );
    await waitFor(
      tester,
      () => p.state.duration > Duration.zero,
      what: 'file loaded',
    );
    await p.pause();
    await settle(tester);

    final panel = find.byType(InspectorPanel);
    final scrollable = find
        .descendant(of: panel, matching: find.byType(Scrollable))
        .first;
    // Build lazily-built rows, then scroll them into the panel's viewport.
    Future<void> reveal(Finder f) async {
      await tester.scrollUntilVisible(
        f,
        150,
        scrollable: scrollable,
        maxScrolls: 60,
      );
      await tester.ensureVisible(f);
      await settle(tester, 150);
    }

    Finder inPanel(Finder f) => find.descendant(of: panel, matching: f);

    // --- Open with Cmd/Ctrl+I --------------------------------------------
    final mod = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(mod);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyUpEvent(mod);
    await settle(tester, 400);
    expect(
      tester.widget<InspectorPanel>(panel).open,
      isTrue,
      reason: 'Cmd/Ctrl+I opens the inspector',
    );
    expect(inPanel(find.text('TIMING')), findsOneWidget);

    // --- Subtitles: delay stepper, preset, outline ------------------------
    await tester.tap(inPanel(find.byTooltip('Later')));
    await tester.tap(inPanel(find.byTooltip('Later')));
    await settle(tester);
    expect(double.parse(await prop('sub-delay')), closeTo(0.2, 0.001));
    await snap(tester, 'p2-1-subtitles');

    await reveal(inPanel(find.text('Large')));
    await tester.tap(inPanel(find.text('Large')));
    await settle(tester);
    expect(double.parse(await prop('sub-scale')), closeTo(1.4, 0.001));

    await reveal(inPanel(find.text('Exact')));
    await tester.tap(inPanel(find.text('Exact')));
    await settle(tester);
    expect(double.parse(await prop('sub-font-size')), 55);
    expect(double.parse(await prop('sub-scale')), closeTo(1, 0.001));

    // Typing in a text field must not trigger shortcuts (F = fullscreen).
    final lang = inPanel(find.byType(TextField));
    await reveal(lang);
    await tester.tap(lang);
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await settle(tester);
    expect(await windowManager.isFullScreen(), isFalse);
    await tester.enterText(lang, 'en,eng');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(await prop('slang'), contains('en'));

    // --- Audio: delay, EQ preset, parametric band ---------------------------
    await tester.tap(inPanel(find.text('Audio')));
    await settle(tester, 400);
    expect(inPanel(find.text('EQUALIZER')), findsOneWidget);
    await tester.tap(inPanel(find.byTooltip('Later')));
    await settle(tester);
    expect(double.parse(await prop('audio-delay')), closeTo(0.05, 0.001));

    await tester.tap(inPanel(find.text('Bass boost')));
    await settle(tester, 500);
    expect(c.eqEnabled, isTrue);
    expect(await prop('af'), contains('equalizer'));
    await snap(tester, 'p2-2-audio');

    await tester.tap(inPanel(find.text('Flat')));
    await settle(tester, 500);
    expect(await prop('af'), isNot(contains('equalizer')));

    // --- Video: preview a look, apply it; live slider ---------------------
    await tester.tap(inPanel(find.text('Video')));
    await settle(tester, 800);
    await tester.tap(inPanel(find.text('Grayscale')));
    await settle(tester);
    expect(
      double.parse(await prop('saturation')),
      0,
      reason: 'not applied until Apply',
    );
    await snap(tester, 'p2-3-video');
    await tester.tap(inPanel(find.text('Apply')));
    await settle(tester);
    expect(double.parse(await prop('saturation')), -100);

    await reveal(inPanel(find.text('Reset all')));
    await tester.tap(inPanel(find.text('Reset all')));
    await settle(tester);
    expect(double.parse(await prop('saturation')), 0);

    await reveal(inPanel(find.text('Sharp')));
    await tester.tap(inPanel(find.text('Sharp')));
    await settle(tester);
    expect(await prop('scale'), 'ewa_lanczossharp');
    expect(inPanel(find.text('Source 1280×720')), findsOneWidget);

    // Flips are a Flutter transform over the video.
    await reveal(inPanel(find.text('Flip horizontally')));
    await tester.tap(
      find.descendant(
        of: find
            .ancestor(
              of: inPanel(find.text('Flip horizontally')),
              matching: find.byType(Row),
            )
            .first,
        matching: find.byType(Switch),
      ),
    );
    await settle(tester);
    expect(c.adjust.hflip, isTrue);
    final flip = tester.widget<Transform>(
      find
          .ancestor(of: find.byType(Video), matching: find.byType(Transform))
          .first,
    );
    expect(flip.transform.storage[0], -1);

    // --- Playback: speed, sleep timer, metadata ---------------------------
    await tester.tap(inPanel(find.text('Playback')));
    await settle(tester, 400);
    await tester.tap(inPanel(find.text('1.5×')));
    await waitFor(
      tester,
      () => (p.state.rate - 1.5).abs() < 0.01,
      what: 'rate 1.5',
    );

    await reveal(inPanel(find.text('End of file')));
    await tester.tap(inPanel(find.text('End of file')));
    await settle(tester);
    expect(await prop('keep-open'), 'always');
    await reveal(inPanel(find.text('30 min')));
    await tester.tap(inPanel(find.text('30 min')));
    await settle(tester);
    expect(c.sleepRemaining!.inMinutes, inInclusiveRange(29, 30));
    expect(await prop('keep-open'), isNot('always'));
    await reveal(inPanel(find.text('Off')));
    await tester.tap(inPanel(find.text('Off')));
    await settle(tester);
    expect(c.sleepRemaining, isNull);

    await reveal(inPanel(find.text('h264')).first);
    expect(inPanel(find.text('h264')), findsWidgets);
    expect(inPanel(find.text('1280×720')), findsOneWidget);
    expect(inPanel(find.text('30 fps')), findsOneWidget);
    await snap(tester, 'p2-4-playback');

    // Close.
    await tester.tap(inPanel(find.byTooltip('Close')));
    await settle(tester, 400);
    expect(find.byType(InspectorPanel).hitTestable(), findsNothing);
  });
}
