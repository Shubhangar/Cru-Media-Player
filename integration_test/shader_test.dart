// Phase 5: GPU shader engine (built-ins, folder presets) reaches the picture.
import 'dart:io';

import 'package:cone_player/library/library_store.dart';
import 'package:cone_player/player/player_controller.dart';
import 'package:cone_player/player/settings_store.dart';
import 'package:cone_player/settings/prefs.dart';
import 'package:cone_player/theme.dart';
import 'package:cone_player/ui/inspector/inspector_panel.dart';
import 'package:cone_player/ui/player_screen.dart';
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
  setUpAll(() async => tmp = await Directory.systemTemp.createTemp('cone_sh'));
  tearDownAll(() async {
    await tmp.delete(recursive: true);
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys().where((k) => k.startsWith(testPrefix))) {
      await prefs.remove(k);
    }
  });

  testWidgets('shaders: built-ins and folder presets', (tester) async {
    MediaKit.ensureInitialized();
    await prepareTestWindow();
    // A stand-in "FSR.glsl" that paints everything magenta, so the effect is
    // unmistakable in the captured frame.
    final folder = Directory('${tmp.path}${Platform.pathSeparator}shaders')
      ..createSync();
    File('${folder.path}${Platform.pathSeparator}FSR.glsl')
        .writeAsStringSync('''
//!HOOK MAIN
//!BIND HOOKED
//!DESC test magenta
vec4 hook() { return vec4(1.0, 0.0, 1.0, 1.0); }
''');
    final lib = LibraryStore(
      Directory('${tmp.path}${Platform.pathSeparator}store'),
    );
    final c = PlayerController(
      settings: SettingsStore(prefix: testPrefix),
      library: lib,
    );
    Prefs.onboarded.set(c.settings, true);
    Prefs.shaderFolder.set(c.settings, folder.path);
    final p = c.player;
    final mpv = p.platform as NativePlayer;
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
    await settle(tester, 500);

    // Built-ins were extracted and can be activated.
    final sharpen = c.shaders!.builtInPath('cone_sharpen')!;
    expect(File(sharpen).readAsStringSync(), contains('//!HOOK MAIN'));
    c.shaders!.toggle(sharpen, true);
    await settle(tester, 400);
    expect(
      await mpv.getProperty('glsl-shaders'),
      contains('cone_sharpen.glsl'),
    );
    c.shaders!.setActive(const []);
    await settle(tester, 400);

    // Inspector › Video › Shaders shows the preset unlocked by the folder.
    await pressMod(tester, LogicalKeyboardKey.keyI);
    await settle(tester, 400);
    final panel = find.byType(InspectorPanel);
    await tester.tap(find.descendant(of: panel, matching: find.text('Video')));
    await settle(tester, 600);
    final chip = find.descendant(
      of: panel,
      matching: find.text('AMD FSR upscale'),
    );
    await tester.scrollUntilVisible(
      chip,
      200,
      scrollable: find
          .descendant(of: panel, matching: find.byType(Scrollable))
          .first,
    );
    await tester.ensureVisible(chip);
    await settle(tester);
    bool magenta(int r, int g, int b) => r > 220 && g < 40 && b > 220;
    final before = await countPixels(tester, magenta);
    await tester.tap(chip);
    await p.seek(const Duration(seconds: 1));
    await settle(tester, 900);
    final after = await countPixels(tester, magenta);
    expect(
      await mpv.getProperty('glsl-shaders'),
      contains('FSR.glsl'),
      reason: 'preset applied',
    );
    if (!noGpu) {
      expect(after, greaterThan(before + 50000), reason: 'shader must render');
    }
    await snap(tester, 'p5-8-shader');

    await tester.tap(
      find.descendant(of: panel, matching: find.textContaining('Turn off')),
    );
    await settle(tester, 400);
    expect(await mpv.getProperty('glsl-shaders'), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(lib.save);
  });
}
