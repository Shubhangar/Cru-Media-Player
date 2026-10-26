import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'theme.dart';
import 'ui/player_screen.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
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
  runApp(ConePlayerApp(initialFiles: files));
}

class ConePlayerApp extends StatelessWidget {
  final List<String> initialFiles;
  const ConePlayerApp({super.key, this.initialFiles = const []});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Cone Player',
    debugShowCheckedModeBanner: false,
    theme: buildConeTheme(),
    home: PlayerScreen(initialFiles: initialFiles),
  );
}
