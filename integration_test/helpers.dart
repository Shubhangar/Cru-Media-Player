import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const fixtures = String.fromEnvironment('FIXTURES');

/// Optional: `--dart-define=SHOTS=<dir>` saves PNGs of the Flutter UI.
const shots = String.fromEnvironment('SHOTS');
final shotKey = GlobalKey();

Widget withShotBoundary(BuildContext context, Widget? child) =>
    RepaintBoundary(key: shotKey, child: child);

Future<void> snap(WidgetTester tester, String name) async {
  if (shots.isEmpty) return;
  await tester.pump();
  final boundary =
      shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1.5);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  await File('$shots/$name.png').writeAsBytes(png!.buffer.asUint8List());
}

Future<void> waitFor(
  WidgetTester tester,
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 10),
  String what = 'condition',
}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('Timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump();
  }
}

/// Renders a frame (starting any animations), waits, then renders again.
Future<void> settle(WidgetTester tester, [int ms = 300]) async {
  await tester.pump();
  await Future<void>.delayed(Duration(milliseconds: ms));
  await tester.pump();
}

LogicalKeyboardKey get modKey => defaultTargetPlatform == TargetPlatform.macOS
    ? LogicalKeyboardKey.metaLeft
    : LogicalKeyboardKey.controlLeft;

Future<void> pressMod(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(modKey);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(modKey);
}

/// Raw RGBA pixels of the app (including the video texture).
Future<(ByteData, int width)> captureRgba(WidgetTester tester) async {
  await tester.pump();
  final boundary =
      shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return (data!, image.width);
}

/// Counts pixels in the lower half matching [test] (r, g, b).
Future<int> countPixels(
  WidgetTester tester,
  bool Function(int r, int g, int b) test,
) async {
  final (data, width) = await captureRgba(tester);
  final height = data.lengthInBytes ~/ 4 ~/ width;
  var n = 0;
  for (var y = height ~/ 2; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      if (test(data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2))) {
        n++;
      }
    }
  }
  return n;
}

/// Average brightness (0..255) of [rect] (logical pixels) in the app image.
Future<double> meanBrightness(WidgetTester tester, Rect rect) async {
  final (data, width) = await captureRgba(tester);
  var sum = 0.0;
  var n = 0;
  for (var y = rect.top.ceil(); y < rect.bottom.floor(); y += 4) {
    for (var x = rect.left.ceil(); x < rect.right.floor(); x += 4) {
      final i = (y * width + x) * 4;
      if (i + 2 >= data.lengthInBytes) continue;
      sum +=
          (data.getUint8(i) + data.getUint8(i + 1) + data.getUint8(i + 2)) / 3;
      n++;
    }
  }
  return n == 0 ? 0 : sum / n;
}
