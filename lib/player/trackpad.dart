import 'dart:io';

import 'package:flutter/services.dart';

/// Where the fingers rest on the trackpad, from the native side (macOS).
class Trackpad {
  static const _channel = MethodChannel('cru/trackpad');

  /// 0 = left edge of the trackpad, 1 = right edge; null when unknown
  /// (other platforms, mice, or no recent touch reading).
  static Future<double?> fingerX() async {
    if (!Platform.isMacOS) return null;
    try {
      return await _channel.invokeMethod<double>('fingerX');
    } catch (_) {
      return null;
    }
  }
}
