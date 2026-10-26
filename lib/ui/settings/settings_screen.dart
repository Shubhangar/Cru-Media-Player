import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../library/library_store.dart';
import '../../player/player_controller.dart';
import '../../player/settings_store.dart';
import '../../settings/prefs.dart';
import '../../theme.dart';
import '../inspector/widgets.dart';
import 'shortcuts.dart';

/// One row in a settings panel.
class _Entry {
  final String label;
  final String info;
  final List<String> keys; // preference keys reset by "Reset panel"
  final Widget Function(BuildContext) build;
  final bool wide; // control spans the full width under the label
  const _Entry(
    this.label,
    this.info,
    this.build, {
    this.keys = const [],
    this.wide = false,
  });
}

class _Panel {
  final String name;
  final IconData filled, outlined;
  final List<_Entry> entries;
  const _Panel(this.name, this.filled, this.outlined, this.entries);
}

/// Full-window settings with 10 categorised panels.
class SettingsScreen extends StatefulWidget {
  final PlayerController controller;
  final VoidCallback onClose;
  final VoidCallback onShowOnboarding;
  final VoidCallback onEditLayout;
  final VoidCallback onEditSubtitleStyle;
  final String initialPanel;
  const SettingsScreen({
    super.key,
    required this.controller,
    required this.onClose,
    required this.onShowOnboarding,
    required this.onEditLayout,
    required this.onEditSubtitleStyle,
    this.initialPanel = 'General',
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String _panel = widget.initialPanel;
  String _query = '';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  PlayerController get c => widget.controller;
  SettingsStore get s => c.settings;
  LibraryStore? get lib => c.library;

  // ---- Control builders ---------------------------------------------------

  Widget _toggle(Pref<bool> p) =>
      ConeSwitch(value: p.of(s), onChanged: (v) => p.set(s, v));

  Widget _choice<T extends Object>(Pref<T> p, List<(T, String)> options) =>
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final (v, label) in options)
            ConeChip(
              label: label,
              selected: p.of(s) == v,
              onTap: () => p.set(s, v),
            ),
        ],
      );

  Widget _slider(
    Pref<double> p, {
    required double min,
    required double max,
    int? divisions,
    required String Function(double) format,
  }) => SizedBox(
    width: 260,
    child: Row(
      children: [
        Expanded(
          child: Slider(
            value: p.of(s).clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: (v) => p.set(s, v),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            format(p.of(s)),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, color: ConeColors.textMuted),
          ),
        ),
      ],
    ),
  );

  Widget _text(Pref<String> p, String hint) => SizedBox(
    width: 260,
    child: TextFormField(
      initialValue: p.of(s),
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
      ),
      onFieldSubmitted: (v) => p.set(s, v.trim()),
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      onChanged: (v) => p.set(s, v.trim()),
    ),
  );

  Widget _folder(Pref<String> p, String emptyLabel) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Text(
          p.of(s).isEmpty ? emptyLabel : p.of(s),
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: ConeColors.textMuted),
        ),
      ),
      const SizedBox(width: 8),
      OutlinedButton(
        onPressed: () async {
          final d = await FilePicker.platform.getDirectoryPath();
          if (d != null) p.set(s, d);
        },
        child: const Text('Choose…'),
      ),
      if (p.of(s).isNotEmpty)
        IconButton(
          tooltip: 'Use default',
          iconSize: 16,
          onPressed: () => p.set(s, ''),
          icon: const Icon(Icons.close),
        ),
    ],
  );

  Widget _button(String label, VoidCallback onTap, {IconData? icon}) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon ?? Icons.chevron_right, size: 16),
        label: Text(label),
      );

  Future<void> _clearDir(Directory d, String what) async {
    if (await d.exists()) await d.delete(recursive: true);
    c.notify('$what cleared');
  }

  // ---- Schema -----------------------------------------------------------

  List<_Panel> get _panels => [
    _Panel('General', Icons.palette, Icons.palette_outlined, [
      _Entry(
        'Theme',
        'The background tone of the whole app. True black saves power on '
            'OLED screens.',
        (_) => _choice(Prefs.canvas, [
          for (final p in canvasPalettes) (p.id, p.name),
        ]),
        keys: [Prefs.canvas.key],
      ),
      _Entry(
        'Accent colour',
        'Used for active controls, the seek bar and highlights.',
        (_) => Wrap(
          spacing: 8,
          children: [
            for (final (name, col) in accentChoices)
              Tooltip(
                message: name,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Prefs.accent.set(s, col.toARGB32()),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: col,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Prefs.accent.of(s) == col.toARGB32()
                            ? ConeColors.text
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        keys: [Prefs.accent.key],
      ),
      _Entry(
        'Welcome tour',
        'Shows the first-run guide again: theme, layout density and the '
            'essential shortcuts.',
        (_) => _button('Show again', widget.onShowOnboarding),
      ),
    ]),
    _Panel(
      'Interface',
      Icons.dashboard_customize,
      Icons.dashboard_customize_outlined,
      [
        _Entry(
          'Control size',
          'How large buttons and bars are. Compact leaves more room for the '
              'picture; Large is easier on touchscreens.',
          (_) => _choice(Prefs.density, [
            ('compact', 'Compact'),
            ('comfortable', 'Comfortable'),
            ('large', 'Large'),
          ]),
          keys: [Prefs.density.key],
        ),
        _Entry(
          'Control bar layout',
          'Choose which buttons appear and in what order, and switch between '
              'saved layouts.',
          (_) => _button(
            'Customise…',
            widget.onEditLayout,
            icon: Icons.drag_indicator,
          ),
        ),
        _Entry(
          'Hide controls after',
          'How long the bars stay after the pointer leaves the top or bottom '
              'edge during playback.',
          (_) => _choice(Prefs.hideDelayMs, [
            (0, 'Instantly'),
            (600, '0.6 s'),
            (1500, '1.5 s'),
            (3000, '3 s'),
          ]),
          keys: [Prefs.hideDelayMs.key],
        ),
        _Entry(
          'On-screen notices',
          'Briefly shows what happened and which key did it, e.g. "Volume 80% ↑".',
          (_) => _toggle(Prefs.osd),
          keys: [Prefs.osd.key],
        ),
        _Entry(
          'Notice duration',
          'How long on-screen notices stay visible.',
          (_) => _choice(Prefs.osdMs, [
            (800, 'Short'),
            (1300, 'Normal'),
            (2500, 'Long'),
          ]),
          keys: [Prefs.osdMs.key],
        ),
        _Entry(
          'Seek bar previews',
          'Shows a picture of the moment you point at on the seek bar.',
          (_) => _toggle(Prefs.seekPreviews),
          keys: [Prefs.seekPreviews.key],
        ),
        _Entry(
          'Keep window on top',
          'The player window stays above other windows.',
          (_) => _toggle(Prefs.stayOnTop),
          keys: [Prefs.stayOnTop.key],
        ),
      ],
    ),
    _Panel('Privacy', Icons.shield, Icons.shield_outlined, [
      _Entry(
        'Remember what I watch',
        'Keeps your history so you can resume. Turn off and nothing new is '
            'recorded.',
        (_) => _toggle(Prefs.rememberHistory),
        keys: [Prefs.rememberHistory.key],
      ),
      _Entry(
        'Save picture thumbnails',
        'Stores a small frame of each video for the Home screen cards.',
        (_) => _toggle(Prefs.saveThumbnails),
        keys: [Prefs.saveThumbnails.key],
      ),
      if (lib != null) ...[
        _Entry(
          'Watch history',
          'Removes every history entry, resume point and thumbnail.',
          (_) => _button('Clear history', () async {
            lib!.clearHistory();
            await _clearDir(lib!.thumbsDir, 'History');
          }, icon: Icons.delete_sweep_outlined),
        ),
        _Entry(
          'Cached data',
          'Deletes cached waveforms. They are rebuilt when needed.',
          (_) => _button(
            'Clear cache',
            () => _clearDir(Directory('${lib!.dir.path}/waveforms'), 'Cache'),
            icon: Icons.cleaning_services_outlined,
          ),
        ),
      ],
    ]),
    _Panel('Controls', Icons.keyboard, Icons.keyboard_outlined, [
      _Entry(
        'Arrow key jump',
        'How far ← and → skip.',
        (_) => _choice(Prefs.seekStep, [
          (5, '5 s'),
          (10, '10 s'),
          (15, '15 s'),
          (30, '30 s'),
        ]),
        keys: [Prefs.seekStep.key],
      ),
      _Entry(
        'Shift + arrow jump',
        'How far Shift + ← and Shift + → skip.',
        (_) => _choice(Prefs.bigSeekStep, [
          (30, '30 s'),
          (60, '1 min'),
          (120, '2 min'),
          (300, '5 min'),
        ]),
        keys: [Prefs.bigSeekStep.key],
      ),
      _Entry(
        'Scroll wheel on the picture',
        'What scrolling over the video does. (On the seek bar it always '
            'steps frame by frame.)',
        (_) => _choice(Prefs.wheel, [
          ('volume', 'Volume'),
          ('seek', 'Seek'),
          ('none', 'Nothing'),
        ]),
        keys: [Prefs.wheel.key],
      ),
      _Entry(
        'Double-click',
        'Zones: left/right thirds jump 10 s and the middle toggles fullscreen.',
        (_) => _choice(Prefs.doubleClick, [
          ('zones', 'Zones'),
          ('fullscreen', 'Fullscreen'),
          ('play', 'Play/pause'),
        ]),
        keys: [Prefs.doubleClick.key],
      ),
      _Entry(
        'Keyboard shortcuts',
        'Every shortcut at a glance.',
        (_) => const ShortcutTable(),
        wide: true,
      ),
    ]),
    _Panel('Playback', Icons.play_circle, Icons.play_circle_outline, [
      _Entry(
        'Reopening unfinished files',
        'Ask shows a prompt near the controls; Always jumps straight to where '
            'you stopped.',
        (_) => _choice(Prefs.resume, [
          ('ask', 'Ask'),
          ('always', 'Resume'),
          ('never', 'Start over'),
        ]),
        keys: [Prefs.resume.key],
      ),
      _Entry(
        'Play next item automatically',
        'When a file ends, continue with the next one in the queue.',
        (_) => _toggle(Prefs.autoplayNext),
        keys: [Prefs.autoplayNext.key],
      ),
      _Entry(
        'Repeat',
        'Loop the current file or the whole queue.',
        (_) => _choice(Prefs.repeat, [
          ('off', 'Off'),
          ('one', 'This file'),
          ('all', 'Queue'),
        ]),
        keys: [Prefs.repeat.key],
      ),
      _Entry(
        'Starting speed',
        'Playback speed used when the app starts.',
        (_) => _slider(
          Prefs.defaultSpeed,
          min: 0.5,
          max: 2,
          divisions: 6,
          format: (v) => '${v.toStringAsFixed(2)}×',
        ),
        keys: [Prefs.defaultSpeed.key],
      ),
    ]),
    _Panel('Video', Icons.movie, Icons.movie_outlined, [
      _Entry(
        'Hardware decoding',
        'Lets the graphics chip decode video: smoother and lighter on '
            'battery. Turn off if you see glitches.',
        (_) => _toggle(Prefs.hwdec),
        keys: [Prefs.hwdec.key],
      ),
      _Entry(
        'Default upscaling quality',
        'How video is resized to your screen when a file opens.',
        (_) => _choice(Prefs.scaler, [
          ('bilinear', 'Fast'),
          ('spline36', 'Balanced'),
          ('ewa_lanczossharp', 'Sharp'),
        ]),
        keys: [Prefs.scaler.key],
      ),
      _Entry(
        'Smooth colour banding',
        'Removes stair-step bands in skies and gradients (uses a little '
            'more GPU).',
        (_) => _toggle(Prefs.deband),
        keys: [Prefs.deband.key],
      ),
      _Entry(
        'HDR tone mapping',
        'Fits HDR brightness into what your display can show.',
        (_) => _toggle(Prefs.toneMap),
        keys: [Prefs.toneMap.key],
      ),
    ]),
    _Panel('Audio', Icons.graphic_eq, Icons.graphic_eq_outlined, [
      _Entry(
        'Starting volume',
        'Volume used when the app starts.',
        (_) => _slider(
          Prefs.startVolume,
          min: 0,
          max: 100,
          divisions: 20,
          format: (v) => '${v.round()}%',
        ),
        keys: [Prefs.startVolume.key],
      ),
      _Entry(
        'Volume boost',
        'Allows volume above 100% (up to 150%) for quiet recordings.',
        (_) => _toggle(Prefs.volumeBoost),
        keys: [Prefs.volumeBoost.key],
      ),
      _Entry(
        'Balance surround downmix',
        'When 5.1/7.1 audio plays on stereo speakers, keeps dialogue and '
            'effects at even levels.',
        (_) => _toggle(Prefs.normalize),
        keys: [Prefs.normalize.key],
      ),
    ]),
    _Panel('Subtitle', Icons.subtitles, Icons.subtitles_outlined, [
      _Entry(
        'Turn subtitles on',
        'Always: whenever a track in your languages exists. Only for foreign '
            'audio: skip them when the audio is already in your language. '
            'Only forced: just signs and translated bits.',
        (_) => _choice(Prefs.subMode, [
          ('auto', 'Always'),
          ('foreign', 'Only for foreign audio'),
          ('forced', 'Only forced'),
          ('off', 'Never'),
        ]),
        keys: [Prefs.subMode.key],
      ),
      _Entry(
        'Pick up subtitle files automatically',
        'Loads subtitle files that sit next to the video. Similar names also '
            'matches "Movie.en.srt" for "Movie.mkv".',
        (_) => _choice(Prefs.subAutoLoad, [
          ('fuzzy', 'Similar names'),
          ('exact', 'Exact name'),
          ('no', 'Off'),
        ]),
        keys: [Prefs.subAutoLoad.key],
      ),
      _Entry(
        'Look and languages',
        'Font, size, colours, position and preferred languages.',
        (_) => _button('Edit subtitle style…', widget.onEditSubtitleStyle),
      ),
    ]),
    _Panel('Library', Icons.video_library, Icons.video_library_outlined, [
      if (lib != null)
        _Entry(
          'Library folders',
          'Folders scanned for Videos and Music.',
          (_) => ListenableBuilder(
            listenable: lib!,
            builder: (_, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final f in lib!.folders)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        f.kind == FolderKind.music
                            ? Icons.library_music_outlined
                            : Icons.movie_outlined,
                        size: 14,
                        color: ConeColors.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(f.path, style: const TextStyle(fontSize: 12)),
                      IconButton(
                        tooltip: 'Remove',
                        iconSize: 14,
                        onPressed: () => lib!.removeFolder(f),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final (kind, label) in [
                      (FolderKind.video, 'Add video folder'),
                      (FolderKind.music, 'Add music folder'),
                    ])
                      OutlinedButton(
                        onPressed: () async {
                          final d = await FilePicker.platform
                              .getDirectoryPath();
                          if (d != null) lib!.addFolder(d, kind);
                        },
                        child: Text(label),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      _Entry(
        'Refresh channel lists',
        'How often IPTV / M3U channel lists are re-downloaded when you open '
            'the library.',
        (_) => _choice(Prefs.refreshHours, [
          (1, 'Hourly'),
          (6, 'Every 6 h'),
          (24, 'Daily'),
        ]),
        keys: [Prefs.refreshHours.key],
      ),
    ]),
    _Panel('Network & more', Icons.tune, Icons.tune_outlined, [
      _Entry(
        'Network timeout',
        'How long to wait for a stream before giving up.',
        (_) => _choice(Prefs.netTimeout, [
          (5, '5 s'),
          (15, '15 s'),
          (30, '30 s'),
          (60, '60 s'),
        ]),
        keys: [Prefs.netTimeout.key],
      ),
      _Entry(
        'Stream buffer',
        'How much of a stream to download ahead. More survives shaky '
            'connections but uses more memory.',
        (_) => _choice(Prefs.cacheMb, [
          (50, '50 MB'),
          (150, '150 MB'),
          (400, '400 MB'),
        ]),
        keys: [Prefs.cacheMb.key],
      ),
      _Entry(
        'Preload next item',
        'Starts opening the next queue item early so playback continues '
            'without a gap. (Performance)',
        (_) => _toggle(Prefs.prefetch),
        keys: [Prefs.prefetch.key],
      ),
      _Entry(
        'Browser identity',
        'Sent to web servers when streaming. Some services only accept '
            'certain browsers. Leave empty for the default.',
        (_) => _text(Prefs.userAgent, 'ConePlayer/1.0'),
        keys: [Prefs.userAgent.key],
      ),
      _Entry(
        'Screenshot folder',
        'Where S (or the menu) saves screenshots. (Recording)',
        (_) => _folder(Prefs.shotFolder, 'Pictures/Cone Player'),
        keys: [Prefs.shotFolder.key],
      ),
      _Entry(
        'Screenshot format',
        'PNG is lossless; JPEG files are smaller.',
        (_) => _choice(Prefs.shotFormat, [('png', 'PNG'), ('jpeg', 'JPEG')]),
        keys: [Prefs.shotFormat.key],
      ),
      _Entry(
        'Shader folder',
        'A folder of GLSL shaders (for example Anime4K or FSR packs) to use '
            'in Video › Shaders. (Extensions)',
        (_) => _folder(Prefs.shaderFolder, 'None'),
        keys: [Prefs.shaderFolder.key],
      ),
    ]),
  ];

  // ---- Layout -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ConeColors.canvas,
      child: ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final panels = _panels;
          final current = panels.firstWhere(
            (p) => p.name == _panel,
            orElse: () => panels.first,
          );
          return Row(
            children: [
              _rail(panels),
              VerticalDivider(width: 1, color: ConeColors.border),
              Expanded(child: _content(panels, current)),
            ],
          );
        },
      ),
    );
  }

  Widget _rail(List<_Panel> panels) => SizedBox(
    width: 220,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 14),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back to player (Esc)',
              onPressed: widget.onClose,
              icon: const Icon(Icons.arrow_back),
            ),
            const Text(
              'Settings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final p in panels)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Material(
              color: _query.isEmpty && p.name == _panel
                  ? ConeColors.accentDim
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(ConeRadius.md),
              child: InkWell(
                borderRadius: BorderRadius.circular(ConeRadius.md),
                onTap: () => setState(() {
                  _panel = p.name;
                  _query = '';
                  _search.clear();
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  child: Row(
                    children: [
                      TwoToneIcon(p.filled, p.outlined, size: 18),
                      const SizedBox(width: 12),
                      Text(
                        p.name,
                        style: TextStyle(
                          color: _query.isEmpty && p.name == _panel
                              ? ConeColors.accent
                              : ConeColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _content(List<_Panel> panels, _Panel current) {
    final q = _query.toLowerCase();
    final shown = q.isEmpty
        ? [for (final e in current.entries) (current, e)]
        : [
            for (final p in panels)
              for (final e in p.entries)
                if ('${e.label} ${e.info}'.toLowerCase().contains(q)) (p, e),
          ];
    final resetKeys = [for (final e in current.entries) ...e.keys];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 18, 20, 10),
          child: Row(
            children: [
              Text(
                q.isEmpty ? current.name : 'Search results',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (q.isEmpty && resetKeys.isNotEmpty)
                TextButton(
                  onPressed: () => s.reset(resetKeys),
                  child: const Text(
                    'Reset to defaults',
                    style: TextStyle(color: ConeColors.textMuted),
                  ),
                ),
              const SizedBox(width: 10),
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v.trim()),
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Search settings',
                    prefixIcon: Icon(Icons.search, size: 18),
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: ConeColors.border),
        Expanded(
          child: shown.isEmpty
              ? const Center(
                  child: Text(
                    'No settings match.',
                    style: TextStyle(color: ConeColors.textMuted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(28, 8, 24, 40),
                  itemCount: shown.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: ConeColors.border),
                  itemBuilder: (context, i) {
                    final (p, e) = shown[i];
                    if (e.wide) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  e.label,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                InfoTip(e.info),
                              ],
                            ),
                            const SizedBox(height: 10),
                            e.build(context),
                          ],
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        e.label,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: ConeColors.text,
                                        ),
                                      ),
                                    ),
                                    InfoTip(e.info),
                                  ],
                                ),
                                if (q.isNotEmpty)
                                  Text(
                                    p.name,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: ConeColors.accent,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          Flexible(
                            flex: 2,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: e.build(context),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
