import 'package:flutter/services.dart';

/// Files the OS asks the app to open after launch (macOS Finder "Open With",
/// double-click, dropping on the Dock icon). These arrive as system events,
/// not command-line arguments.
class SystemOpen {
  static const _channel = MethodChannel('cru/open_files');

  /// Calls [onFiles] for every open request. Returns the files that were
  /// requested before Dart was ready (e.g. the file that launched the app).
  static Future<List<String>> listen(
    void Function(List<String> files) onFiles,
  ) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open') {
        onFiles(List<String>.from(call.arguments as List));
      }
    });
    try {
      final pending = await _channel.invokeMethod<List>('ready');
      return List<String>.from(pending ?? const []);
    } on MissingPluginException {
      return const []; // Platforms (and tests) without the native side.
    }
  }
}
