import 'package:flutter/material.dart';

import '../../library/library_store.dart';
import '../../theme.dart';
import '../library/library_screen.dart' show LibrarySection;
import '../library/media_widgets.dart';

/// Landing hub shown when nothing is playing: continue watching, pins,
/// playlists and recent items.
class HomeView extends StatelessWidget {
  final LibraryStore library;
  final LibraryActions actions;
  final VoidCallback onOpenFile, onOpenFolder, onOpenStream;
  final void Function({
    String? folder,
    String? sourceUrl,
    LibrarySection? section,
  })
  onOpenLibrary;
  const HomeView({
    super.key,
    required this.library,
    required this.actions,
    required this.onOpenFile,
    required this.onOpenFolder,
    required this.onOpenStream,
    required this.onOpenLibrary,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final resume = library.recent(limit: 12, unfinishedOnly: true);
        final recent = library
            .recent(limit: 30)
            .where((h) => !h.resumable)
            .take(8)
            .toList();
        final empty =
            resume.isEmpty &&
            recent.isEmpty &&
            library.pins.isEmpty &&
            library.playlists.isEmpty;
        // Material, not a coloured box, so list rows can show hover/ink.
        return Material(
          color: ConeColors.canvas,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(32, 72, 32, 140),
                children: [
                  _hero(),
                  if (empty) _dropHint(),
                  if (resume.isNotEmpty) ...[
                    const ShelfHeader('Continue watching'),
                    SizedBox(
                      height: 190,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: resume.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 14),
                        itemBuilder: (_, i) => SizedBox(
                          width: 240,
                          child: _historyCard(resume[i]),
                        ),
                      ),
                    ),
                  ],
                  if (library.pins.isNotEmpty) ...[
                    const ShelfHeader('Pinned'),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [for (final p in library.pins) _pinTile(p)],
                    ),
                  ],
                  if (library.playlists.isNotEmpty) ...[
                    ShelfHeader(
                      'Playlists',
                      trailing: TextButton(
                        onPressed: () =>
                            onOpenLibrary(section: LibrarySection.playlists),
                        child: const Text('See all'),
                      ),
                    ),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final p in library.playlists) _playlistTile(p),
                      ],
                    ),
                  ],
                  if (recent.isNotEmpty) ...[
                    ShelfHeader(
                      'Recently played',
                      trailing: TextButton(
                        onPressed: library.clearHistory,
                        child: const Text(
                          'Clear history',
                          style: TextStyle(color: ConeColors.textMuted),
                        ),
                      ),
                    ),
                    for (final h in recent) _recentRow(h),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _hero() => Row(
    children: [
      Icon(Icons.change_history_rounded, size: 44, color: ConeColors.accent),
      const SizedBox(width: 14),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cone Player',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: ConeColors.text,
              ),
            ),
            Text(
              'Drop video, music, playlists or subtitles anywhere.',
              style: TextStyle(color: ConeColors.textMuted),
            ),
          ],
        ),
      ),
      Wrap(
        spacing: 8,
        children: [
          FilledButton.icon(
            onPressed: onOpenFile,
            icon: const Icon(Icons.insert_drive_file_outlined, size: 18),
            label: const Text('Open file'),
            style: _btnShape(FilledButton.styleFrom()),
          ),
          _outlined('Folder', Icons.folder_open_outlined, onOpenFolder),
          _outlined('Network stream', Icons.language, onOpenStream),
          _outlined(
            'Library',
            Icons.video_library_outlined,
            () => onOpenLibrary(),
          ),
        ],
      ),
    ],
  );

  static ButtonStyle _btnShape(ButtonStyle s) => s.copyWith(
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ConeRadius.md),
      ),
    ),
  );

  Widget _outlined(String label, IconData icon, VoidCallback f) =>
      OutlinedButton.icon(
        onPressed: f,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: _btnShape(
          OutlinedButton.styleFrom(
            foregroundColor: ConeColors.text,
            side: BorderSide(color: ConeColors.border),
          ),
        ),
      );

  Widget _dropHint() => Container(
    margin: const EdgeInsets.only(top: 40),
    height: 260,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(ConeRadius.lg),
      border: Border.all(color: ConeColors.border, width: 1.5),
      color: ConeColors.surface,
    ),
    alignment: Alignment.center,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.file_download_outlined, size: 40, color: ConeColors.accent),
        SizedBox(height: 10),
        Text(
          'Drop media here to start',
          style: TextStyle(fontSize: 16, color: ConeColors.text),
        ),
        SizedBox(height: 4),
        Text(
          'Things you watch show up here so you can pick up where you left off.',
          style: TextStyle(color: ConeColors.textMuted, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _historyCard(HistoryEntry h) => MediaCard(
    title: h.title,
    caption: timeLeft(h),
    thumb: MediaThumb(thumb: h.thumb, audio: h.isAudio, progress: h.progress),
    onTap: () => actions.play([h.uri]),
    onRemove: () => library.forget(h.uri),
    menu: [
      menuItem('Play', Icons.play_arrow, () => actions.play([h.uri])),
      menuItem('Add to queue', Icons.queue, () => actions.enqueue([h.uri])),
      menuItem(
        'Mark as watched',
        Icons.check,
        () => library.setWatched(h.uri, true),
      ),
      menuItem('Remove', Icons.close, () => library.forget(h.uri)),
    ],
  );

  Widget _tile({
    required IconData icon,
    required String title,
    required String caption,
    required VoidCallback onTap,
    VoidCallback? onUnpin,
  }) => Material(
    color: ConeColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(ConeRadius.md),
      side: BorderSide(color: ConeColors.border),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(ConeRadius.md),
      onTap: onTap,
      child: SizedBox(
        width: 250,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              Icon(icon, color: ConeColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: ConeColors.text),
                    ),
                    Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: ConeColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (onUnpin != null)
                IconButton(
                  tooltip: 'Unpin',
                  iconSize: 16,
                  color: ConeColors.textMuted,
                  onPressed: onUnpin,
                  icon: const Icon(Icons.push_pin),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _pinTile(Pin p) {
    void unpin() => library.togglePin(p);
    switch (p.kind) {
      case PinKind.folder:
        return _tile(
          icon: Icons.folder,
          title: p.label,
          caption: p.target,
          onTap: () => onOpenLibrary(folder: p.target),
          onUnpin: unpin,
        );
      case PinKind.stream:
        final isSource = library.sources.any((s) => s.url == p.target);
        return _tile(
          icon: isSource ? Icons.live_tv : Icons.language,
          title: p.label,
          caption: isSource ? 'Channel list' : p.target,
          onTap: () => isSource
              ? onOpenLibrary(sourceUrl: p.target)
              : actions.play([p.target]),
          onUnpin: unpin,
        );
      case PinKind.playlist:
        final pl = library.playlists.where((x) => x.id == p.target).firstOrNull;
        return _tile(
          icon: Icons.playlist_play,
          title: p.label,
          caption: pl == null ? 'Missing' : '${pl.items.length} items',
          onTap: () => pl == null ? null : actions.play(pl.items),
          onUnpin: unpin,
        );
    }
  }

  Widget _playlistTile(UserPlaylist p) => _tile(
    icon: Icons.playlist_play,
    title: p.name,
    caption: '${p.items.length} item${p.items.length == 1 ? '' : 's'}',
    onTap: () => p.items.isEmpty ? null : actions.play(p.items),
  );

  Widget _recentRow(HistoryEntry h) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: SizedBox(
      width: 64,
      height: 36,
      child: MediaThumb(thumb: h.thumb, audio: h.isAudio, watched: false),
    ),
    title: Text(h.title, style: const TextStyle(color: ConeColors.text)),
    subtitle: Text(
      h.watched ? 'Finished' : timeLeft(h),
      style: const TextStyle(color: ConeColors.textMuted, fontSize: 11),
    ),
    trailing: IconButton(
      tooltip: 'Remove from history',
      iconSize: 16,
      color: ConeColors.textMuted,
      onPressed: () => library.forget(h.uri),
      icon: const Icon(Icons.close),
    ),
    onTap: () => actions.play([h.uri]),
  );
}
