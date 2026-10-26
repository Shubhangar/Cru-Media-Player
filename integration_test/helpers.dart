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
