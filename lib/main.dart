import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'theme.dart';
import 'ui/player_screen.dart';

Future<void> main() async {
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
  runApp(const ConePlayerApp());
}

class ConePlayerApp extends StatelessWidget {
  const ConePlayerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Cone Player',
        debugShowCheckedModeBanner: false,
        theme: buildConeTheme(),
        home: const PlayerScreen(),
      );
}
