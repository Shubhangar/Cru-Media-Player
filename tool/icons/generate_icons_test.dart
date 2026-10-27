// Regenerates the app icons from the blob mascot.
// Run: flutter test tool/icons/generate_icons_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cone_player/ui/blob_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _orange = Color(0xFFFF6600);

/// Icon artwork at [px]: a charcoal rounded tile with the blob on it
/// (macOS grid: the tile fills ~80% of the canvas).
Future<Uint8List> renderIcon(int px, {bool tile = true}) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  final s = px.toDouble();
  if (tile) {
    final inset = s * 0.1;
    final r = Rect.fromLTWH(inset, inset, s - 2 * inset, s - 2 * inset);
    c.drawRRect(
      RRect.fromRectAndRadius(r, Radius.circular(r.width * 0.225)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2A2A2A), Color(0xFF121212)],
        ).createShader(r),
    );
    c.save();
    c.translate(s * 0.2, s * 0.19);
    BlobPainter(color: _orange).paint(c, Size.square(s * 0.6));
    c.restore();
  } else {
    BlobPainter(color: _orange).paint(c, Size.square(s));
  }
  final img = await rec.endRecording().toImage(px, px);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// ICO container holding PNG images (supported since Windows Vista).
Uint8List buildIco(List<(int, Uint8List)> images) {
  final header = BytesBuilder()
    ..add([0, 0, 1, 0])
    ..add(_u16(images.length));
  var offset = 6 + 16 * images.length;
  final dir = BytesBuilder();
  for (final (px, png) in images) {
    dir
      ..add([px >= 256 ? 0 : px, px >= 256 ? 0 : px, 0, 0])
      ..add(_u16(1))
      ..add(_u16(32))
      ..add(_u32(png.length))
      ..add(_u32(offset));
    offset += png.length;
  }
  final out = BytesBuilder()
    ..add(header.takeBytes())
    ..add(dir.takeBytes());
  for (final (_, png) in images) {
    out.add(png);
  }
  return out.takeBytes();
}

List<int> _u16(int v) => [v & 255, v >> 8 & 255];
List<int> _u32(int v) => [v & 255, v >> 8 & 255, v >> 16 & 255, v >> 24 & 255];

void main() {
  test('generate icons', () async {
    await TestWidgetsFlutterBinding.ensureInitialized().runAsync(() async {
      const mac = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
      for (final px in [16, 32, 64, 128, 256, 512, 1024]) {
        await File('$mac/app_icon_$px.png').writeAsBytes(await renderIcon(px));
      }
      await File('windows/runner/resources/app_icon.ico').writeAsBytes(
        buildIco([
          for (final px in [16, 32, 48, 64, 256]) (px, await renderIcon(px)),
        ]),
      );
      await Directory('assets/brand').create(recursive: true);
      await File('assets/brand/app_icon_256.png')
          .writeAsBytes(await renderIcon(256));
      await File('assets/brand/blob_512.png')
          .writeAsBytes(await renderIcon(512, tile: false));
    });
  });
}
