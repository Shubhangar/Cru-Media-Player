import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../library/library_store.dart';
import '../../library/m3u.dart';
import '../../theme.dart';
import 'media_widgets.dart';

/// Folder separator of this OS (scanned paths use it; Windows uses `\`).
final _sep = Platform.pathSeparator;

enum LibrarySection { videos, music, streams, playlists, history }

enum SortMode {
  name,
  nameDesc,
  added,
  size,
  unwatchedFirst,
  watchedFirst,
  played,
}

const _sortLabels = {
  SortMode.name: 'Name A–Z',
  SortMode.nameDesc: 'Name Z–A',
  SortMode.added: 'Recently added',
  SortMode.size: 'Largest first',
  SortMode.unwatchedFirst: 'Unwatched first',
  SortMode.watchedFirst: 'Watched first',
  SortMode.played: 'Recently played',
};

enum ViewMode { grid, list, detail }

/// Folder scans are cached for the session; refresh re-scans.
class ScanCache {
  static final Map<String, Future<List<MediaFile>>> _cache = {};
  static Future<List<MediaFile>> get(
    String root,
    FolderKind? kind, {
    bool refresh = false,
  }) => refresh || !_cache.containsKey('$root|$kind')
      ? (_cache['$root|$kind'] = scanFolder(root, kind: kind))
      : _cache['$root|$kind']!;
}

