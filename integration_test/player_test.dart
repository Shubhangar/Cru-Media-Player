// Drives the real app (real mpv playback) with key and mouse events.
// Run:  tool/run_integration_test.sh   (or see that script for the command)
import 'dart:io';

import 'package:cone_player/player/player_controller.dart';
import 'package:cone_player/theme.dart';
import 'package:cone_player/ui/player_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

const fixtures = String.fromEnvironment('FIXTURES');

/// Optional: `--dart-define=SHOTS=<dir>` saves window screenshots (macOS
/// only; macOS may ask for screen-recording permission the first time).
const shots = String.fromEnvironment('SHOTS');

Future<void> snap(WidgetTester tester, String name) async {
  if (shots.isEmpty || !Platform.isMacOS) return;
  await Future<void>.delayed(const Duration(milliseconds: 250));
  await tester.pump();
  final b = await windowManager.getBounds();
  await Process.run('screencapture', [
    '-x',
    '-R${b.left.round()},${b.top.round()},${b.width.round()},${b.height.round()}',
    '$shots/$name.png',
  ]);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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

  Future<void> settle(WidgetTester tester, [int ms = 300]) async {
    await Future<void>.delayed(Duration(milliseconds: ms));
    await tester.pump();
  }

  testWidgets('core player flows', (tester) async {
    expect(fixtures, isNotEmpty, reason: 'pass --dart-define=FIXTURES=<dir>');
    MediaKit.ensureInitialized();
    await windowManager.ensureInitialized();

    final c = PlayerController();
    final p = c.player;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildConeTheme(),
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
}
