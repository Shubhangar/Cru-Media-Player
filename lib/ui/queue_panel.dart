import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../library/library_store.dart';
import '../player/player_controller.dart';
import '../theme.dart';
import 'flyouts.dart';
import 'library/library_screen.dart' show ScanCache;
import 'library/media_widgets.dart';
import '../player/format.dart';

/// Slide-out sidebar over the video: play queue, a compact library whose
/// items can be dragged into the queue, and bookmarks.
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

  static const width = 340.0;

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
              side: BorderSide(color: ConeColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: DefaultTabController(
              length: controller.library == null ? 2 : 3,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TabBar(
                          indicatorColor: ConeColors.accent,
                          labelColor: ConeColors.accent,
                          unselectedLabelColor: ConeColors.textMuted,
                          dividerColor: ConeColors.border,
                          labelPadding: EdgeInsets.zero,
                          tabs: [
                            Tab(text: 'Queue'),
                            if (controller.library != null)
                              Tab(text: 'Library'),
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
                        if (controller.library != null)
                          _LibraryTab(controller: controller),
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
        return QueueDropTarget(
          controller: controller,
          child: Column(
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
                          final name = fileNameOf(m.uri);
                          final current = i == pl.index;
                          return ReorderableDragStartListener(
                            key: ValueKey('${m.uri}#$i'),
                            index: i,
                            child: ListTile(
                              dense: true,
                              leading: current
                                  ? Icon(
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
              Divider(height: 1, color: ConeColors.border),
              TextButton.icon(
                onPressed: onAddFiles,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add files to queue'),
              ),
            ],
          ),
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
        leading: Icon(Icons.bookmark, color: ConeColors.accent, size: 18),
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

/// Accepts library items dragged onto it and appends them to the queue
/// without interrupting playback.
class QueueDropTarget extends StatelessWidget {
  final PlayerController controller;
  final Widget child;
  const QueueDropTarget({
    super.key,
    required this.controller,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => DragTarget<List<String>>(
    onAcceptWithDetails: (d) => controller.openAll(d.data, append: true),
    builder: (context, candidates, _) => Stack(
      children: [
        child,
        if (candidates.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                margin: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: ConeColors.accent.withValues(alpha: 0.10),
                  border: Border.all(color: ConeColors.accent, width: 2),
                  borderRadius: BorderRadius.circular(ConeRadius.md),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Drop to add to queue',
                  style: TextStyle(
                    color: ConeColors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Compact library list; rows can be dragged onto the queue drop zone.
class _LibraryTab extends StatefulWidget {
  final PlayerController controller;
  const _LibraryTab({required this.controller});

  @override
  State<_LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<_LibraryTab> {
  String _q = '';
  late Future<(List<String>, List<String>)> _all = _items();

  LibraryStore get lib => widget.controller.library!;

  /// Recently played, then everything in the library folders (minus repeats).
  Future<(List<String>, List<String>)> _items() async {
    final scans = await Future.wait([
      for (final f in lib.folders) ScanCache.get(f.path, f.kind),
    ]);
    final recent = [for (final h in lib.recent(limit: 50)) h.uri];
    final seen = recent.toSet();
    final folders = <String>[
      for (final l in scans)
        for (final f in l)
          if (seen.add(f.path)) f.path,
    ];
    return (recent, folders);
  }

  Future<void> _addFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    lib.addFolder(dir, FolderKind.video);
    setState(() => _all = _items());
  }

  bool _match(String u) => displayName(u).toLowerCase().contains(_q);

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10.5,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w600,
        color: ConeColors.textMuted,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
          child: TextField(
            style: const TextStyle(fontSize: 13),
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Search library',
              prefixIcon: Icon(Icons.search, size: 18),
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder(
            future: _all,
            builder: (context, snap) {
              final data = snap.data;
              if (data == null) {
                return const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              final recent = data.$1.where(_match).toList();
              final folders = data.$2.where(_match).toList();
              return ListView(
                children: [
                  if (recent.isNotEmpty) ...[
                    _header('Recently played'),
                    for (final u in recent) _row(u),
                  ],
                  if (folders.isNotEmpty) ...[
                    _header('In your folders'),
                    for (final u in folders) _row(u),
                  ],
                  if (lib.folders.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Column(
                        children: [
                          const Text(
                            'Add a folder to browse its videos here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: ConeColors.textMuted,
                              fontSize: 12.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: _addFolder,
                            icon: const Icon(
                              Icons.create_new_folder_outlined,
                              size: 18,
                            ),
                            label: const Text('Add a folder…'),
                          ),
                        ],
                      ),
                    )
                  else if (recent.isEmpty && folders.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Nothing matches.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: ConeColors.textMuted),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        QueueDropTarget(
          controller: widget.controller,
          child: Container(
            height: 52,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: ConeColors.border)),
            ),
            alignment: Alignment.center,
            child: StreamBuilder(
              stream: widget.controller.player.stream.playlist,
              builder: (_, _) => Text(
                'Drag items here to queue them  ·  '
                '${widget.controller.player.state.playlist.medias.length} in queue',
                style: const TextStyle(
                  fontSize: 12,
                  color: ConeColors.textMuted,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(String uri) {
    final h = lib.history[uri];
    final tile = ListTile(
      dense: true,
      leading: SizedBox(
        width: 48,
        height: 27,
        child: MediaThumb(
          thumb: h?.thumb,
          audio: isAudioPath(uri),
          progress: h?.progress ?? 0,
        ),
      ),
      title: Text(
        displayName(uri),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: ConeColors.text),
      ),
      trailing: IconButton(
        tooltip: 'Add to queue',
        iconSize: 18,
        color: ConeColors.accent,
        onPressed: () => widget.controller.openAll([uri], append: true),
        icon: const Icon(Icons.add),
      ),
      onTap: () => widget.controller.playNext([uri]),
    );
    return Draggable<List<String>>(
      data: [uri],
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: ConeColors.surfaceHigh,
        borderRadius: BorderRadius.circular(ConeRadius.md),
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.queue, size: 16, color: ConeColors.accent),
              const SizedBox(width: 8),
              Text(
                displayName(uri),
                style: const TextStyle(color: ConeColors.text, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: tile),
      child: tile,
    );
  }
}