/// Full-window media library over the player.
class LibraryScreen extends StatefulWidget {
  final LibraryStore library;
  final LibraryActions actions;
  final List<String> Function() currentQueue;
  final VoidCallback onClose;
  final LibrarySection initialSection;
  final String? initialFolder;
  final String? initialSourceUrl;
  const LibraryScreen({
    super.key,
    required this.library,
    required this.actions,
    required this.currentQueue,
    required this.onClose,
    this.initialSection = LibrarySection.videos,
    this.initialFolder,
    this.initialSourceUrl,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late LibrarySection _section = widget.initialSourceUrl != null
      ? LibrarySection.streams
      : widget.initialSection;
  String? _root; // library folder being browsed (null = list of roots)
  String? _path; // current folder inside _root
  String _query = '';
  SortMode _sort = SortMode.name;
  ViewMode _view = ViewMode.grid;
  String? _sourceId;
  String? _channelGroup;
  String? _playlistId;
  final _search = TextEditingController();

  LibraryStore get lib => widget.library;
  LibraryActions get act => widget.actions;

  @override
  void initState() {
    super.initState();
    final f = widget.initialFolder;
    if (f != null) {
      final root = lib.folders
          .where((r) => f == r.path || f.startsWith('${r.path}$_sep'))
          .firstOrNull;
      _section = root?.kind == FolderKind.music
          ? LibrarySection.music
          : LibrarySection.videos;
      _root = root?.path ?? f;
      _path = f;
    }
    if (widget.initialSourceUrl != null) {
      _sourceId = lib.sources
          .where((s) => s.url == widget.initialSourceUrl)
          .firstOrNull
          ?.id;
    }
    lib.refreshStaleSources();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _go(LibrarySection s) => setState(() {
    _section = s;
    _root = _path = null;
    _query = '';
    _search.clear();
  });

  FolderKind? get _kind => switch (_section) {
    LibrarySection.videos => FolderKind.video,
    LibrarySection.music => FolderKind.music,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ConeColors.canvas,
      child: ListenableBuilder(
        listenable: lib,
        builder: (context, _) => Row(
          children: [
            _rail(),
            VerticalDivider(width: 1, color: ConeColors.border),
            Expanded(
              child: Column(
                children: [
                  _toolbar(),
                  Divider(height: 1, color: ConeColors.border),
                  Expanded(child: _body()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Navigation rail ----------------------------------------------------

  Widget _rail() {
    Widget item(LibrarySection s, IconData icon, String label, [int? count]) {
      final sel = _section == s;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Material(
          color: sel ? ConeColors.accentDim : Colors.transparent,
          borderRadius: BorderRadius.circular(ConeRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(ConeRadius.md),
            onTap: () => _go(s),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: sel ? ConeColors.accent : ConeColors.text,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: sel ? ConeColors.accent : ConeColors.text,
                      ),
                    ),
                  ),
                  if (count != null && count > 0)
                    Text(
                      '$count',
                      style: const TextStyle(
                        fontSize: 11,
                        color: ConeColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: 210,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back to player (Esc)',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 4),
                const Text(
                  'Library',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: ConeColors.text,
                  ),
                ),
              ],
            ),
          ),
          item(
            LibrarySection.videos,
            Icons.movie_outlined,
            'Videos',
            lib.folders.where((f) => f.kind == FolderKind.video).length,
          ),
          item(
            LibrarySection.music,
            Icons.library_music_outlined,
            'Music',
            lib.folders.where((f) => f.kind == FolderKind.music).length,
          ),
          item(
            LibrarySection.streams,
            Icons.live_tv_outlined,
            'Network streams',
            lib.sources.length,
          ),
          item(
            LibrarySection.playlists,
            Icons.playlist_play,
            'Playlists',
            lib.playlists.length,
          ),
          item(
            LibrarySection.history,
            Icons.history,
            'History',
            lib.history.length,
          ),
        ],
      ),
    );
  }

  // ---- Toolbar: breadcrumb, search, sort, view mode ----------------------

  Widget _toolbar() {
    final crumbs = <(String, VoidCallback?)>[
      (
        switch (_section) {
          LibrarySection.videos => 'Videos',
          LibrarySection.music => 'Music',
          LibrarySection.streams => 'Network streams',
          LibrarySection.playlists => 'Playlists',
          LibrarySection.history => 'History',
        },
        () => setState(() {
          _root = _path = _sourceId = _playlistId = null;
        }),
      ),
    ];
    if (_root != null && _path != null) {
      final parent = Directory(_root!).parent.path;
      final rel = _path!.substring(parent.length + 1).split(_sep);
      var acc = parent;
      for (final seg in rel) {
        acc = '$acc$_sep$seg';
        final target = acc;
        crumbs.add((seg, () => setState(() => _path = target)));
      }
    }
    if (_section == LibrarySection.streams && _source != null) {
      crumbs.add((_source!.name, null));
    }
    if (_section == LibrarySection.playlists && _playlist != null) {
      crumbs.add((_playlist!.name, null));
    }
    final browsing =
        _section == LibrarySection.videos || _section == LibrarySection.music;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < crumbs.length; i++) ...[
                    if (i > 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: ConeColors.textMuted,
                        ),
                      ),
                    InkWell(
                      borderRadius: BorderRadius.circular(ConeRadius.sm),
                      onTap: i == crumbs.length - 1 ? null : crumbs[i].$2,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Text(
                          crumbs[i].$1,
                          style: TextStyle(
                            fontSize: i == 0 ? 16 : 14,
                            fontWeight: i == crumbs.length - 1
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: i == crumbs.length - 1
                                ? ConeColors.text
                                : ConeColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(
            width: 240,
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        iconSize: 16,
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                        }),
                        icon: const Icon(Icons.close),
                      ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          if (browsing) ...[
            const SizedBox(width: 10),
            PopupMenuButton<SortMode>(
              tooltip: 'Sort',
              initialValue: _sort,
              onSelected: (s) => setState(() => _sort = s),
              itemBuilder: (_) => [
                for (final e in _sortLabels.entries)
                  PopupMenuItem(value: e.key, height: 36, child: Text(e.value)),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: ConeColors.border),
                  borderRadius: BorderRadius.circular(ConeRadius.sm),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.sort,
                      size: 16,
                      color: ConeColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _sortLabels[_sort]!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: ConeColors.text,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            for (final (m, icon, tip) in [
              (ViewMode.grid, Icons.grid_view, 'Grid'),
              (ViewMode.list, Icons.view_list, 'List'),
              (ViewMode.detail, Icons.table_rows_outlined, 'Details'),
            ])
              IconButton(
                tooltip: tip,
                iconSize: 18,
                color: _view == m ? ConeColors.accent : ConeColors.textMuted,
                onPressed: () => setState(() => _view = m),
                icon: Icon(icon),
              ),
          ],
        ],
      ),
    );
  }

  Widget _body() => switch (_section) {
    LibrarySection.videos || LibrarySection.music => _browse(),
    LibrarySection.streams => _streams(),
    LibrarySection.playlists => _playlists(),
    LibrarySection.history => _history(),
  };

  // ---- Videos & music -------------------------------------------------

  Future<void> _addFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null) lib.addFolder(dir, _kind!);
  }

  Widget _empty(IconData icon, String title, String body, Widget? action) =>
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: ConeColors.accent),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 16, color: ConeColors.text),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: ConeColors.textMuted, fontSize: 12),
            ),
            if (action != null) ...[const SizedBox(height: 16), action],
          ],
        ),
      );

  Widget _browse() {
    final roots = lib.folders.where((f) => f.kind == _kind).toList();
    final music = _kind == FolderKind.music;
    final addButton = FilledButton.icon(
      onPressed: _addFolder,
      icon: const Icon(Icons.create_new_folder_outlined, size: 18),
      label: Text('Add ${music ? 'music' : 'video'} folder'),
    );

    // Search spans every root of this kind.
    if (_query.isNotEmpty) {
      final paths = _root != null
          ? [_root!]
          : roots.map((r) => r.path).toList();
      return FutureBuilder(
        future: Future.wait([for (final p in paths) ScanCache.get(p, _kind)]),
        builder: (context, snap) {
          if (!snap.hasData) return _loading();
          final hits = snap.data!
              .expand((l) => l)
              .where((f) => f.name.toLowerCase().contains(_query))
              .toList();
          if (hits.isEmpty) {
            return _empty(
              Icons.search_off,
              'No matches',
              'Nothing named "$_query".',
              null,
            );
          }
          return _files(_sorted(hits));
        },
      );
    }

    if (_root == null) {
      if (roots.isEmpty) {
        return _empty(
          music ? Icons.library_music_outlined : Icons.video_library_outlined,
          'Your ${music ? 'music' : 'video'} library is empty',
          'Add a folder and Cru Media Player will find all the '
              '${music ? 'songs' : 'videos'} inside it.',
          addButton,
        );
      }
      return GridView.extent(
        padding: const EdgeInsets.all(20),
        maxCrossAxisExtent: 260,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 3.2,
        children: [
          for (final r in roots)
            _folderTile(
              r.path,
              onOpen: () => setState(() => _root = _path = r.path),
              onRemove: () => lib.removeFolder(r),
            ),
          OutlinedButton.icon(
            onPressed: _addFolder,
            icon: const Icon(Icons.add),
            label: const Text('Add folder'),
            style: OutlinedButton.styleFrom(
              foregroundColor: ConeColors.textMuted,
              side: BorderSide(color: ConeColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ConeRadius.md),
              ),
            ),
          ),
        ],
      );
    }

    return FutureBuilder(
      future: ScanCache.get(_root!, _kind),
      builder: (context, snap) {
        if (!snap.hasData) return _loading();
        final here = _path ?? _root!;
        final subfolders = <String, int>{};
        final files = <MediaFile>[];
        for (final f in snap.data!) {
          if (!f.path.startsWith('$here$_sep')) continue;
          final rest = f.path.substring(here.length + 1);
          final slash = rest.indexOf(_sep);
          if (slash < 0) {
            files.add(f);
          } else {
            final sub = '$here$_sep${rest.substring(0, slash)}';
            subfolders[sub] = (subfolders[sub] ?? 0) + 1;
          }
        }
        if (subfolders.isEmpty && files.isEmpty) {
          return _empty(
            Icons.folder_off_outlined,
            'Nothing here',
            'No ${music ? 'audio' : 'video'} files in this folder.',
            TextButton(
              onPressed: () =>
                  setState(() => ScanCache.get(_root!, _kind, refresh: true)),
              child: const Text('Scan again'),
            ),
          );
        }
        final names = subfolders.keys.toList()..sort();
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(
                  children: [
                    Text(
                      '${files.length} file${files.length == 1 ? '' : 's'}'
                      '${names.isEmpty ? '' : ' · ${names.length} folder${names.length == 1 ? '' : 's'}'}',
                      style: const TextStyle(
                        color: ConeColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    if (files.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => act.play(
                          _sorted(files).map((f) => f.path).toList(),
                        ),
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('Play all'),
                      ),
                    TextButton.icon(
                      onPressed: () => lib.togglePin(
                        Pin(
                          Directory(here).uri.pathSegments
                              .where((s) => s.isNotEmpty)
                              .last,
                          here,
                          PinKind.folder,
                        ),
                      ),
                      icon: Icon(
                        lib.isPinned(here)
                            ? Icons.push_pin
                            : Icons.push_pin_outlined,
                        size: 16,
                      ),
                      label: Text(
                        lib.isPinned(here) ? 'Pinned' : 'Pin to Home',
                      ),
                    ),
                    IconButton(
                      tooltip: 'Scan again',
                      iconSize: 18,
                      color: ConeColors.textMuted,
                      onPressed: () => setState(
                        () => ScanCache.get(_root!, _kind, refresh: true),
                      ),
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
            ),
            if (names.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                sliver: SliverGrid.extent(
                  maxCrossAxisExtent: 260,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 3.2,
                  children: [
                    for (final n in names)
                      _folderTile(
                        n,
                        caption: '${subfolders[n]} items',
                        onOpen: () => setState(() => _path = n),
                      ),
                  ],
                ),
              ),
            SliverToBoxAdapter(child: _files(_sorted(files), shrink: true)),
          ],
        );
      },
    );
  }

  Widget _loading() => const Center(
    child: SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );

  Widget _folderTile(
    String path, {
    required VoidCallback onOpen,
    String? caption,
    VoidCallback? onRemove,
  }) {
    final name = path
        .split(RegExp(r'[/\\]'))
        .lastWhere((s) => s.isNotEmpty, orElse: () => path);
    return Material(
      color: ConeColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ConeRadius.md),
        side: BorderSide(color: ConeColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(ConeRadius.md),
        onTap: onOpen,
        onSecondaryTapDown: (d) async {
          final f = await showMenu<VoidCallback>(
            context: context,
            position: RelativeRect.fromLTRB(
              d.globalPosition.dx,
              d.globalPosition.dy,
              d.globalPosition.dx,
              d.globalPosition.dy,
            ),
            items: [
              menuItem('Open', Icons.folder_open, onOpen),
              menuItem(
                lib.isPinned(path) ? 'Unpin from Home' : 'Pin to Home',
                Icons.push_pin_outlined,
                () => lib.togglePin(Pin(name, path, PinKind.folder)),
              ),
              if (onRemove != null)
                menuItem('Remove from library', Icons.delete_outline, onRemove),
            ],
          );
          f?.call();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(Icons.folder, color: ConeColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: ConeColors.text),
                    ),
                    Text(
                      caption ?? path,
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
              if (lib.isPinned(path))
                const Icon(
                  Icons.push_pin,
                  size: 14,
                  color: ConeColors.textMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<MediaFile> _sorted(List<MediaFile> files) {
    HistoryEntry? h(MediaFile f) => lib.history[f.path];
    int watched(MediaFile f) => (h(f)?.watched ?? false) ? 1 : 0;
    final l = [...files];
    int byName(MediaFile a, MediaFile b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());
    l.sort(switch (_sort) {
      SortMode.name => byName,
      SortMode.nameDesc => (a, b) => byName(b, a),
      SortMode.added => (a, b) => b.modified.compareTo(a.modified),
      SortMode.size => (a, b) => b.size.compareTo(a.size),
      SortMode.unwatchedFirst => (a, b) {
        final c = watched(a).compareTo(watched(b));
        return c != 0 ? c : byName(a, b);
      },
      SortMode.watchedFirst => (a, b) {
        final c = watched(b).compareTo(watched(a));
        return c != 0 ? c : byName(a, b);
      },
      SortMode.played => (a, b) {
        final ta = h(a)?.lastPlayed, tb = h(b)?.lastPlayed;
        if (ta == null && tb == null) return byName(a, b);
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      },
    });
    return l;
  }

  List<PopupMenuEntry<VoidCallback>> _fileMenu(List<MediaFile> all, int i) {
    final f = all[i];
    final watched = lib.history[f.path]?.watched ?? false;
    return [
      menuItem('Play', Icons.play_arrow, () => _playFrom(all, i)),
      menuItem('Play next', Icons.playlist_play, () => act.playNext([f.path])),
      menuItem('Add to queue', Icons.queue, () => act.enqueue([f.path])),
      menuItem(
        'Add to playlist…',
        Icons.playlist_add,
        () => _addToPlaylist([f.path]),
      ),
      menuItem(
        watched ? 'Mark as unwatched' : 'Mark as watched',
        watched ? Icons.remove_done : Icons.done,
        () => lib.setWatched(f.path, !watched),
      ),
    ];
  }

  void _playFrom(List<MediaFile> all, int i) =>
      act.play(all.map((f) => f.path).toList(), start: i);

  Widget _files(List<MediaFile> files, {bool shrink = false}) {
    if (files.isEmpty) return const SizedBox.shrink();
    switch (_view) {
      case ViewMode.grid:
        return GridView.builder(
          shrinkWrap: shrink,
          physics: shrink ? const NeverScrollableScrollPhysics() : null,
          padding: const EdgeInsets.all(20),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 240,
            mainAxisSpacing: 16,
            crossAxisSpacing: 14,
            childAspectRatio: 1.25,
          ),
          itemCount: files.length,
          itemBuilder: (_, i) {
            final f = files[i];
            final h = lib.history[f.path];
            return MediaCard(
              title: f.name,
              caption: h == null
                  ? _fmtSize(f.size)
                  : (h.watched ? 'Watched' : timeLeft(h)),
              thumb: MediaThumb(
                thumb: h?.thumb,
                audio: f.isAudio,
                progress: h?.progress ?? 0,
                watched: h?.watched ?? false,
              ),
              onTap: () => _playFrom(files, i),
              menu: _fileMenu(files, i),
            );
          },
        );
      case ViewMode.list:
      case ViewMode.detail:
        final detail = _view == ViewMode.detail;
        return ListView.builder(
          shrinkWrap: shrink,
          physics: shrink ? const NeverScrollableScrollPhysics() : null,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: files.length + (detail ? 1 : 0),
          itemBuilder: (_, i) {
            if (detail && i == 0) return _detailHeader();
            final idx = detail ? i - 1 : i;
            final f = files[idx];
            final h = lib.history[f.path];
            return _FileRow(
              file: f,
              history: h,
              detail: detail,
              onTap: () => _playFrom(files, idx),
              menu: _fileMenu(files, idx),
            );
          },
        );
    }
  }

  Widget _detailHeader() => const Padding(
    padding: EdgeInsets.fromLTRB(12, 4, 12, 6),
    child: Row(
      children: [
        SizedBox(width: 70),
        Expanded(flex: 5, child: _H('Name')),
        Expanded(flex: 2, child: _H('Size')),
        Expanded(flex: 2, child: _H('Modified')),
        Expanded(flex: 2, child: _H('Status')),
      ],
    ),
  );

  Future<void> _addToPlaylist(List<String> uris) async {
    final choice = await showDialog<Object>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Add to playlist'),
        children: [
          for (final p in lib.playlists)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p),
              child: Text(p.name),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'new'),
            child: Row(
              children: [
                Icon(Icons.add, size: 16, color: ConeColors.accent),
                SizedBox(width: 8),
                Text('New playlist…'),
              ],
            ),
          ),
        ],
      ),
    );
    if (choice is UserPlaylist) {
      lib.addToPlaylist(choice, uris);
    } else if (choice == 'new' && mounted) {
      final name = await _ask('New playlist', 'Name');
      if (name != null) lib.createPlaylist(name, uris);
    }
  }

  Future<String?> _ask(String title, String hint, {String initial = ''}) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(hintText: hint),
            onSubmitted: (v) =>
                Navigator.pop(ctx, v.trim().isEmpty ? null : v.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: ConeColors.textMuted),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              ctrl.text.trim().isEmpty ? null : ctrl.text.trim(),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ---- Network streams / IPTV --------------------------------------------

  StreamSource? get _source =>
      lib.sources.where((s) => s.id == _sourceId).firstOrNull;

  Future<void> _addStream() async {
    final urlCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    var asList = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Add network stream'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: urlCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'https://…/channels.m3u  or a video URL',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Name (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                RadioGroup<bool>(
                  groupValue: asList,
                  onChanged: (v) => setD(() => asList = v ?? true),
                  child: const Column(
                    children: [
                      RadioListTile(
                        value: true,
                        dense: true,
                        title: Text('Channel list (M3U / IPTV)'),
                        subtitle: Text(
                          'Lists every channel; refreshes automatically',
                        ),
                      ),
                      RadioListTile(
                        value: false,
                        dense: true,
                        title: Text('Single stream'),
                        subtitle: Text('Pinned to Home for one-click playback'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: ConeColors.textMuted),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    final url = urlCtrl.text.trim();
    if (ok != true || url.isEmpty) return;
    final name = nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim();
    if (asList) {
      final s = await lib.addSource(url, name: name);
      if (mounted) setState(() => _sourceId = s.id);
    } else {
      lib.togglePin(Pin(name ?? displayName(url), url, PinKind.stream));
    }
  }

  Widget _streams() {
    final s = _source;
    if (s == null) {
      final singles = lib.pins.where(
        (p) =>
            p.kind == PinKind.stream &&
            !lib.sources.any((x) => x.url == p.target),
      );
      if (lib.sources.isEmpty && singles.isEmpty) {
        return _empty(
          Icons.live_tv_outlined,
          'No network streams yet',
          'Add an M3U playlist (for example an IPTV channel list) or a direct '
              'stream URL.',
          FilledButton.icon(
            onPressed: _addStream,
            icon: const Icon(Icons.add_link, size: 18),
            label: const Text('Add stream'),
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              const Text(
                'Channel lists',
                style: TextStyle(color: ConeColors.textMuted, fontSize: 12),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _addStream,
                icon: const Icon(Icons.add_link, size: 18),
                label: const Text('Add stream'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final src in lib.sources) _sourceRow(src),
          if (singles.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text(
              'Single streams',
              style: TextStyle(color: ConeColors.textMuted, fontSize: 12),
            ),
            for (final p in singles)
              ListTile(
                leading: Icon(Icons.language, color: ConeColors.accent),
                title: Text(p.label),
                subtitle: Text(
                  p.target,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => act.play([p.target]),
                trailing: IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => lib.togglePin(p),
                ),
              ),
          ],
        ],
      );
    }

    final groups = <String>{for (final c in s.channels) c.group}.toList()
      ..sort();
    final shown = s.channels
        .where((c) => _channelGroup == null || c.group == _channelGroup)
        .where((c) => _query.isEmpty || c.name.toLowerCase().contains(_query))
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(
            children: [
              Text(
                '${s.channels.length} channels'
                '${s.fetchedAt == null ? '' : ' · updated ${_ago(s.fetchedAt!)}'}',
                style: const TextStyle(
                  color: ConeColors.textMuted,
                  fontSize: 12,
                ),
              ),
              if (s.error != null) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    s.error!,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFFF8A65),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              TextButton.icon(
                onPressed: () =>
                    lib.togglePin(Pin(s.name, s.url, PinKind.stream)),
                icon: Icon(
                  lib.isPinned(s.url)
                      ? Icons.push_pin
                      : Icons.push_pin_outlined,
                  size: 16,
                ),
                label: Text(lib.isPinned(s.url) ? 'Pinned' : 'Pin to Home'),
              ),
              IconButton(
                tooltip: 'Refresh channel list',
                iconSize: 18,
                color: ConeColors.textMuted,
                onPressed: () => lib.refreshSource(s),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (groups.length > 1)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              children: [
                for (final g in [null, ...groups])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(
                        g == null ? 'All' : (g.isEmpty ? 'Other' : g),
                      ),
                      selected: _channelGroup == g,
                      onSelected: (_) => setState(() => _channelGroup = g),
                      selectedColor: ConeColors.accentDim,
                      labelStyle: const TextStyle(fontSize: 12),
                      side: BorderSide(color: ConeColors.border),
                      showCheckmark: false,
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 3,
            ),
            itemCount: shown.length,
            itemBuilder: (_, i) => _channelTile(shown, i),
          ),
        ),
      ],
    );
  }

  Widget _sourceRow(StreamSource src) => Card(
    color: ConeColors.surface,
    margin: const EdgeInsets.only(bottom: 8),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(ConeRadius.md),
      side: BorderSide(color: ConeColors.border),
    ),
    child: ListTile(
      leading: Icon(Icons.live_tv, color: ConeColors.accent),
      title: Text(src.name),
      subtitle: Text(
        src.error ??
            '${src.channels.length} channels · ${src.fetchedAt == null ? 'never updated' : 'updated ${_ago(src.fetchedAt!)}'}',
        style: TextStyle(
          fontSize: 11,
          color: src.error != null
              ? const Color(0xFFFF8A65)
              : ConeColors.textMuted,
        ),
      ),
      onTap: () => setState(() {
        _sourceId = src.id;
        _channelGroup = null;
      }),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: () => lib.refreshSource(src),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => lib.removeSource(src),
          ),
        ],
      ),
    ),
  );

  Widget _channelTile(List<Channel> shown, int i) {
    final c = shown[i];
    return Material(
      color: ConeColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ConeRadius.md),
        side: BorderSide(color: ConeColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(ConeRadius.md),
        // Queue the visible channels so N / P zap between them.
        onTap: () => act.play(shown.map((c) => c.url).toList(), start: i),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                height: 28,
                child: c.logo == null
                    ? const Icon(
                        Icons.tv,
                        color: ConeColors.textMuted,
                        size: 20,
                      )
                    : Image.network(
                        c.logo!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.tv,
                          color: ConeColors.textMuted,
                          size: 20,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  c.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: ConeColors.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  // ---- Playlists -----------------------------------------------------------

  UserPlaylist? get _playlist =>
      lib.playlists.where((p) => p.id == _playlistId).firstOrNull;

  Widget _playlists() {
    final p = _playlist;
    if (p == null) {
      final actions = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton.icon(
            onPressed: () async {
              final name = await _ask('New playlist', 'Name');
              if (name != null) lib.createPlaylist(name);
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New playlist'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: widget.currentQueue().isEmpty
                ? null
                : () async {
                    final name = await _ask('Save queue as playlist', 'Name');
                    if (name != null) {
                      lib.createPlaylist(name, widget.currentQueue());
                    }
                  },
            icon: const Icon(Icons.queue, size: 18),
            label: const Text('Save current queue'),
          ),
        ],
      );
      if (lib.playlists.isEmpty) {
        return _empty(
          Icons.playlist_add,
          'No playlists yet',
          'Save what you are playing as a playlist, or add files from the '
              'library with right-click › Add to playlist.',
          actions,
        );
      }
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Align(alignment: Alignment.centerRight, child: actions),
          const SizedBox(height: 10),
          for (final pl in lib.playlists)
            Card(
              color: ConeColors.surface,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ConeRadius.md),
                side: BorderSide(color: ConeColors.border),
              ),
              child: ListTile(
                leading: Icon(Icons.playlist_play, color: ConeColors.accent),
                title: Text(pl.name),
                subtitle: Text(
                  '${pl.items.length} item${pl.items.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: ConeColors.textMuted,
                  ),
                ),
                onTap: () => setState(() => _playlistId = pl.id),
                trailing: IconButton(
                  tooltip: 'Play',
                  icon: Icon(Icons.play_arrow, color: ConeColors.accent),
                  onPressed: pl.items.isEmpty ? null : () => act.play(pl.items),
                ),
              ),
            ),
        ],
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: p.items.isEmpty ? null : () => act.play(p.items),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Play'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: p.items.isEmpty ? null : () => act.enqueue(p.items),
                icon: const Icon(Icons.queue, size: 18),
                label: const Text('Add to queue'),
              ),
              const Spacer(),
              IconButton(
                tooltip: lib.isPinned(p.id) ? 'Unpin from Home' : 'Pin to Home',
                onPressed: () =>
                    lib.togglePin(Pin(p.name, p.id, PinKind.playlist)),
                icon: Icon(
                  lib.isPinned(p.id) ? Icons.push_pin : Icons.push_pin_outlined,
                  size: 18,
                ),
              ),
              IconButton(
                tooltip: 'Rename',
                onPressed: () async {
                  final n = await _ask(
                    'Rename playlist',
                    'Name',
                    initial: p.name,
                  );
                  if (n != null) lib.renamePlaylist(p, n);
                },
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
              IconButton(
                tooltip: 'Delete playlist',
                onPressed: () {
                  lib.deletePlaylist(p);
                  setState(() => _playlistId = null);
                },
                icon: const Icon(Icons.delete_outline, size: 18),
              ),
            ],
          ),
        ),
        Expanded(
          child: p.items.isEmpty
              ? _empty(
                  Icons.queue_music,
                  'Empty playlist',
                  'Add files from the library with right-click › Add to playlist.',
                  null,
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: p.items.length,
                  itemBuilder: (_, i) {
                    final uri = p.items[i];
                    final h = lib.history[uri];
                    return ListTile(
                      leading: SizedBox(
                        width: 64,
                        height: 36,
                        child: MediaThumb(
                          thumb: h?.thumb,
                          audio: isAudioPath(uri),
                          progress: h?.progress ?? 0,
                        ),
                      ),
                      title: Text(displayName(uri)),
                      subtitle: Text(
                        uri,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: ConeColors.textMuted,
                        ),
                      ),
                      onTap: () => act.play(p.items, start: i),
                      trailing: IconButton(
                        tooltip: 'Remove from playlist',
                        icon: const Icon(Icons.remove_circle_outline, size: 18),
                        onPressed: () => lib.removeFromPlaylist(p, i),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ---- History -------------------------------------------------------------

  Widget _history() {
    final items = lib
        .recent(limit: 500)
        .where((h) => _query.isEmpty || h.title.toLowerCase().contains(_query))
        .toList();
    if (items.isEmpty) {
      return _empty(
        Icons.history,
        'Nothing played yet',
        'Files and streams you play appear here.',
        null,
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: lib.clearHistory,
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: const Text('Clear history'),
          ),
        ),
        for (final h in items)
          ListTile(
            leading: SizedBox(
              width: 64,
              height: 36,
              child: MediaThumb(
                thumb: h.thumb,
                audio: h.isAudio,
                progress: h.progress,
              ),
            ),
            title: Text(h.title),
            subtitle: Text(
              '${h.watched ? 'Finished' : timeLeft(h)} · ${_ago(h.lastPlayed)}',
              style: const TextStyle(fontSize: 11, color: ConeColors.textMuted),
            ),
            onTap: () => act.play([h.uri]),
            trailing: IconButton(
              tooltip: 'Remove from history',
              icon: const Icon(Icons.close, size: 16),
              onPressed: () => lib.forget(h.uri),
            ),
          ),
      ],
    );
  }
}

String _fmtSize(int bytes) {
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  var x = bytes.toDouble();
  var i = 0;
  while (x >= 1024 && i < u.length - 1) {
    x /= 1024;
    i++;
  }
  return '${i == 0 ? x.round() : x.toStringAsFixed(1)} ${u[i]}';
}

class _H extends StatelessWidget {
  final String text;
  const _H(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 11, color: ConeColors.textMuted),
  );
}

