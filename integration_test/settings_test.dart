// Phase 5: onboarding, theme, settings panels, layout customizer.
import 'dart:io';

import 'package:cone_player/library/library_store.dart';
import 'package:cone_player/main.dart';
import 'package:cone_player/player/player_controller.dart';
import 'package:cone_player/player/settings_store.dart';
import 'package:cone_player/settings/prefs.dart';
import 'package:cone_player/theme.dart';
import 'package:cone_player/ui/inspector/widgets.dart';
import 'package:cone_player/ui/layout/control_layout.dart';
import 'package:cone_player/ui/layout/layout_editor.dart';
import 'package:cone_player/ui/onboarding.dart';
import 'package:cone_player/ui/settings/settings_screen.dart';
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
  setUpAll(() async => tmp = await Directory.systemTemp.createTemp('cone_set'));
  tearDownAll(() async {
    await tmp.delete(recursive: true);
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys().where((k) => k.startsWith(testPrefix))) {
      await prefs.remove(k);
    }
    // Leave the global palette as the app's default for other tests.
    ConeColors.apply(
      palette: canvasPalettes.first,
      accentColor: accentChoices.first.$2,
    );
    ConeDensity.scale = 1;
  });

  testWidgets('onboarding, settings and layout customizer', (tester) async {
    MediaKit.ensureInitialized();
    await prepareTestWindow();
    final settings = SettingsStore(prefix: testPrefix);
    final lib = LibraryStore(
      Directory('${tmp.path}${Platform.pathSeparator}store'),
    );
    final c = PlayerController(settings: settings, library: lib);
    final p = c.player;
    final mpv = p.platform as NativePlayer;
    setAppBuilder(withShotBoundary);
    await tester.binding.setSurfaceSize(const Size(1280, 760));
    await tester.pumpWidget(
      ConePlayerApp(
        settings: settings,
        library: lib,
        controller: c,
        initialFiles: [fixture('test-clip.mp4')],
      ),
    );
    await waitFor(tester, () => p.state.duration > Duration.zero, what: 'load');
    await p.pause();
    await settle(tester);

    // --- Onboarding ---------------------------------------------------------
    Finder wiz(Finder f) =>
        find.descendant(of: find.byType(OnboardingWizard), matching: f);
    expect(find.byType(OnboardingWizard), findsOneWidget);
    expect(find.text('Welcome to Cru Media Player'), findsOneWidget);
    await snap(tester, 'p5-1-welcome');
    await tester.tap(wiz(find.text('Get started')));
    await settle(tester);
    await tester.tap(wiz(find.text('True black (OLED)')));
    await tester.tap(wiz(find.byTooltip('Sky')));
    await settle(tester);
    expect(ConeColors.canvas, const Color(0xFF000000));
    expect(
      ConeColors.accent,
      accentChoices.firstWhere((a) => a.$1 == 'Sky').$2,
    );
    await snap(tester, 'p5-2-look');
    await tester.tap(wiz(find.text('Next')));
    await settle(tester);
    await tester.tap(wiz(find.text('Large')));
    await tester.tap(wiz(find.text('Power user')));
    await settle(tester);
    expect(ConeDensity.scale, 1.25);
    expect(LayoutProfiles(settings).activeName, 'Power user');
    await snap(tester, 'p5-3-density');
    await tester.tap(wiz(find.text('Next')));
    await settle(tester);
    expect(find.text('Bookmark this moment'), findsOneWidget);
    await tester.tap(wiz(find.text('Next')));
    await settle(tester);
    await tester.tap(wiz(find.text('Explore')));
    await settle(tester, 400);
    expect(find.byType(OnboardingWizard), findsNothing);
    expect(Prefs.onboarded.of(settings), isTrue);

    // Power-user bar has the extra buttons.
    expect(find.byTooltip('Screenshot (S)'), findsOneWidget);
    expect(find.byTooltip('Next frame (.)'), findsOneWidget);
    await snap(tester, 'p5-4-power-bar');

    // --- Settings -----------------------------------------------------------
    await pressMod(tester, LogicalKeyboardKey.comma);
    await settle(tester, 400);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(InfoTip), findsAtLeastNWidgets(3));
    for (final panel in [
      'General', 'Interface', 'Privacy', 'Controls', 'Playback', 'Video',
      'Audio', 'Subtitle', 'Library', 'Network & more', //
    ]) {
      expect(find.text(panel), findsWidgets, reason: panel);
    }
    await tester.enterText(
      find.widgetWithText(TextField, 'Search settings'),
      'banding',
    );
    await settle(tester);
    expect(find.text('Smooth colour banding'), findsOneWidget);
    await tester.tap(
      find
          .descendant(
            of: find
                .ancestor(
                  of: find.text('Smooth colour banding'),
                  matching: find.byType(Row),
                )
                .at(1),
            matching: find.byType(Switch),
          )
          .first,
    );
    await settle(tester);
    expect(Prefs.deband.of(settings), isTrue);
    expect(await mpv.getProperty('deband'), 'yes');
    await snap(tester, 'p5-5-search');

    await tester.enterText(
      find.widgetWithText(TextField, 'Search settings'),
      '',
    );
    await tester.tap(find.text('Controls'));
    await settle(tester);
    await tester.tap(find.text('10 s'));
    await settle(tester);
    expect(Prefs.seekStep.of(settings), 10);
    await snap(tester, 'p5-6-controls');
    await tester.tap(find.text('Reset to defaults'));
    await settle(tester);
    expect(Prefs.seekStep.of(settings), 5);
    await tester.tap(find.text('10 s'));
    await settle(tester);

    await tester.tap(find.text('Network & more'));
    await settle(tester);
    Prefs.shotFolder.set(settings, '${tmp.path}${Platform.pathSeparator}shots');
    await settle(tester);

    // --- Layout customizer from Interface -----------------------------------
    await tester.tap(find.text('Interface'));
    await settle(tester);
    await tester.tap(find.text('Customise…'));
    await settle(tester, 400);
    expect(find.byType(LayoutEditor), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(LayoutEditor),
        matching: find.text('Default'),
      ),
    );
    await settle(tester);
    expect(find.byTooltip('Screenshot (S)'), findsNothing);
    final chip = find.byKey(const ValueKey('chip-screenshot'));
    final zone = find.byKey(const ValueKey('zone-left'));
    await tester.dragFrom(
      tester.getCenter(chip),
      tester.getCenter(zone) - tester.getCenter(chip),
    );
    await settle(tester);
    expect(
      LayoutProfiles(settings).active.left,
      contains(ControlId.screenshot),
    );
    await snap(tester, 'p5-7-layout-editor');
    await tester.tap(find.text('Save as new'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'Mine');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(LayoutProfiles(settings).activeName, 'Mine');
    await tester.tap(find.byTooltip('Done'));
    await settle(tester);
    expect(find.byTooltip('Screenshot (S)'), findsOneWidget);

    // --- Behaviour follows settings -------------------------------------------
    final before = p.state.position;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await waitFor(
      tester,
      () => p.state.position >= before + const Duration(seconds: 9),
      what: '10 s jump',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await waitFor(
      tester,
      () =>
          Directory('${tmp.path}${Platform.pathSeparator}shots').existsSync() &&
          Directory('${tmp.path}${Platform.pathSeparator}shots')
              .listSync()
              .isNotEmpty,
      what: 'screenshot file',
    );
    final shot = Directory('${tmp.path}${Platform.pathSeparator}shots')
        .listSync()
        .single;
    expect(shot.path, endsWith('.png'));
    expect(File(shot.path).lengthSync(), greaterThan(1000));

    setAppBuilder(null);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(lib.save);
  });
}
