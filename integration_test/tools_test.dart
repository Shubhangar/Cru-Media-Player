// Phase 6: open & tools hub, capture, clipboard, convert, cast.
import 'dart:convert';
import 'dart:io';

import 'package:cone_player/library/library_store.dart';
import 'package:cone_player/player/player_controller.dart';
import 'package:cone_player/player/settings_store.dart';
import 'package:cone_player/settings/prefs.dart';
import 'package:cone_player/theme.dart';
import 'package:cone_player/tools/cast_session.dart';
import 'package:cone_player/ui/tools/tools_dialogs.dart';
import 'package:cone_player/ui/player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'helpers.dart';

final testPrefix = 'test${DateTime.now().microsecondsSinceEpoch}.';

const _description = '''<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0"><device>
<friendlyName>Living Room TV</friendlyName><serviceList><service>
<serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
<controlURL>/ctl</controlURL></service></serviceList></device></root>''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUpAll(
    () async => tmp = await Directory.systemTemp.createTemp('cone_tools'),
  );
  tearDownAll(() async {
    await tmp.delete(recursive: true);
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys().where((k) => k.startsWith(testPrefix))) {
      await prefs.remove(k);
    }
  });

  testWidgets('hub, capture, clipboard, convert, cast', (tester) async {
    MediaKit.ensureInitialized();
    await windowManager.ensureInitialized();
    final clip = File(fixture('test-clip.mp4'))
        .copySync('${tmp.path}${Platform.pathSeparator}Clip.mp4')
        .path;

    // A local HTTP "camera" and a fake DLNA renderer.
    final camera = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    camera.listen((r) async {
      r.response.headers.contentType = ContentType('video', 'mp4');
      await r.response.addStream(File(clip).openRead());
      await r.response.close();
    });
    final calls = <(String, String)>[];
    final renderer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    renderer.listen((r) async {
      if (r.uri.path == '/desc.xml') {
        r.response.write(_description);
      } else {
        final a = r.headers
            .value('soapaction')!
            .split('#')
            .last
            .replaceAll('"', '');
        calls.add((a, await utf8.decoder.bind(r).join()));
        r.response.write('<s:Envelope><s:Body/></s:Envelope>');
      }
      await r.response.close();
    });

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
        home: PlayerScreen(controller: c, library: lib, initialFiles: [clip]),
      ),
    );
    await waitFor(tester, () => p.state.duration > Duration.zero, what: 'load');
    await p.pause();
    await settle(tester);

    // --- Hub ------------------------------------------------------------------
    await pressMod(tester, LogicalKeyboardKey.keyT);
    await settle(tester, 400);
    for (final t in [
      'Open file', 'Open folder', 'Network stream', 'Capture device',
      'From clipboard', 'Convert', 'Cast', //
    ]) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    await snap(tester, 'p6-1-hub');

    // --- Capture (HTTP source, low latency) -------------------------------------
    await tester.tap(find.text('Capture device'));
    await settle(tester, 400);
    await tester.tap(find.text('HTTP'));
    final camUrl = 'http://127.0.0.1:${camera.port}/video';
    await tester.enterText(find.byType(TextField).last, camUrl);
    await snap(tester, 'p6-2-capture');
    await tester.tap(find.text('Connect'));
    await waitFor(
      tester,
      () => c.currentUri == camUrl && p.state.duration > Duration.zero,
      what: 'capture source playing',
    );
    expect(Prefs.captureSources.of(c.settings), camUrl);

    // --- Clipboard ---------------------------------------------------------------
    await Clipboard.setData(ClipboardData(text: 'watch this: $clip'));
    await pressMod(tester, LogicalKeyboardKey.keyT);
    await settle(tester, 400);
    await tester.tap(find.text('From clipboard'));
    await settle(tester, 400);
    expect(find.text(clip), findsOneWidget);
    await tester.tap(find.text('Play'));
    await waitFor(tester, () => c.currentUri == clip, what: 'clipboard play');
    await waitFor(
      tester,
      () => p.state.duration > Duration.zero,
      what: 'loaded',
    );
    await p.pause();

    // --- Convert (avconvert on macOS) --------------------------------------------
    if (Platform.isMacOS) {
      await pressMod(tester, LogicalKeyboardKey.keyT);
      await settle(tester, 400);
      await tester.tap(find.text('Convert').last);
      await waitFor(
        tester,
        () => find.text('MP4 · 720p (smaller)').evaluate().isNotEmpty,
        what: 'converter detected',
      );
      await tester.tap(find.text('MP4 · 720p (smaller)'));
      await settle(tester);
      expect(find.textContaining('Clip (mp4-720).mp4'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Convert'));
      await waitFor(
        tester,
        () => find.textContaining('Done:').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 60),
        what: 'conversion',
      );
      await snap(tester, 'p6-3-convert');
      final out = File(
        '${tmp.path}${Platform.pathSeparator}Clip (mp4-720).mp4',
      );
      expect(out.lengthSync(), greaterThan(10000));
      await tester.tap(find.text('Play result'));
      await waitFor(
        tester,
        () => c.currentUri == out.path,
        what: 'play result',
      );
      await waitFor(tester, () => p.state.height == 720, what: '720p output');
      await c.openAll([clip]);
      await waitFor(
        tester,
        () => p.state.duration > Duration.zero,
        what: 'reload',
      );
    }

    // --- Cast to a DLNA renderer ------------------------------------------------
    await p.play();
    final screen = tester.state(find.byType(PlayerScreen));
    final cast = (screen as dynamic).debugCast as CastSession;
    // Loopback URL so the in-process "TV" can fetch the file.
    showCastDialog(screen.context, c, cast, serveHost: '127.0.0.1');
    await settle(tester, 400);
    await tester.tap(find.text('Add by address…'));
    await settle(tester, 300);
    await tester.enterText(
      find.byType(TextField).last,
      'http://127.0.0.1:${renderer.port}/desc.xml',
    );
    await tester.tap(find.text('Add'));
    await waitFor(
      tester,
      () => find.text('Living Room TV').evaluate().isNotEmpty,
      what: 'device added',
    );
    await snap(tester, 'p6-4-cast-dialog');
    await tester.tap(find.widgetWithText(FilledButton, 'Cast'));
    await waitFor(tester, () => cast.active, what: 'casting');
    await settle(tester, 400);
    expect(p.state.playing, isFalse, reason: 'local playback pauses');
    expect(
      find.descendant(
        of: find.byType(CastPill),
        matching: find.textContaining('Casting to Living Room TV'),
      ),
      findsOneWidget,
    );
    expect(
      calls.map((c) => c.$1),
      containsAllInOrder(['SetAVTransportURI', 'Play']),
    );
    final url = RegExp(r'<CurrentURI>([^<]+)</CurrentURI>')
        .firstMatch(calls.first.$2)![1]!;
    final bytes = await tester.runAsync(() async {
      final h = HttpClient();
      final res = await (await h.getUrl(Uri.parse(url))).close();
      final n = await res.fold<int>(0, (a, b) => a + b.length);
      h.close();
      return n;
    });
    expect(bytes, File(clip).lengthSync());
    await snap(tester, 'p6-5-casting');
    await tester.tap(find.byTooltip('Stop casting'));
    await settle(tester, 500);
    expect(calls.last.$1, 'Stop');
    expect(
      find.descendant(
        of: find.byType(CastPill),
        matching: find.textContaining('Casting to'),
      ),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(lib.save);
    await camera.close(force: true);
    await renderer.close(force: true);
  });
}
