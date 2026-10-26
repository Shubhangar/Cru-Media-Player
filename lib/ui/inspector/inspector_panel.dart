import 'package:flutter/material.dart';

import '../../player/player_controller.dart';
import '../../theme.dart';
import 'audio_tab.dart';
import 'playback_tab.dart';
import 'subtitle_tab.dart';
import 'video_tab.dart';

enum InspectorTab { subtitles, audio, video, playback }

/// Slide-out multi-tab inspector over the video.
class InspectorPanel extends StatelessWidget {
  final bool open;
  final PlayerController controller;
  final InspectorTab tab;
  final ValueChanged<InspectorTab> onTab;
  final VoidCallback onClose;
  final VoidCallback onLoadSubtitle;
  const InspectorPanel({
    super.key,
    required this.open,
    required this.controller,
    required this.tab,
    required this.onTab,
    required this.onClose,
    required this.onLoadSubtitle,
  });

  static const width = 380.0;

  static const _tabs = [
    (InspectorTab.subtitles, Icons.subtitles_outlined, 'Subtitles'),
    (InspectorTab.audio, Icons.graphic_eq, 'Audio'),
    (InspectorTab.video, Icons.tune, 'Video'),
    (InspectorTab.playback, Icons.slow_motion_video, 'Playback'),
  ];

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !open,
      child: AnimatedSlide(
        offset: open ? Offset.zero : const Offset(1.05, 0),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: Container(
          width: width,
          margin: const EdgeInsets.only(right: 8, bottom: 110),
          child: Material(
            color: ConeColors.surface.withValues(alpha: 0.97),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ConeRadius.lg),
              side: BorderSide(color: ConeColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _header(),
                Divider(height: 1, color: ConeColors.border),
                Expanded(
                  child: ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) => switch (tab) {
                      InspectorTab.subtitles => SubtitleTab(
                        c: controller,
                        onLoadFile: onLoadSubtitle,
                      ),
                      InspectorTab.audio => AudioTab(c: controller),
                      InspectorTab.video => VideoTab(c: controller),
                      InspectorTab.playback => PlaybackTab(c: controller),
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
    child: Row(
      children: [
        for (final (t, icon, label) in _tabs)
          Expanded(
            child: Semantics(
              label: label,
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(ConeRadius.md),
                onTap: () => onTab(t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: t == tab ? ConeColors.accentDim : null,
                    borderRadius: BorderRadius.circular(ConeRadius.md),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        icon,
                        size: 20,
                        color: t == tab ? ConeColors.accent : ConeColors.text,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          color: t == tab
                              ? ConeColors.accent
                              : ConeColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        IconButton(
          tooltip: 'Close',
          iconSize: 18,
          color: ConeColors.textMuted,
          onPressed: onClose,
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );
}
