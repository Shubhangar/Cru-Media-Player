import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../player/opensubtitles.dart';
import '../player/player_controller.dart';
import '../player/subtitle_matching.dart';
import '../theme.dart';
import 'inspector/widgets.dart';

/// Multi-source subtitle loader: this file, a folder for the whole queue,
/// or OpenSubtitles.com.
Future<void> showSubtitleLoader(
  BuildContext context,
  PlayerController c, {
  int initialTab = 0,
  OpenSubtitlesClient Function(String key)? clientFactory,
}) => showDialog(
  context: context,
  builder: (_) => Dialog(
    child: SizedBox(
      width: 640,
      height: 520,
      child: _SubtitleLoader(
        c: c,
        initialTab: initialTab,
        clientFactory: clientFactory ?? OpenSubtitlesClient.new,
      ),
    ),
  ),
);

class _SubtitleLoader extends StatelessWidget {
  final PlayerController c;
  final int initialTab;
  final OpenSubtitlesClient Function(String key) clientFactory;
  const _SubtitleLoader({
    required this.c,
    required this.initialTab,
    required this.clientFactory,
  });

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    initialIndex: initialTab,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
          child: Row(
            children: [
              const TwoToneIcon(Icons.subtitles, Icons.subtitles_outlined),
              const SizedBox(width: 10),
              const Text(
                'Subtitles',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: ConeColors.text,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const TabBar(
          indicatorColor: ConeColors.accent,
          labelColor: ConeColors.accent,
          unselectedLabelColor: ConeColors.textMuted,
          dividerColor: ConeColors.border,
          tabs: [
            Tab(text: 'This file'),
            Tab(text: 'Folder / playlist'),
            Tab(text: 'Online'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              _ThisFile(c: c),
              _Batch(c: c),
              _Online(c: c, clientFactory: clientFactory),
            ],
          ),
        ),
      ],
    ),
  );
}

String _name(String p) => p.split(RegExp(r'[/\\]')).last;

// ---- This file ----------------------------------------------------------------

class _ThisFile extends StatelessWidget {
  final PlayerController c;
  const _ThisFile({required this.c});

  @override
  Widget build(BuildContext context) {
    final uri = c.currentUri;
    final local = uri != null && !uri.contains('://');
    final nearby = local ? sidecarCandidates(uri) : const <String>[];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        FilledButton.icon(
          onPressed: () async {
            final r = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: subtitleExts.toList(),
            );
            final p = r?.files.single.path;
            if (p != null) {
              await c.loadSubtitle(p);
              if (context.mounted) Navigator.pop(context);
            }
          },
          icon: const Icon(Icons.file_open_outlined, size: 18),
          label: const Text('Choose a subtitle file…'),
        ),
        const SizedBox(height: 18),
        Text(
          nearby.isEmpty
              ? 'No matching subtitle files next to this video.'
              : 'Found next to this video',
          style: const TextStyle(color: ConeColors.textMuted, fontSize: 12),
        ),
        for (final s in nearby)
          ListTile(
            dense: true,
            leading: const Icon(
              Icons.subtitles_outlined,
              color: ConeColors.accent,
            ),
            title: Text(_name(s)),
            trailing: const Text(
              'Load',
              style: TextStyle(color: ConeColors.accent),
            ),
            onTap: () async {
              await c.loadSubtitle(s);
              if (context.mounted) Navigator.pop(context);
            },
          ),
      ],
    );
  }
}

// ---- Folder / playlist batch ------------------------------------------------

class _Batch extends StatefulWidget {
  final PlayerController c;
  const _Batch({required this.c});

  @override
  State<_Batch> createState() => _BatchState();
}

class _BatchState extends State<_Batch> {
  Map<String, String>? _matches;
  String? _folder;

  List<String> get _queue =>
      widget.c.queueUris.where((u) => !u.contains('://')).toList();

