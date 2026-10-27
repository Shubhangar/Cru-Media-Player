// Phase 5: multi-view sync grid and floating feeds.
import 'dart:io';

import 'package:cone_player/library/library_store.dart';
import 'package:cone_player/player/multiview.dart';
import 'package:cone_player/player/player_controller.dart';
import 'package:cone_player/player/settings_store.dart';
import 'package:cone_player/settings/prefs.dart';
import 'package:cone_player/theme.dart';
import 'package:cone_player/ui/multiview_view.dart';
import 'package:cone_player/ui/player_screen.dart';
import 'package:cone_player/ui/seek_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';
import 'test_window.dart';

final testPrefix = 'test${DateTime.now().microsecondsSinceEpoch}.';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUpAll(() async => tmp = await Directory.systemTemp.createTemp('cone_mv'));
  tearDownAll(() async {
    await tmp.delete(recursive: true);
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys().where((k) => k.startsWith(testPrefix))) {
      await prefs.remove(k);
    }
  });

  testWidgets('feeds follow the master and can float', (tester) async {
    MediaKit.ensureInitialized();
    await prepareTestWindow();
    final angle = File(fixture('test-clip.mp4'))
        .copySync('${tmp.path}${Platform.pathSeparator}Angle B.mp4')
        .path;
    final lib = LibraryStore(
      Directory('${tmp.path}${Platform.pathSeparator}store'),
    );
    final c = PlayerController(
      settings: SettingsStore(prefix: testPrefix),
      library: lib,
    );
    Prefs.onboarded.set(c.settings, true);
    final p = c.player;
    await tester.binding.setSurfaceSize(const Size(1280, 760));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildConeTheme(),
        builder: withShotBoundary,
        home: PlayerScreen(
          controller: c,
          library: lib,
          initialFiles: [fixture('test-clip.mp4')],
        ),
      ),
    );
    await waitFor(tester, () => p.state.duration > Duration.zero, what: 'load');
    await p.pause();
    await settle(tester);

    // Add a feed through the dialog: "From queue" needs a 2nd item, so use
    // the engine directly for the file and the UI for everything else.
    final screen = tester.state(find.byType(PlayerScreen));
    final mv = (screen as dynamic).debugMultiView as MultiView;
    // Pump while adding: the feed's tile must mount before media opens.
    final adding = mv.addFeed(angle);
    await waitFor(
      tester,
      () =>
          mv.feeds.isNotEmpty &&
          mv.feeds.single.player.state.duration > Duration.zero,
      what: 'feed opened',
    );
    await adding;
    await settle(tester, 800);
    expect(find.byType(MultiViewGrid), findsOneWidget);
    expect(find.text('Angle B.mp4'), findsOneWidget);
    final feed = mv.feeds.single;
    await waitFor(
      tester,
      () => feed.player.state.duration > Duration.zero,
      what: 'feed loaded',
    );

    // Play/pause follow the master.
    await tester.tap(find.byTooltip('Play / pause all (Space)'));
    await waitFor(tester, () => feed.player.state.playing, what: 'feed plays');
    await settle(tester, 1200);
    expect(mv.drift(feed), lessThan(const Duration(milliseconds: 400)));
    // The feed's tile shows real video (the clip is never pure black).
    final tile = tester.getRect(
      find
          .ancestor(of: find.text('Angle B.mp4'), matching: find.byType(Stack))
          .first,
    );
    expect(
      await meanBrightness(tester, tile.deflate(30)),
      greaterThan(20),
      reason: 'feed video must render',
    );
    await snap(tester, 'p5-9-multiview-grid');

    // A seek on the master carries over; offset shifts the feed.
    await p.seek(const Duration(seconds: 8));
    await settle(tester, 900);
    expect(mv.drift(feed), lessThan(const Duration(milliseconds: 500)));
    for (var i = 0; i < 20; i++) {
      await tester.tap(
        find.descendant(
          of: find.byType(MultiViewGrid),
          matching: find.byTooltip('Later'),
        ),
      );
    }
    await settle(tester, 1200);
    expect(feed.offset, closeTo(2.0, 0.01));
    expect(mv.drift(feed), lessThan(const Duration(milliseconds: 500)));
    expect(
      feed.player.state.position - p.state.position,
      greaterThan(const Duration(milliseconds: 1500)),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await waitFor(
      tester,
      () => !feed.player.state.playing,
      what: 'feed pauses',
    );

    // Each tile has its own seek bar (shown on hover). Scrubbing a synced
    // feed re-aligns it: the jump becomes its offset.
    expect(
      find.descendant(
        of: find.byType(MultiViewGrid),
        matching: find.byType(SeekBar),
      ),
      findsNWidgets(3),
    );
    await mv.seekFeed(feed, p.state.position + const Duration(seconds: 5));
    await settle(tester, 900);
    expect(feed.offset, closeTo(5.0, 0.15));
    expect(mv.drift(feed), lessThan(const Duration(milliseconds: 500)));

    // Audio focus: listening to the feed mutes the main video.
    Finder inGrid(Finder f) =>
        find.descendant(of: find.byType(MultiViewGrid), matching: f);
    await tester.tap(inGrid(find.byTooltip('Listen to this')).last);
    await settle(tester);
    expect(p.state.volume, 0);
    expect(feed.player.state.volume, greaterThan(0));
    await tester.tap(inGrid(find.byTooltip('Listen to this')).first);
    await settle(tester);
    expect(p.state.volume, greaterThan(0));
    expect(feed.player.state.volume, 0);

    // Esc floats the feed over the player; it can be dragged.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester, 400);
    expect(mv.mode, MultiMode.floating);
    expect(find.byType(MultiViewGrid), findsNothing);
    final before = feed.floatPos;
    await tester.drag(find.text('Angle B.mp4'), const Offset(200, 120));
    await settle(tester);
    expect(feed.floatPos.dx, greaterThan(before.dx + 100));
    await snap(tester, 'p5-10-multiview-float');

    await mv.closeAll();
    await settle(tester);
    expect(mv.feeds, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(lib.save);
  });
}
