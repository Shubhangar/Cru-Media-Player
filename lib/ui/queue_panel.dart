import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../player/player_controller.dart';
import '../theme.dart';
import 'flyouts.dart';

/// Slide-out sidebar over the video with the play queue and bookmarks.
class QueuePanel extends StatelessWidget {
  final bool open;
  final PlayerController controller;
  final VoidCallback onClose;
  final VoidCallback onAddFiles;
  const QueuePanel({
    super.key,
    required this.open,
    required this.controller,
    required this.onClose,
    required this.onAddFiles,
  });

  static const width = 320.0;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !open,
      child: AnimatedSlide(
        offset: open ? Offset.zero : const Offset(1, 0),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: Container(
          width: width,
          margin: const EdgeInsets.only(right: 8, bottom: 110),
          // Material (not a decorated box) so list rows show hover/ink.
          child: Material(
            color: ConeColors.surface.withValues(alpha: 0.96),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ConeRadius.lg),
              side: const BorderSide(color: ConeColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: TabBar(
                          indicatorColor: ConeColors.accent,
                          labelColor: ConeColors.accent,
                          unselectedLabelColor: ConeColors.textMuted,
                          dividerColor: ConeColors.border,
                          tabs: [
                            Tab(text: 'Queue'),
                            Tab(text: 'Bookmarks'),
                          ],
                        ),
                      ),
                      ControlIcon(
                        icon: Icons.close,
                        tooltip: 'Close',
                        onPressed: onClose,
                        size: 18,
                      ),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _QueueList(
                          controller: controller,
                          onAddFiles: onAddFiles,
                        ),
                        _BookmarkList(controller: controller),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QueueList extends StatelessWidget {
  final PlayerController controller;
  final VoidCallback onAddFiles;
  const _QueueList({required this.controller, required this.onAddFiles});

  @override
  Widget build(BuildContext context) {
    final p = controller.player;
    return StreamBuilder<Playlist>(
      stream: p.stream.playlist,
      initialData: p.state.playlist,
      builder: (context, snap) {
        final pl = snap.data!;
        return Column(
          children: [
            Expanded(
              child: pl.medias.isEmpty
                  ? const Center(
                      child: Text(
                        'Queue is empty.\nDrop files onto the video.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: ConeColors.textMuted),
                      ),
                    )
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      itemCount: pl.medias.length,
                      // mpv inserts before the target index; onReorderItem gives
                      // the final index, so shift by one when moving down.
                      onReorderItem: (from, to) =>
                          p.move(from, to > from ? to + 1 : to),
                      itemBuilder: (context, i) {
                        final m = pl.medias[i];
                        final name = Uri.decodeComponent(
                          m.uri.split(RegExp(r'[/\\]')).last,
                        );
                        final current = i == pl.index;
                        return ReorderableDragStartListener(
                          key: ValueKey('${m.uri}#$i'),
                          index: i,
                          child: ListTile(
                            dense: true,
                            leading: current
                                ? const Icon(
                                    Icons.play_arrow_rounded,
                                    color: ConeColors.accent,
                                  )
                                : Text(
                                    '${i + 1}',
                                    style: const TextStyle(
                                      color: ConeColors.textMuted,
                                    ),
                                  ),
                            title: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: current
                                    ? ConeColors.accent
                                    : ConeColors.text,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                size: 18,
                                color: ConeColors.textMuted,
                              ),
                              onPressed: () => p.remove(i),
                            ),
                            onTap: () => p.jump(i),
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 1, color: ConeColors.border),
            TextButton.icon(
              onPressed: onAddFiles,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add files to queue'),
            ),
          ],
        );
      },
    );
  }
}

class _BookmarkList extends StatelessWidget {
  final PlayerController controller;
  const _BookmarkList({required this.controller});

  @override
  Widget build(BuildContext context) {
    final b = controller.bookmarks;
    if (b.isEmpty) {
      return const Center(
        child: Text(
          'No bookmarks yet.\nPress Ctrl/⌘ + B while watching.',
          textAlign: TextAlign.center,
          style: TextStyle(color: ConeColors.textMuted),
        ),
      );
    }
    return ListView.builder(
      itemCount: b.length,
      itemBuilder: (_, i) => ListTile(
        dense: true,
        leading: const Icon(Icons.bookmark, color: ConeColors.accent, size: 18),
        title: Text(b[i].label, style: const TextStyle(color: ConeColors.text)),
        trailing: Text(
          formatDuration(b[i].position),
          style: const TextStyle(color: ConeColors.textMuted),
        ),
        onTap: () => controller.player.seek(b[i].position),
      ),
    );
  }
}
