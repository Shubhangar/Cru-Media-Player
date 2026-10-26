import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../osd.dart';

final _mod = Platform.isMacOS ? '⌘' : 'Ctrl';

/// The essential shortcuts, shared by Settings and the onboarding tour.
List<(String, String)> get essentialShortcuts => [
  ('Space', 'Play / pause'),
  ('← →', 'Jump back / forward'),
  ('↑ ↓', 'Volume'),
  ('F', 'Fullscreen'),
  (', .', 'Previous / next frame'),
  ('$_mod + B', 'Bookmark this moment'),
  ('$_mod + I', 'Inspector (subtitles, audio, video)'),
  ('$_mod + Shift + L', 'Library'),
];

List<(String, String)> get allShortcuts => [
  ...essentialShortcuts,
  ('Shift + ← →', 'Big jump'),
  ('M', 'Mute'),
  ('[ ]  Backspace', 'Slower / faster / normal speed'),
  ('N  P', 'Next / previous in queue'),
  ('I', 'Picture-in-picture'),
  ('H', 'Hide all controls'),
  ('R', 'Rotate 90°'),
  ('Z  X', 'Zoom in / out'),
  ('S', 'Screenshot'),
  ('$_mod + O', 'Open file  (Shift: folder)'),
  ('$_mod + U', 'Open network stream'),
  ('$_mod + V', 'Play link from clipboard'),
  ('$_mod + L', 'Queue & bookmarks'),
  ('$_mod + W', 'Close media'),
  ('$_mod + ,', 'Settings'),
  ('Enter / Esc', 'Accept / dismiss resume prompt'),
];

class ShortcutTable extends StatelessWidget {
  final bool essentialOnly;
  const ShortcutTable({super.key, this.essentialOnly = false});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final (keys, what)
          in essentialOnly ? essentialShortcuts : allShortcuts)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 150,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: KeyChip(keys),
                ),
              ),
              Text(
                what,
                style: const TextStyle(fontSize: 13, color: ConeColors.text),
              ),
            ],
          ),
        ),
    ],
  );
}
