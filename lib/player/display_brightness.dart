import 'dart:io';

import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';

/// Brightness of the display the player is on (0..1), for the swipe gesture.
///
/// macOS: built-in displays via the runner's `cru/display` channel. Windows:
/// monitors via screen_brightness. Elsewhere, or for displays that can't be
/// driven, [get] returns null and callers adjust the video instead.
class DisplayBrightness {
  static const _mac = MethodChannel('cru/display');

  static Future<double?> get() async {
    try {
      if (Platform.isMacOS) return await _mac.invokeMethod<double>('get');
      if (Platform.isWindows) return await ScreenBrightness().system;
    } catch (_) {}
    return null;
  }

  static Future<bool> set(double value) async {
    final v = value.clamp(0.0, 1.0);
    try {
      if (Platform.isMacOS) {
        return await _mac.invokeMethod<bool>('set', v) ?? false;
      }
      if (Platform.isWindows) {
        await ScreenBrightness().setSystemScreenBrightness(v);
        return true;
      }
    } catch (_) {}
    return false;
  }
}