  Future<void> _pick() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    final subs = Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path)
        .where((p) => subtitleExts.contains(p.split('.').last.toLowerCase()))
        .toList();
    setState(() {
      _folder = dir;
      _matches = matchSubtitles(_queue, subs);
    });
  }

  @override
  Widget build(BuildContext context) {
    final queue = _queue;
    final m = _matches;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Match subtitles in a folder to the ${queue.length} '
            'file${queue.length == 1 ? '' : 's'} in your queue by name or '
            'episode number (S01E02, 1x02).',
            style: const TextStyle(color: ConeColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: queue.isEmpty ? null : _pick,
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            label: Text(_folder == null ? 'Choose folder…' : _name(_folder!)),
          ),
          const SizedBox(height: 12),
          if (m != null)
            Text(
              '${m.length} of ${queue.length} matched',
              style: const TextStyle(color: ConeColors.text),
            ),
          Expanded(
            child: ListView(
              children: [
                for (final q in queue)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      m?[q] != null
                          ? Icons.check_circle
                          : Icons.remove_circle_outline,
                      size: 18,
                      color: m?[q] != null
                          ? ConeColors.accent
                          : ConeColors.textMuted,
                    ),
                    title: Text(_name(q)),
                    subtitle: Text(
                      m?[q] == null ? 'No match' : _name(m![q]!),
                      style: const TextStyle(
                        fontSize: 11,
                        color: ConeColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: m == null || m.isEmpty
                  ? null
                  : () async {
                      await widget.c.assignSubtitles(m);
                      widget.c.notify(
                        'Subtitles matched for ${m.length} files',
                      );
                      if (context.mounted) Navigator.pop(context);
                    },
              child: const Text('Use these subtitles'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Online (OpenSubtitles) ------------------------------------------------

class _Online extends StatefulWidget {
  final PlayerController c;
  final OpenSubtitlesClient Function(String key) clientFactory;
  const _Online({required this.c, required this.clientFactory});

  @override
  State<_Online> createState() => _OnlineState();
}

class _OnlineState extends State<_Online> {
  late final _key = TextEditingController(
    text: widget.c.settings.openSubtitlesKey,
  );
  late final _query = TextEditingController(
    text: widget.c.currentUri == null
        ? ''
        : queryFromFileName(widget.c.currentUri!),
  );
  late final _langs = TextEditingController(
    text: widget.c.subtitleLanguages.isEmpty
        ? 'en'
        : widget.c.subtitleLanguages,
  );
  List<SubtitleResult>? _results;
  String? _status;
  bool _busy = false;

  PlayerController get c => widget.c;
  bool get _hasKey => c.settings.openSubtitlesKey.isNotEmpty;
  OpenSubtitlesClient get _client =>
      widget.clientFactory(c.settings.openSubtitlesKey);

  @override
  void dispose() {
    _key.dispose();
    _query.dispose();
    _langs.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await f();
    } catch (e) {
      if (mounted) setState(() => _status = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _hashOf(String? uri) {
    if (uri == null || uri.contains('://')) return null;
    try {
      return openSubtitlesHash(uri);
    } catch (_) {
      return null;
    }
  }

  /// Next to the video when possible, else in the app's support folder.
  Future<String> _target(String media, SubtitleResult r) async {
    final ext = r.fileName.contains('.') ? r.fileName.split('.').last : 'srt';
    final base = media.contains('://')
        ? 'stream'
        : media.substring(0, media.lastIndexOf('.'));
    final beside = '$base.${r.language}.$ext';
    try {
      final f = File(beside)..createSync();
      f.deleteSync();
      return beside;
    } catch (_) {
      final dir = Directory(
        '${(await getApplicationSupportDirectory()).path}/subtitles',
      )..createSync(recursive: true);
      return '${dir.path}/${_name(beside)}';
    }
  }

  Future<void> _search() => _run(() async {
    final r = await _client.search(
      hash: _hashOf(c.currentUri),
      query: _query.text.trim(),
      languages: _langs.text.trim(),
    );
    setState(() {
      _results = r;
      _status = r.isEmpty ? 'No subtitles found.' : null;
    });
  });

  Future<void> _download(SubtitleResult r) => _run(() async {
    final uri = c.currentUri!;
    final path = await _client.download(r, await _target(uri, r));
    await c.assignSubtitles({uri: path});
    if (mounted) Navigator.pop(context);
  });

  Future<void> _fetchQueue() => _run(() async {
    final got = <String, String>{};
    final items = c.queueUris.where((u) => !u.contains('://')).toList();
    for (var i = 0; i < items.length; i++) {
      setState(() => _status = 'Fetching ${i + 1} of ${items.length}…');
      final hits = await _client.search(
        hash: _hashOf(items[i]),
        query: queryFromFileName(items[i]),
        languages: _langs.text.trim(),
      );
      if (hits.isEmpty) continue;
      got[items[i]] = await _client.download(
        hits.first,
        await _target(items[i], hits.first),
      );
    }
    await c.assignSubtitles(got);
    setState(
      () => _status =
          'Found subtitles for ${got.length} of ${items.length} files.',
    );
  });

  @override
  Widget build(BuildContext context) {
    if (!_hasKey) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Search OpenSubtitles.com',
              style: TextStyle(fontSize: 15, color: ConeColors.text),
            ),
            const SizedBox(height: 6),
            const Text(
              'OpenSubtitles needs a free API key. Create an account at '
              'opensubtitles.com, open your profile › API consumers, create a '
              'consumer and paste its key here. It is stored only on this '
              'computer.',
              style: TextStyle(color: ConeColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _key,
              decoration: const InputDecoration(hintText: 'API key'),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () => setState(
                () => c.settings.openSubtitlesKey = _key.text.trim(),
              ),
              child: const Text('Save key'),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _query,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Title',
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _langs,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'en,de',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy || c.currentUri == null ? null : _search,
                child: const Text('Search'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  _status ??
                      'Searches by this file\'s fingerprint and title; exact '
                          'matches come first.',
                  style: const TextStyle(
                    color: ConeColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
              if (_busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView(
              children: [
                for (final r in _results ?? const <SubtitleResult>[])
                  ListTile(
                    dense: true,
                    title: Text(r.release.isEmpty ? r.fileName : r.release),
                    subtitle: Wrap(
                      spacing: 6,
                      children: [
                        _badge(r.language.toUpperCase()),
                        if (r.hashMatch) _badge('Exact match', accent: true),
                        if (r.hearingImpaired) _badge('HI'),
                        Text(
                          '${r.downloads} downloads',
                          style: const TextStyle(
                            fontSize: 11,
                            color: ConeColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    trailing: TextButton(
                      onPressed: _busy ? null : () => _download(r),
                      child: const Text('Download'),
                    ),
                  ),
              ],
            ),
          ),
          Row(
            children: [
              TextButton(
                onPressed: () =>
                    setState(() => c.settings.openSubtitlesKey = ''),
                child: const Text(
                  'Change API key',
                  style: TextStyle(color: ConeColors.textMuted),
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _busy || c.queueUris.length < 2 ? null : _fetchQueue,
                icon: const Icon(Icons.playlist_add_check, size: 18),
                label: const Text('Fetch for whole queue'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge(String t, {bool accent = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(ConeRadius.sm),
      border: Border.all(color: accent ? ConeColors.accent : ConeColors.border),
    ),
    child: Text(
      t,
      style: TextStyle(
        fontSize: 10,
        color: accent ? ConeColors.accent : ConeColors.textMuted,
      ),
    ),
  );
}
