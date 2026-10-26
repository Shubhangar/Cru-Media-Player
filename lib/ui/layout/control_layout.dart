import 'dart:convert';

import 'package:flutter/material.dart';

import '../../player/settings_store.dart';
import '../../settings/prefs.dart';

/// Every control that can be placed on the bottom bar.
enum ControlId {
  prev('Previous', Icons.skip_previous_rounded),
  play('Play / pause', Icons.play_arrow_rounded),
  next('Next', Icons.skip_next_rounded),
  frameBack('Previous frame', Icons.chevron_left),
  frameForward('Next frame', Icons.chevron_right),
  time('Time', Icons.schedule),
  speed('Speed', Icons.speed),
  bookmark('Bookmark', Icons.bookmark_add_outlined),
  screenshot('Screenshot', Icons.photo_camera_outlined),
  rotate('Rotate', Icons.rotate_90_degrees_cw_outlined),
  repeat('Repeat', Icons.repeat),
  fullscreen('Fullscreen', Icons.fullscreen),
  pip('Picture-in-picture', Icons.picture_in_picture_alt_outlined),
  queue('Queue', Icons.queue_music),
  subtitles('Subtitles', Icons.subtitles_outlined),
  audio('Audio', Icons.graphic_eq),
  inspector('Inspector', Icons.tune),
  library('Library', Icons.video_library_outlined),
  volume('Volume', Icons.volume_up_outlined);

  final String label;
  final IconData icon;
  const ControlId(this.label, this.icon);
}

/// Left and right groups of the control bar.
class BarLayout {
  final List<ControlId> left, right;
  const BarLayout(this.left, this.right);

  Set<ControlId> get used => {...left, ...right};

  Map<String, dynamic> toJson() => {
    'left': [for (final c in left) c.name],
    'right': [for (final c in right) c.name],
  };

  factory BarLayout.fromJson(Map<String, dynamic> j) {
    List<ControlId> list(String k) => [
      for (final n in (j[k] as List? ?? const []))
        ...ControlId.values.where((c) => c.name == n),
    ];
    return BarLayout(list('left'), list('right'));
  }

  BarLayout copy() => BarLayout([...left], [...right]);
}

const defaultLayouts = <String, BarLayout>{
  'Default': BarLayout(
    [ControlId.prev, ControlId.play, ControlId.next, ControlId.time],
    [
      ControlId.fullscreen,
      ControlId.pip,
      ControlId.queue,
      ControlId.subtitles,
      ControlId.audio,
      ControlId.volume,
    ],
  ),
  'Minimal': BarLayout(
    [ControlId.play, ControlId.time],
    [ControlId.fullscreen, ControlId.volume],
  ),
  'Power user': BarLayout(
    [
      ControlId.frameBack,
      ControlId.prev,
      ControlId.play,
      ControlId.next,
      ControlId.frameForward,
      ControlId.time,
      ControlId.speed,
    ],
    [
      ControlId.bookmark,
      ControlId.screenshot,
      ControlId.repeat,
      ControlId.subtitles,
      ControlId.audio,
      ControlId.inspector,
      ControlId.queue,
      ControlId.pip,
      ControlId.fullscreen,
      ControlId.volume,
    ],
  ),
};

/// Named layouts ("profiles") with one active, stored in [SettingsStore].
class LayoutProfiles {
  final SettingsStore s;
  LayoutProfiles(this.s);

  static const _key = Pref('barLayouts', '');
  static const _active = Pref('barLayout', 'Default');

  Map<String, BarLayout> get all {
    final raw = _key.of(s);
    if (raw.isEmpty) return {...defaultLayouts};
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in j.entries)
          e.key: BarLayout.fromJson(Map<String, dynamic>.from(e.value as Map)),
      };
    } catch (_) {
      return {...defaultLayouts};
    }
  }

  void _saveAll(Map<String, BarLayout> m) => _key.set(
    s,
    jsonEncode({for (final e in m.entries) e.key: e.value.toJson()}),
  );

  String get activeName {
    final n = _active.of(s);
    return all.containsKey(n) ? n : all.keys.first;
  }

  BarLayout get active => all[activeName]!;

  void select(String name) => _active.set(s, name);

  void update(String name, BarLayout layout) {
    final m = all..[name] = layout;
    _saveAll(m);
  }

  String saveAs(String name, BarLayout layout) {
    var n = name.trim().isEmpty ? 'My layout' : name.trim();
    final m = all;
    var i = 2;
    final base = n;
    while (m.containsKey(n)) {
      n = '$base $i';
      i++;
    }
    m[n] = layout;
    _saveAll(m);
    select(n);
    return n;
  }

  void delete(String name) {
    final m = all..remove(name);
    if (m.isEmpty) m.addAll(defaultLayouts);
    _saveAll(m);
    if (activeName == name || !m.containsKey(_active.of(s))) {
      select(m.keys.first);
    }
  }

  /// Restores a built-in profile (or all built-ins) to its original buttons.
  void resetBuiltIn(String name) {
    final d = defaultLayouts[name];
    if (d != null) update(name, d.copy());
  }
}
