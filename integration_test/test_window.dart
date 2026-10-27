import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// Makes the test window behave as if it were in front, even while you use
/// other apps during a run:
/// - always on top, because macOS stops drawing windows that are covered;
/// - lifecycle pinned to resumed, because Flutter drops keyboard focus when
///   the app goes inactive, and simulated shortcuts then reach nothing.
Future<void> prepareTestWindow() async {
  await windowManager.ensureInitialized();
  await windowManager.setAlwaysOnTop(true);
  final binding = WidgetsBinding.instance;
  _listener ??= AppLifecycleListener(
    onStateChange: (state) {
      if (state != AppLifecycleState.resumed) {
        scheduleMicrotask(
          () =>
              binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed),
        );
      }
    },
  );
  binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

AppLifecycleListener? _listener;
