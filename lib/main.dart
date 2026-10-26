import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'library/library_store.dart';
import 'player/player_controller.dart';
import 'player/settings_store.dart';
import 'settings/prefs.dart';
import 'theme.dart';
import 'ui/player_screen.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: Size(1280, 760),
      minimumSize: Size(480, 270),
      center: true,
      title: 'Cone Player',
      backgroundColor: ConeColors.canvas,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  // Only real files and URLs: macOS/Xcode may add flags like "-NSFoo YES".
  final files = args
      .where((a) => a.contains('://') || File(a).existsSync())
      .toList();
  final support = await getApplicationSupportDirectory();
  final library = LibraryStore(support);
  await library.load();
  final settings = SettingsStore();
  await settings.load();
  runApp(
    ConePlayerApp(initialFiles: files, library: library, settings: settings),
  );
}

/// Applies the theme preferences (canvas, accent, control size).
void applyThemePrefs(SettingsStore s) {
  ConeColors.apply(
    palette: canvasPalettes.firstWhere(
      (p) => p.id == Prefs.canvas.of(s),
      orElse: () => canvasPalettes.first,
    ),
    accentColor: Color(Prefs.accent.of(s)),
  );
  ConeDensity.scale = ConeDensity.forName(Prefs.density.of(s));
}

/// Optional wrapper around the app's content (tests use it for screenshots).
TransitionBuilder? _builder;
void setAppBuilder(TransitionBuilder? b) => _builder = b;

class ConePlayerApp extends StatefulWidget {
  final List<String> initialFiles;
  final LibraryStore? library;
  final SettingsStore settings;

  /// For tests: drive a specific controller.
  final PlayerController? controller;
  const ConePlayerApp({
    super.key,
    this.initialFiles = const [],
    this.library,
    required this.settings,
    this.controller,
  });

  @override
  State<ConePlayerApp> createState() => _ConePlayerAppState();
}

class _ConePlayerAppState extends State<ConePlayerApp> {
  String _themeKey = '';

  String get _currentKey {
    final s = widget.settings;
    return '${Prefs.canvas.of(s)}|${Prefs.accent.of(s)}|${Prefs.density.of(s)}';
  }

  void _onSettings() {
    // Rebuild the tree only when something visual changed.
    if (_currentKey == _themeKey) return;
    setState(() {
      _themeKey = _currentKey;
      applyThemePrefs(widget.settings);
    });
  }

  @override
  void initState() {
    super.initState();
    _themeKey = _currentKey;
    applyThemePrefs(widget.settings);
    widget.settings.addListener(_onSettings);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettings);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Cone Player',
    debugShowCheckedModeBanner: false,
    theme: buildConeTheme(),
    builder: _builder,
    home: PlayerScreen(
      initialFiles: widget.initialFiles,
      library: widget.library,
      settings: widget.settings,
      controller: widget.controller,
    ),
  );
}
