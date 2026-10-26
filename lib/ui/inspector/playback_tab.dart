import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../player/player_controller.dart';
import '../../theme.dart';
import 'widgets.dart';

class PlaybackTab extends StatefulWidget {
  final PlayerController c;
  const PlaybackTab({super.key, required this.c});

  @override
  State<PlaybackTab> createState() => _PlaybackTabState();
}

class _PlaybackTabState extends State<PlaybackTab> {
  Timer? _tick;
  late Future<Map<String, Map<String, String>>> _meta = widget.c.metadata();
  late final StreamSubscription _rateSub;

  PlayerController get c => widget.c;

  @override
  void initState() {
    super.initState();
    // Countdown for the sleep timer.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (c.sleepAt != null && mounted) setState(() {});
    });
    _rateSub = c.player.stream.rate.listen(
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    _rateSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rate = c.player.state.rate;
    final remaining = c.sleepRemaining;
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        SectionHeader(
          'Speed',
          Icons.speed,
          Icons.speed_outlined,
          info:
              'Playback speed. Pitch is kept natural. Shortcuts: [ and ] '
              'step by 0.1×, Backspace resets.',
        ),
        AdjustSlider(
          label: 'Playback speed',
          value: rate,
          min: 0.25,
          max: 4,
          divisions: 75,
          defaultValue: 1,
          format: (v) => '${v.toStringAsFixed(2)}×',
          onChanged: (v) =>
              c.player.setRate(double.parse(v.toStringAsFixed(2))),
        ),
        ChipRow([
          for (final r in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0])
            ConeChip(
              label: '$r×',
              selected: (rate - r).abs() < 0.001,
              onTap: () => c.setRate(r),
            ),
        ]),
        SettingRow(
          label: 'Reverse playback',
          info:
              'Plays the video backwards. This is demanding: expect slower '
              'playback on long or high-resolution files.',
          child: ConeSwitch(value: c.reverse, onChanged: c.setReverse),
        ),
        panelDivider,
        SectionHeader(
          'Sleep timer',
          Icons.bedtime,
          Icons.bedtime_outlined,
          info:
              'Pause playback automatically after a while, or when the '
              'current file finishes.',
          trailing: remaining != null
              ? Text(
                  _fmt(remaining),
                  style: const TextStyle(
                    color: ConeColors.accent,
                    fontSize: 13,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                )
              : (c.sleepAtEnd
                    ? const Text(
                        'At end of file',
                        style: TextStyle(
                          color: ConeColors.accent,
                          fontSize: 12,
                        ),
                      )
                    : null),
        ),
        ChipRow([
          ConeChip(
            label: 'Off',
            selected: remaining == null && !c.sleepAtEnd,
            onTap: () => c.setSleepTimer(null),
          ),
          for (final m in [15, 30, 45, 60, 90])
            ConeChip(
              label: '$m min',
              selected: false,
              onTap: () => c.setSleepTimer(Duration(minutes: m)),
            ),
          ConeChip(
            label: 'End of file',
            selected: c.sleepAtEnd,
            onTap: () => c.setSleepTimer(null, atEndOfFile: true),
          ),
        ]),
        panelDivider,
        SectionHeader('Overlays', Icons.layers, Icons.layers_outlined),
        SettingRow(
          label: 'Waveform on seek bar',
          info:
              'Draws the audio waveform inside the seek bar so you can spot '
              'loud and quiet parts.',
          child: ConeSwitch(
            value: c.showWaveform,
            onChanged: (v) => c.setOverlay(waveform: v),
          ),
        ),
        SettingRow(
          label: 'Subtitle timeline',
          info:
              'Shows subtitle blocks above the seek bar. Drag a block to '
              're-sync subtitles visually.',
          child: ConeSwitch(
            value: c.showSubtitleTimeline,
            onChanged: (v) => c.setOverlay(subtitleTimeline: v),
          ),
        ),
        panelDivider,
        SectionHeader(
          'Media info',
          Icons.info,
          Icons.info_outlined,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Copy all',
                iconSize: 16,
                color: ConeColors.textMuted,
                onPressed: () async {
                  final m = await _meta;
                  final text = [
                    for (final g in m.entries) ...[
                      '[${g.key}]',
                      for (final e in g.value.entries) '${e.key}: ${e.value}',
                    ],
                  ].join('\n');
                  await Clipboard.setData(ClipboardData(text: text));
                  c.notify('Media info copied');
                },
                icon: const Icon(Icons.copy),
              ),
              IconButton(
                tooltip: 'Refresh',
                iconSize: 16,
                color: ConeColors.textMuted,
                onPressed: () => setState(() => _meta = c.metadata()),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        FutureBuilder(
          future: _meta,
          builder: (context, snap) {
            final m = snap.data;
            if (m == null) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            if (m.values.every((g) => g.isEmpty)) {
              return const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'Nothing playing.',
                  style: TextStyle(color: ConeColors.textMuted, fontSize: 12),
                ),
              );
            }
            return Column(
              children: [
                for (final g in m.entries)
                  if (g.value.isNotEmpty) _MetaGroup(g.key, g.value),
              ],
            );
          },
        ),
      ],
    );
  }

  static String _fmt(Duration d) =>
      '${d.inMinutes}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')} left';
}

class _MetaGroup extends StatelessWidget {
  final String title;
  final Map<String, String> rows;
  const _MetaGroup(this.title, this.rows);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: ConeColors.accent,
          ),
        ),
        const SizedBox(height: 4),
        for (final e in rows.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1.5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    e.key,
                    style: const TextStyle(
                      fontSize: 12,
                      color: ConeColors.textMuted,
                    ),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    e.value,
                    style: const TextStyle(
                      fontSize: 12,
                      color: ConeColors.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