class _FileRow extends StatefulWidget {
  final MediaFile file;
  final HistoryEntry? history;
  final bool detail;
  final VoidCallback onTap;
  final List<PopupMenuEntry<VoidCallback>> menu;
  const _FileRow({
    required this.file,
    required this.history,
    required this.detail,
    required this.onTap,
    required this.menu,
  });

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.file, h = widget.history;
    final status = h == null
        ? 'New'
        : (h.watched ? 'Watched' : '${(h.progress * 100).round()}%');
    final m = f.modified;
    final date =
        '${m.year}-${m.month.toString().padLeft(2, '0')}-'
        '${m.day.toString().padLeft(2, '0')}';
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onSecondaryTapDown: (d) async {
          final fn = await showMenu<VoidCallback>(
            context: context,
            position: RelativeRect.fromLTRB(
              d.globalPosition.dx,
              d.globalPosition.dy,
              d.globalPosition.dx,
              d.globalPosition.dy,
            ),
            items: widget.menu,
          );
          fn?.call();
        },
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(ConeRadius.sm),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: _hover ? ConeColors.surface : null,
            child: Row(
              children: [
                SizedBox(
                  width: 58,
                  height: 33,
                  child: MediaThumb(
                    thumb: h?.thumb,
                    audio: f.isAudio,
                    progress: h?.progress ?? 0,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 5,
                  child: Text(
                    f.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: (h?.watched ?? false)
                          ? ConeColors.textMuted
                          : ConeColors.text,
                    ),
                  ),
                ),
                if (widget.detail) ...[
                  Expanded(flex: 2, child: _cell(_fmtSize(f.size))),
                  Expanded(flex: 2, child: _cell(date)),
                  Expanded(flex: 2, child: _cell(status)),
                ] else
                  _cell(status),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cell(String t) => Text(
    t,
    style: const TextStyle(fontSize: 12, color: ConeColors.textMuted),
  );
}
