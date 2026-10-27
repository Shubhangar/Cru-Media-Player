// Phase 4: subtitle loader (sidecars, online search via a fake server).
import 'dart:convert';
import 'dart:io';

import 'package:cone_player/player/opensubtitles.dart';
import 'package:cone_player/player/player_controller.dart';
import 'package:cone_player/player/settings_store.dart';
import 'package:cone_player/settings/prefs.dart';
import 'package:cone_player/theme.dart';
import 'package:cone_player/ui/player_screen.dart';
import 'package:cone_player/ui/subtitle_loader.dart';
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
  setUpAll(() async => tmp = await Directory.systemTemp.createTemp('cone_sl'));
  tearDownAll(() async {
    await tmp.delete(recursive: true);
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys().where((k) => k.startsWith(testPrefix))) {
      await prefs.remove(k);
    }
  });

  testWidgets('sidecars and OpenSubtitles download', (tester) async {
    MediaKit.ensureInitialized();
    await windowManager.ensureInitialized();
    // Work on a copy so downloads land in the temp folder, not the repo.
    final clip = File(fixture('test-clip.mp4'))
        .copySync('${tmp.path}${Platform.pathSeparator}Clip.mp4')
        .path;
    File('${tmp.path}${Platform.pathSeparator}Clip.fr.srt')
        .writeAsStringSync('1\n00:00:01,000 --> 00:00:02,000\nBonjour\n');
    final c = PlayerController(settings: SettingsStore(prefix: testPrefix));
    Prefs.onboarded.set(c.settings, true);
    final p = c.player;
    await tester.binding.setSurfaceSize(const Size(1280, 760));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildConeTheme(),
        builder: withShotBoundary,
        home: PlayerScreen(controller: c, initialFiles: [clip]),
      ),
    );
    await waitFor(tester, () => p.state.duration > Duration.zero, what: 'load');
    await p.pause();
    final ctx = tester.element(find.byType(PlayerScreen));

    // --- This file: sidecar is listed and loads ----------------------------
    showSubtitleLoader(ctx, c);
    await settle(tester, 400);
    expect(find.text('Clip.fr.srt'), findsOneWidget);
    await tester.tap(find.text('Clip.fr.srt'));
    await settle(tester, 600);
    expect(
      await (p.platform as NativePlayer).getProperty(
        'current-tracks/sub/external-filename',
      ),
      endsWith('Clip.fr.srt'),
    );

    // --- Online: key prompt, search ranks exact match first, download ------
    final requests = <String>[];
    OpenSubtitlesClient fake(String key) => OpenSubtitlesClient(
      key,
      fetch: (method, url, headers, [body]) async {
        requests.add('$method ${url.path}');
        // The API gets the key; the final file link must not.
        if (url.host == 'api.opensubtitles.com') {
          expect(headers['Api-Key'], 'TESTKEY');
        } else {
          expect(headers.containsKey('Api-Key'), isFalse);
        }
        if (url.path.endsWith('/subtitles')) {
          expect(url.queryParameters['moviehash'], hasLength(16));
          return (
            200,
            jsonEncode({
              'data': [
                for (final (id, rel, hash) in [
                  (1, 'Some.Other.Cut', false),
                  (2, 'Clip.Exact.Release', true),
                ])
                  {
                    'attributes': {
                      'language': 'en',
                      'release': rel,
                      'download_count': 5,
                      'moviehash_match': hash,
                      'files': [
                        {'file_id': id, 'file_name': 'x.srt'},
                      ],
                    },
                  },
              ],
            }),
          );
        }
        if (method == 'POST') {
          return (200, jsonEncode({'link': 'https://dl.example/s.srt'}));
        }
        return (200, '1\n00:00:01,000 --> 00:00:03,000\nDownloaded line\n');
      },
    );
    showSubtitleLoader(ctx, c, initialTab: 2, clientFactory: fake);
    await settle(tester, 400);
    expect(find.textContaining('needs a free API key'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'TESTKEY');
    await tester.tap(find.text('Save key'));
    await settle(tester);
    expect(find.text('Clip'), findsOneWidget); // query from the file name
    await tester.tap(find.text('Search'));
    await waitFor(
      tester,
      () => find.text('Clip.Exact.Release').evaluate().isNotEmpty,
      what: 'results',
    );
    // Exact hash match is listed first.
    expect(
      tester.getTopLeft(find.text('Clip.Exact.Release')).dy,
      lessThan(tester.getTopLeft(find.text('Some.Other.Cut')).dy),
    );
    expect(find.text('Exact match'), findsOneWidget);
    await snap(tester, 'p4-6-opensubtitles');
    await tester.tap(find.text('Download').first);
    await waitFor(
      tester,
      () => c.assignedSubtitles[clip] != null,
      what: 'download assigned',
    );
    final saved = c.assignedSubtitles[clip]!;
    expect(saved, '${tmp.path}${Platform.pathSeparator}Clip.en.srt');
    expect(File(saved).readAsStringSync(), contains('Downloaded line'));
    expect(requests, [
      'GET /api/v1/subtitles',
      'POST /api/v1/download',
      'GET /s.srt',
    ]);
    await settle(tester, 600);
    expect(
      await (p.platform as NativePlayer).getProperty(
        'current-tracks/sub/external-filename',
      ),
      endsWith('Clip.en.srt'),
    );
    expect(c.settings.openSubtitlesKey, 'TESTKEY');
  });
}
